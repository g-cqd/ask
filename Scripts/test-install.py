#!/usr/bin/env python3
"""Tests of Scripts/install.sh in a copy of the tree where the build and the budgets are stubs: no ask is built, measured or
installed anywhere but a temporary directory."""
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parent / "install.sh"


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name).resolve()
        self.scripts = self.root / "tree" / "Scripts"
        self.scripts.mkdir(parents=True)
        shutil.copy(SCRIPT, self.scripts / "install.sh")
        self.target = self.root / "bin"
        self.stub("build-release.sh", '#!/bin/sh\necho "$@" > built-with\nmkdir -p .build/release\n'
                  'printf \'#!/bin/sh\\necho new\\n\' > .build/release/ask\nchmod +x .build/release/ask\n')
        self.budgets(0)

    def stub(self, name, text):
        path = self.scripts / name
        path.write_text(text)
        path.chmod(0o755)

    def budgets(self, status):
        self.stub("measure-budgets.py", f'import sys\nopen("measured", "w").write(" ".join(sys.argv[1:]))\nsys.exit({status})\n')

    def install(self, *arguments, home=None):
        env = dict(os.environ, HOME=str(home or self.root / "home"))
        return subprocess.run(["sh", str(self.scripts / "install.sh"), *arguments], env=env, capture_output=True, text=True)

    def installed(self):
        return subprocess.run([str(self.target / "ask")], capture_output=True, text=True).stdout.strip()

    def an_older_ask(self):
        self.target.mkdir()
        (self.target / "ask").write_text("#!/bin/sh\necho old\n")
        (self.target / "ask").chmod(0o755)

    def leftovers(self):
        return [entry.name for entry in self.target.iterdir() if entry.name != "ask"]

    def test_within_budget_the_built_binary_replaces_the_one_there(self):
        self.an_older_ask()
        result = self.install(str(self.target))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.installed(), "new")
        self.assertEqual(os.stat(self.target / "ask").st_mode & 0o777, 0o755)
        self.assertEqual(self.leftovers(), [], "nothing staged is left behind")
        self.assertIn(f"Installed {self.target}/ask", result.stdout)

    def test_the_shipping_binary_is_built_and_that_one_is_measured(self):
        self.install(str(self.target))
        tree = self.scripts.parent
        self.assertEqual((tree / "built-with").read_text().strip(), "--product ask")
        self.assertEqual((tree / "measured").read_text(), ".build/release/ask 12")

    def test_over_budget_nothing_is_installed_and_the_one_there_stays(self):
        self.an_older_ask()
        self.budgets(1)
        result = self.install(str(self.target))
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.installed(), "old")
        self.assertEqual(self.leftovers(), [])
        self.assertIn("Not installed", result.stderr)

    def test_over_budget_with_nothing_there_installs_nothing(self):
        self.budgets(1)
        self.assertEqual(self.install(str(self.target)).returncode, 1)
        self.assertFalse((self.target / "ask").exists())

    def test_a_build_that_fails_measures_and_installs_nothing(self):
        self.an_older_ask()
        self.stub("build-release.sh", "#!/bin/sh\nexit 3\n")
        result = self.install(str(self.target))
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.scripts.parent / "measured").exists())
        self.assertEqual(self.installed(), "old")

    def test_a_binary_that_does_not_run_is_not_installed(self):
        self.an_older_ask()
        self.stub("build-release.sh", '#!/bin/sh\nmkdir -p .build/release\nprintf \'#!/bin/sh\\nexit 9\\n\' > .build/release/ask\n'
                  'chmod +x .build/release/ask\n')
        result = self.install(str(self.target))
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.installed(), "old")
        self.assertEqual(self.leftovers(), [])
        self.assertIn("does not run", result.stderr)

    def test_without_a_directory_it_installs_in_the_home_s_local_bin(self):
        home = self.root / "another home"
        result = self.install(home=home)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((home / ".local" / "bin" / "ask").exists())


if __name__ == "__main__":
    unittest.main()
