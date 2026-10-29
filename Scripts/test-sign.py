#!/usr/bin/env python3
"""Tests for Scripts/sign.sh on a copy of a system binary, signed ad hoc ("-"): never a real identity, so never a keychain prompt."""
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parent / "sign.sh"


def details(path):
    return subprocess.run(["codesign", "-dv", str(path)], capture_output=True, text=True).stderr


class SignTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.binary = pathlib.Path(self.temp.name) / "ask-under-test"  # not "ask": codesign names an unnamed signature after the file
        shutil.copy("/usr/bin/true", self.binary)
        subprocess.run(["codesign", "--remove-signature", str(self.binary)], check=True, capture_output=True)

    def sign(self, identity):
        env = dict(os.environ)
        env.pop("ASK_SIGNING_IDENTITY", None)
        if identity is not None:
            env["ASK_SIGNING_IDENTITY"] = identity
        return subprocess.run(["sh", str(SCRIPT), str(self.binary)], env=env, capture_output=True, text=True)

    def test_signs_with_the_identity_under_the_identifier_ask(self):
        result = self.sign("-")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Identifier=ask", details(self.binary).splitlines())
        subprocess.run(["codesign", "--verify", str(self.binary)], check=True)

    def test_without_an_identity_it_leaves_the_binary_and_says_so(self):
        before = self.binary.read_bytes()
        result = self.sign(None)
        self.assertEqual(result.returncode, 0)
        self.assertIn("ASK_SIGNING_IDENTITY", result.stdout + result.stderr)
        self.assertEqual(self.binary.read_bytes(), before)

    def test_a_failed_signing_fails_the_script(self):
        result = self.sign("No Such Identity (XXXXXXXXXX)")
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
