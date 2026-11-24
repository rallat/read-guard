"""Tests for read-guard.sh. Needs bash and jq. Skipped when jq is missing."""
import json
import os
import shutil
import subprocess
import tempfile
import unittest

HOOK = os.path.join(os.path.dirname(__file__), "..", "read-guard.sh")


@unittest.skipUnless(shutil.which("jq"), "jq not installed")
class ReadGuardTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.env = dict(os.environ, TMPDIR=self.tmp.name,
                        READ_GUARD_LOG_DIR=os.path.join(self.tmp.name, "log"))
        self.env.pop("READ_GUARD", None)

    def write(self, name, lines):
        path = os.path.join(self.tmp.name, name)
        with open(path, "w") as f:
            f.write("\n".join(lines) + "\n")
        return path

    def big_py(self):
        body = []
        for i in range(40):
            body.append(f"def func_{i}():")
            body.extend(["    x = 1"] * 9)
        return self.write("big.py", body)

    def run_hook(self, tool_input, env=None):
        payload = json.dumps({"tool_name": "Read", "session_id": "s1", "tool_input": tool_input})
        return subprocess.run(["bash", HOOK], input=payload, capture_output=True,
                              text=True, env=env or self.env)

    def test_large_whole_file_read_is_denied_with_outline(self):
        r = self.run_hook({"file_path": self.big_py()})
        out = json.loads(r.stdout)["hookSpecificOutput"]
        self.assertEqual(out["permissionDecision"], "deny")
        self.assertIn("L1-10  def func_0():", out["permissionDecisionReason"])

    def test_second_identical_read_passes(self):
        path = self.big_py()
        self.run_hook({"file_path": path})
        self.assertEqual(self.run_hook({"file_path": path}).stdout, "")

    def test_ranged_read_passes(self):
        r = self.run_hook({"file_path": self.big_py(), "offset": 1, "limit": 20})
        self.assertEqual(r.stdout, "")

    def test_small_file_passes(self):
        r = self.run_hook({"file_path": self.write("small.py", ["def a():", "    pass"])})
        self.assertEqual(r.stdout, "")

    def test_secret_looking_path_passes(self):
        path = self.write("secret_config.py", [f"def f{i}(): pass" for i in range(400)])
        self.assertEqual(self.run_hook({"file_path": path}).stdout, "")

    def test_disabled_by_env(self):
        env = dict(self.env, READ_GUARD="off")
        self.assertEqual(self.run_hook({"file_path": self.big_py()}, env=env).stdout, "")


if __name__ == "__main__":
    unittest.main()
