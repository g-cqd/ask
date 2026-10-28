#!/usr/bin/env python3
"""Throwaway-repository tests for shared number claims and the no-push landing workflow."""
import concurrent.futures
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from record_numbers import duplicates, git, next_number


class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = pathlib.Path(self.temp.name)
        self.root = self.base / "main checkout"
        self.root.mkdir()
        self.run_git("init", "-q", "-b", "main")
        self.run_git("config", "user.name", "Fixture")
        self.run_git("config", "user.email", "fixture@example.invalid")
        os.environ["ASK_LAND_EMAIL"] = "fixture@example.invalid"
        for directory in ["adr", "roadmap", "diary"]:
            (self.root / "docs" / directory).mkdir(parents=True)
        (self.root / "Scripts").mkdir()
        for name in ["land.py", "land.sh", "next-number.py", "next-number.sh", "record_numbers.py", "check-records.py"]:
            shutil.copy(HERE / name, self.root / "Scripts" / name)
        self.quality("exit 0")
        self.record("adr", "0001-first.md")
        self.record("diary", "2026-10-25-01.md")
        self.commit("fixture")
        self.remote = self.base / "remote.git"
        subprocess.run(["git", "clone", "--bare", "--quiet", str(self.root), str(self.remote)], check=True)
        self.run_git("remote", "add", "origin", str(self.remote))
        self.run_git("fetch", "-q", "origin")

    def run_git(self, *args, root=None):
        return git(root or self.root, *args).stdout.strip()

    def record(self, kind, name, root=None):
        path = (root or self.root) / "docs" / kind / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("# Fixture\n")

    def commit(self, message, root=None):
        self.run_git("add", "-A", root=root)
        self.run_git("commit", "-q", "-m", message, root=root)

    def quality(self, body, root=None):
        path = (root or self.root) / "Scripts" / "quality.sh"
        path.write_text("#!/bin/sh\nset -eu\n" + body + "\n")
        path.chmod(0o755)

    def task(self):
        task = self.base / "task checkout"
        self.run_git("worktree", "add", "-q", "-b", "task", str(task))
        return task

    def invoke(self, name, *args, root=None):
        return subprocess.run([sys.executable, str((root or self.root) / "Scripts" / name), *args],
                              cwd=root or self.root, capture_output=True, text=True, timeout=60)

    def test_eight_concurrent_claimants_get_distinct_numbers(self):
        def claim(_):
            p = self.invoke("next-number.py", "adr", "--claim")
            self.assertEqual(p.returncode, 0, p.stderr)
            return p.stdout.strip()
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            numbers = list(pool.map(claim, range(8)))
        self.assertEqual(set(numbers), {f"{n:04d}" for n in range(2, 10)})

    def test_branch_only_and_uncommitted_worktree_records_count(self):
        task = self.task()
        self.record("adr", "0037-branch-only.md", root=task)
        self.commit("unmerged record", root=task)
        self.run_git("checkout", "--detach", "main", root=task)
        self.assertFalse((task / "docs/adr/0037-branch-only.md").exists())
        self.record("roadmap", "0042-uncommitted.md", root=task)
        self.assertEqual(next_number(self.root, "adr", "", False), "0038")
        self.assertEqual(next_number(self.root, "roadmap", "", False), "0043")

    def test_diary_claims_are_per_day(self):
        self.assertEqual(next_number(self.root, "diary", "2026-10-25", True), "02")
        self.assertEqual(next_number(self.root, "diary", "2026-10-26", True), "01")

    def test_only_published_records_release_claims(self):
        self.assertEqual(next_number(self.root, "adr", "", True), "0002")
        self.record("adr", "0002-published.md")
        self.commit("locally landed record")
        self.assertEqual(next_number(self.root, "adr", "", False), "0003")
        ref = "refs/claims/adr-0002"
        self.assertEqual(git(self.root, "show-ref", "--verify", "--quiet", ref, check=False).returncode, 0)
        self.run_git("update-ref", "refs/remotes/origin/main", "HEAD")
        self.assertEqual(next_number(self.root, "adr", "", False), "0003")
        self.assertNotEqual(git(self.root, "show-ref", "--verify", "--quiet", ref, check=False).returncode, 0)

    def test_duplicate_detection_covers_all_three_kinds(self):
        self.assertEqual(len(duplicates([
            "docs/adr/0002-a.md", "docs/adr/0002-b.md", "docs/roadmap/0003-a.md", "docs/roadmap/0003-b.md",
            "docs/diary/2026-10-25-01.md", "docs/diary/2026-10-25-1.md"])), 3)
        self.assertFalse(duplicates(["docs/diary/2026-10-25-01.md", "docs/diary/2026-10-26-01.md"]))

    def test_landing_runs_gate_fast_forwards_and_removes_only_task_without_pushing(self):
        task = self.task()
        self.record("adr", "0002-task.md", root=task)
        self.quality("echo ran > ../gate-ran", root=task)
        self.commit("task", root=task)
        wanted = self.run_git("rev-parse", "HEAD", root=task)
        published = self.run_git("rev-parse", "main", root=self.remote)
        p = self.invoke("land.py", root=task)
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        self.assertEqual(self.run_git("rev-parse", "HEAD"), wanted)
        self.assertEqual((self.base / "gate-ran").read_text().strip(), "ran")
        self.assertFalse(task.exists())
        self.assertNotEqual(git(self.root, "show-ref", "--verify", "--quiet", "refs/heads/task", check=False).returncode, 0)
        self.assertEqual(self.run_git("rev-parse", "main", root=self.remote), published)

    def test_failed_gate_keeps_main_and_task(self):
        task = self.task()
        self.quality("exit 1", root=task)
        self.commit("red gate", root=task)
        before = self.run_git("rev-parse", "HEAD")
        p = self.invoke("land.py", root=task)
        self.assertNotEqual(p.returncode, 0)
        self.assertTrue(task.exists())
        self.assertEqual(self.run_git("rev-parse", "HEAD"), before)

    def test_duplicate_record_is_refused_before_landing(self):
        task = self.task()
        self.record("adr", "0001-duplicate.md", root=task)
        self.commit("duplicate", root=task)
        p = self.invoke("land.py", root=task)
        self.assertNotEqual(p.returncode, 0)
        self.assertIn("duplicate adr", p.stderr)

    def test_new_diary_gap_is_refused(self):
        task = self.task()
        self.record("diary", "2026-10-25-03.md", root=task)
        self.commit("gap", root=task)
        p = self.invoke("land.py", root=task)
        self.assertNotEqual(p.returncode, 0)
        self.assertIn("new diary gap", p.stderr)

    def test_duplicate_gate_fails_on_disk_and_recovers_after_removal(self):
        self.assertEqual(self.invoke("check-records.py").returncode, 0)
        self.record("adr", "0001-other.md")
        p = self.invoke("check-records.py")
        self.assertEqual(p.returncode, 1)
        self.assertIn("0001-other.md", p.stderr)
        (self.root / "docs/adr/0001-other.md").unlink()
        self.assertEqual(self.invoke("check-records.py").returncode, 0)

    def test_main_moving_during_gate_is_refused(self):
        task = self.task()
        self.quality('git -C "../main checkout" commit --allow-empty -q -m concurrent', root=task)
        self.commit("gate simulates concurrent landing", root=task)
        p = self.invoke("land.py", root=task)
        self.assertNotEqual(p.returncode, 0)
        self.assertIn("moved during the gate", p.stderr)
        self.assertTrue(task.exists())

    def test_remote_moving_during_gate_is_refused(self):
        task = self.task()
        self.quality('git -C "../remote.git" fetch -q "$PWD" HEAD\n'
                     'git -C "../remote.git" update-ref refs/heads/main FETCH_HEAD', root=task)
        self.commit("gate simulates remote publication", root=task)
        before = self.run_git("rev-parse", "HEAD")
        p = self.invoke("land.py", root=task)
        self.assertNotEqual(p.returncode, 0)
        self.assertIn("moved during the gate", p.stderr)
        self.assertEqual(self.run_git("rev-parse", "HEAD"), before)

    def test_a_branch_that_is_only_behind_main_lands(self):
        task = self.task()
        self.record("diary", "2026-10-25-02.md")
        self.commit("main moves on with a diary the task has not seen")
        self.record("diary", "2026-10-25-03.md", root=task)
        self.commit("task holds 03 while main holds the 02 it has not merged", root=task)
        p = self.invoke("land.py", root=task)
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        self.assertTrue((self.root / "docs/diary/2026-10-25-02.md").exists())

    def test_keep_retains_task_after_successful_landing(self):
        task = self.task()
        self.record("adr", "0002-task.md", root=task)
        self.commit("task", root=task)
        wanted = self.run_git("rev-parse", "HEAD", root=task)
        p = self.invoke("land.py", "--keep", root=task)
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        self.assertEqual(self.run_git("rev-parse", "HEAD"), wanted)
        self.assertTrue(task.exists())
        self.assertEqual(self.run_git("rev-parse", "task"), wanted)

    def test_dirty_main_is_refused_and_other_lock_is_not_removed(self):
        task = self.task()
        (self.root / "uncommitted").write_text("x")
        p = self.invoke("land.py", root=task)
        self.assertNotEqual(p.returncode, 0)
        self.assertIn("not clean", p.stderr)
        (self.root / "uncommitted").unlink()
        lock = self.root / ".git" / "ask-land.lock"
        lock.mkdir()
        p = self.invoke("land.py", root=task)
        self.assertNotEqual(p.returncode, 0)
        self.assertTrue(lock.exists())


if __name__ == "__main__":
    unittest.main()
