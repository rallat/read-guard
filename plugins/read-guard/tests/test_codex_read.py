import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest


ADAPTER = Path(__file__).resolve().parents[1] / "codex_read.py"


@unittest.skipUnless(shutil.which("jq"), "jq not installed")
class CodexReadTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name) / "project"
        self.root.mkdir()
        self.target = self.root / "long file.md"
        self.target.write_text("# One\n" + "line\n" * 320 + "# Two\n")
        self.env = dict(os.environ, TMPDIR=tmp.name, READ_GUARD="on",
                        READ_GUARD_LOG_DIR=tmp.name)

    def run_hook(self, command, **arguments):
        event = {"tool_name": "Bash", "cwd": str(self.root), "session_id": "s1",
                 "tool_input": {"command": command, **arguments}}
        result = subprocess.run([sys.executable, "-I", str(ADAPTER)],
                                input=json.dumps(event), capture_output=True,
                                text=True, env=self.env, check=True)
        return result.stdout

    def test_outline_then_repeat(self):
        command = 'cat -- "long file.md"'
        decision = json.loads(self.run_hook(command))["hookSpecificOutput"]
        self.assertEqual(decision["permissionDecision"], "deny")
        self.assertIn("L1-321  # One", decision["permissionDecisionReason"])
        self.assertEqual(self.run_hook(command), "")

    def test_rtk_and_working_directory(self):
        (self.root / "src").mkdir()
        self.target.rename(self.root / "src" / self.target.name)
        result = self.run_hook("rtk proxy cat 'long file.md'", workdir="src")
        self.assertIn("L1-321", result)

    def test_complex_and_partial_commands_pass(self):
        for command in ["cat 'long file.md' | head", "cat *.md", "cat $FILE",
                        "cat 'long file.md' another.md", "sed -n '1,10p' file",
                        "cat missing.md", "cat -n 'long file.md'"]:
            with self.subTest(command=command):
                self.assertEqual(self.run_hook(command), "")

    def test_outside_project_passes(self):
        outside = self.root.parent / "outside.md"
        self.target.rename(outside)
        self.target.symlink_to(outside)
        for path in [outside, self.target]:
            self.assertEqual(self.run_hook("cat " + shlex.quote(str(path))), "")
