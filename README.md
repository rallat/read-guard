# Read Guard

Find the symbol, then read the relevant lines. When a coding agent requests a large source or Markdown file, Read Guard gives it an outline with line ranges. The agent can read a range immediately or repeat the original request to see the whole file.

## Install

Use a macOS or Linux environment with Bash, jq and shasum on PATH. The Codex adapter also requires Python 3. The catalogs below install the plugin from this repository.

### Claude Code

```sh
claude plugin marketplace add rallat/read-guard
claude plugin install read-guard@rallat-tools
```

Open a fresh session. The hook runs before Claude Code's built-in `Read` tool. Requests that specify an offset or limit pass through immediately.

### Codex CLI

```sh
codex plugin marketplace add rallat/read-guard
codex plugin add read-guard@rallat-tools
```

Open a fresh session, run `/hooks`, and review and trust the Read Guard hook. Codex sends shell commands to its `Bash` hook. The adapter recognizes a literal `cat FILE` or `cat -- FILE`, optionally prefixed with `rtk` or `rtk proxy`. It accepts simple quoted paths with spaces and resolves the file inside the hook's working directory, honoring an explicit command working directory within that tree. Compound commands, pipes, flags, shell expansion, multiple operands and other tools pass through. The adapter never executes the incoming command.

## Behavior

The default thresholds are **over 300 lines or over 20,000 bytes**. For a supported extension with recognizable declarations or headings, the first whole-file read returns up to 80 outline entries. Repeating the read in the same session allows the full file if its modification time is unchanged. The outline uses language-specific patterns and can miss declarations. Small files, paths that look like secrets, and files with no outline pass through.

| Environment variable | Default | Purpose |
| --- | --- | --- |
| `READ_GUARD` | `on` | Set to `off` before starting the client to disable the hook. |
| `READ_GUARD_MIN_LINES` | `300` | Line threshold. |
| `READ_GUARD_MIN_BYTES` | `20000` | Byte threshold. |
| `READ_GUARD_MAX_ENTRIES` | `80` | Maximum outline entries. |
| `READ_GUARD_LOG_DIR` | `~/.cache/read-guard` | Local decision log, including file paths. |

Repeat-read markers live in a per-user directory under the system temporary directory. The hook runs locally and makes no network requests.

## Development

```sh
python3 -m unittest discover -s plugins/read-guard/tests -v
```

The Bash hook and its original tests were extracted from the Agent Lane Playbook. The Codex adapter and marketplace packaging are part of this standalone distribution. [MIT license](LICENSE)
