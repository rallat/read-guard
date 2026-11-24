# Read Guard

Read Guard is a local plugin for Claude Code and Codex. The first time an agent tries to read a large source or Markdown file in full, the hook returns an outline of declarations or headings with their line ranges. The agent can jump to the part it needs. If it needs the whole file, it can repeat the request.

## Why I created it

I built Read Guard after auditing how agents read code in long sessions. In one session, just 61 reads accounted for almost a quarter of all the characters returned by file reads. Each of those calls brought in an entire file of more than 300 lines. That output could stay in the conversation for many more turns.

I wanted the agent to find the symbol, then read the relevant lines. Putting the outline in the response gives it a place to start at the moment it asks for the file. The repeat-read option matters because sometimes understanding a change takes the whole file.

## What we measured

We compared two sessions from one project, before and after adding the written rule to read an outline or symbol first. We counted a whole-file read when it supplied neither an offset nor a limit and the result exceeded 300 lines.

| Session | Agents | All read calls | Whole-file reads over 300 lines | Share of all characters returned by reads |
| --- | ---: | ---: | ---: | ---: |
| Before the rule, Oct 28–30, 2026 | 108 | 1,083 | 61 (5.6% of calls) | 22.7% |
| After the rule, Nov 15–20, 2026 | 246 | 2,859 | 5 (0.2% of calls) | 2.0% |

We also estimated what replacing each large whole-file read with a typical range read could have saved. We used the median range size, estimated one token per four characters, and counted the initial read plus later turns in that agent's session. The estimate was **17.9 million tokens** in the first session (3.35% of subagent tokens) and **3.9 million** in the second (0.18%).

The sessions involved different tasks, and the audit did not verify hook activation for each agent. Those limits leave the standalone plugin's effect on token usage and billing unmeasured.

## Install

Use a macOS or Linux environment with Bash, jq and shasum on PATH. The Codex adapter also requires Python 3. The catalogs below install the plugin from this repository.

### Claude Code

```sh
claude plugin marketplace add rallat/read-guard
claude plugin install read-guard@rallat-tools
```

Open a fresh session. To check the installation, run `claude plugin details read-guard@rallat-tools` in your terminal and look for one `PreToolUse` hook. It runs before Claude Code's built-in `Read` tool. Requests that specify an offset or limit pass through immediately.

### Codex CLI

```sh
codex plugin marketplace add rallat/read-guard
codex plugin add read-guard@rallat-tools
```

Open a fresh session, run `/hooks`, and review and trust the `PreToolUse` hook from `read-guard@rallat-tools`. Codex skips a newly installed hook until you trust it.

For a question about a particular function, type, or caller, invoke `$read-guard:read-symbol` in your prompt. Codex can also select it automatically for matching questions. The skill finds the symbol, reads the relevant lines, and cites the source. It works independently of hook trust.

Codex sends shell commands to its `Bash` hook. The adapter recognizes a literal `cat FILE` or `cat -- FILE`, optionally prefixed with `rtk` or `rtk proxy`. It accepts simple quoted paths with spaces and resolves the file relative to the working directory reported by the hook. Compound commands, pipes, flags, shell expansion, multiple operands and other tools pass through. The adapter never executes the incoming command.

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
