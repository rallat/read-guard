#!/usr/bin/env bash
# read-guard: PreToolUse hook for the Read tool.
# Denies a whole-file Read of a large code or markdown file and returns an outline
# with source line ranges, so the agent can re-read a range.
#
# Passes through (exit 0, no output) when:
#   READ_GUARD=off; offset/limit present; unsupported extension; file below
#   threshold; secret-looking path; the same read was already denied once this
#   session (second identical read passes); or the outline is empty / any error.
# Fails open: any error exits 0.
#
# Env:
#   READ_GUARD=off            disable
#   READ_GUARD_MIN_LINES      line threshold (default 300)
#   READ_GUARD_MIN_BYTES      byte threshold (default 20000)
#   READ_GUARD_MAX_ENTRIES    outline entries shown (default 80)
#   READ_GUARD_LOG_DIR        JSON Lines decision log (default ~/.cache/read-guard)

[[ "${READ_GUARD:-on}" == "off" ]] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

MIN_LINES="${READ_GUARD_MIN_LINES:-300}"
MIN_BYTES="${READ_GUARD_MIN_BYTES:-20000}"
MAX_ENTRIES="${READ_GUARD_MAX_ENTRIES:-80}"
for number in "$MIN_LINES" "$MIN_BYTES" "$MAX_ENTRIES"; do
  [[ "$number" =~ ^(0|[1-9][0-9]{0,8})$ ]] || exit 0
done

input="$(cat)" || exit 0
tool=$(jq -r '.tool_name // empty' <<<"$input" 2>/dev/null) || exit 0
[[ "$tool" == "Read" ]] || exit 0

file=$(jq -r '.tool_input.file_path // empty' <<<"$input")
[[ -n "$file" ]] || exit 0
# Only outline files beneath the host's working root, before its read runs.
root=$(jq -r '.cwd // empty' <<<"$input")
if [[ -n "$root" ]]; then
  root=$(cd -P -- "$root" 2>/dev/null && pwd -P) || exit 0
  [[ "$file" == /* ]] || file="$root/$file"
  parent=$(cd -P -- "$(dirname -- "$file")" 2>/dev/null && pwd -P) || exit 0
  file="$parent/${file##*/}"
  [[ "$file" == "${root%/}/"* ]] || exit 0
fi
[[ -f "$file" && ! -L "$file" ]] || exit 0

# Ranged read: always passes.
ranged=$(jq -r '[.tool_input.offset, .tool_input.limit] | map(select(. != null)) | length' <<<"$input")
[[ "$ranged" == "0" ]] || exit 0

# Never outline or block anything that looks like a secret.
shopt -s nocasematch
if [[ "$file" =~ (\.env|secret|credential|\.pem$|\.key$|id_rsa|id_ed25519|\.p12$|\.keystore$|token) ]]; then
  exit 0
fi
shopt -u nocasematch

ext="${file##*.}"; ext="$(tr '[:upper:]' '[:lower:]' <<<"$ext")"
case "$ext" in
  swift)            re='^[[:space:]]*((public|private|fileprivate|internal|open|final|static|override|mutating|nonisolated|@[A-Za-z]+)[[:space:]]+)*(func|class|struct|enum|protocol|extension|actor|init|subscript)\b' ;;
  py)               re='^[[:space:]]*(async[[:space:]]+)?(def|class)[[:space:]]' ;;
  go)               re='^(func|type|var|const)[[:space:]]' ;;
  kt|kts)           re='^[[:space:]]*((public|private|internal|protected|open|abstract|override|suspend|data|sealed|inline)[[:space:]]+)*(fun|class|object|interface)[[:space:]]' ;;
  ts|tsx|js|jsx)    re='^[[:space:]]*(export[[:space:]]+)?(default[[:space:]]+)?(async[[:space:]]+)?(function|class|interface|type|enum|const[[:space:]]+[A-Za-z_]+[[:space:]]*=[[:space:]]*(async[[:space:]]*)?\()' ;;
  java|rs|rb|sh|c|h|cc|cpp|m) re='^[[:space:]]*((pub|public|private|protected|static|final|abstract)[[:space:]]+)*(fn|struct|enum|trait|impl|class|interface|def|module|function)[[:space:]]|^[a-z_]+\(\)[[:space:]]*\{' ;;
  md)               re='^#{1,6}[[:space:]]' ;;
  *) exit 0 ;;
esac

lines=$(wc -l <"$file" | tr -d ' ')
bytes=$(wc -c <"$file" | tr -d ' ')
(( lines > MIN_LINES || bytes > MIN_BYTES )) || exit 0

# Second identical read in a session passes through.
sid=$(jq -r '.session_id // "nosession"' <<<"$input")
if ! mtime=$(stat -c %Y "$file" 2>/dev/null); then
  mtime=$(stat -f %m "$file" 2>/dev/null) || exit 0
fi
umask 077
state_dir="${TMPDIR:-/tmp}/read-guard-$UID"
mkdir -m 700 "$state_dir" 2>/dev/null || [[ -d "$state_dir" && -O "$state_dir" && ! -L "$state_dir" ]] || exit 0
key=$(printf '%s|%s|%s' "$sid" "$file" "$mtime" | shasum | cut -c1-24)
log_dir="${READ_GUARD_LOG_DIR:-$HOME/.cache/read-guard}"; mkdir -p "$log_dir" 2>/dev/null
log() { printf '{"ts":"%s","action":"%s","lines":%s,"file":%s}\n' "$(date -u +%FT%TZ)" "$1" "$lines" "$(jq -Rn --arg f "$file" '$f')" >>"$log_dir/decisions.jsonl" 2>/dev/null; }
if [[ -e "$state_dir/$key" ]]; then log pass-repeat; exit 0; fi

# Outline with source line ranges: each entry spans to the line before the next entry.
outline=$(LC_ALL=C grep -nE "$re" "$file" 2>/dev/null | head -n "$MAX_ENTRIES" | awk -F: -v total="$lines" '
  { n=$1; sub(/^[0-9]+:/, ""); gsub(/^[ \t]+/, ""); s=substr($0,1,110); start[NR]=n; sig[NR]=s }
  END { for (i=1;i<=NR;i++) { e=(i<NR)?start[i+1]-1:total; printf "L%d-%d  %s\n", start[i], e, sig[i] } }') || exit 0
[[ -n "$outline" ]] || { log pass-empty-outline; exit 0; }

: >"$state_dir/$key" 2>/dev/null
log deny

reason="Whole-file read paused by read-guard ($lines lines, $bytes bytes). Use the relevant line range below, or repeat the same read for the full file.
$file
$outline"
jq -n --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
