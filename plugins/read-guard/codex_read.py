"""Translate one literal Codex cat command into a Read event for the shared hook."""

import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys


def read_target(event):
    arguments = event["tool_input"]
    command = arguments.get("command", "")
    if event["tool_name"] != "Bash" or not isinstance(command, str):
        return None
    # Handle literal paths only. Never run the incoming command or expand its input.
    if not re.fullmatch(r"""[\w./ '"\-\t]+""", command):
        return None
    words = shlex.split(command)
    if words[:2] == ["rtk", "proxy"]:
        words = words[2:]
    elif words[:1] == ["rtk"]:
        words = words[1:]
    if words[:1] != ["cat"]:
        return None
    operands = words[1:]
    if operands[:1] == ["--"]:
        operands = operands[1:]
    if len(operands) != 1 or not operands[0] or operands[0].startswith("-"):
        return None
    root = Path(event["cwd"]).resolve(strict=True)
    workdir = arguments.get("workdir") or arguments.get("cwd") or "."
    path = (root / workdir / operands[0]).resolve(strict=True)
    return path if root in path.parents and path.is_file() else None


def main():
    if os.environ.get("READ_GUARD") == "off":
        return
    event = json.load(sys.stdin)
    target = read_target(event)
    if target is None:
        return
    event.update(tool_name="Read", tool_input={"file_path": str(target)})
    hook = Path(__file__).with_name("read-guard.sh")
    subprocess.run(["bash", str(hook)], input=json.dumps(event), text=True)


if __name__ == "__main__":
    try:
        main()
    except (AttributeError, KeyError, OSError, RuntimeError, TypeError, ValueError):
        pass  # An unavailable file or an unrecognized event leaves the tool alone.
