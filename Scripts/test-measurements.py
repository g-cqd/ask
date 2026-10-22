#!/usr/bin/env python3
"""Deterministic guards for external measurements; no ask process or real timing assertion."""
import contextlib
import importlib.util
import io
import os
from pathlib import Path
import struct
import sys
import termios
import unittest
from unittest.mock import patch


def load(name):
    path = Path(__file__).with_name(name + '.py')
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), path)
    module = importlib.util.module_from_spec(spec)
    with patch.object(sys, 'argv', [str(path)]):
        spec.loader.exec_module(module)
    return module


budgets = load('measure-budgets')
action = load('measure-action')


class ReachedExec(Exception):
    pass


class MeasurementTests(unittest.TestCase):
    def test_child_sets_geometry_before_exec(self):
        events = []
        def execute(*args):
            events.append(('exec', args))
            raise ReachedExec()
        def ioctl(*args):
            events.append(('size', args))
        with patch('pty.fork', return_value=(0, 99)), patch('fcntl.ioctl', side_effect=ioctl), \
             patch('os.execv', side_effect=execute), patch.dict(os.environ):
            with self.assertRaises(ReachedExec):
                budgets.spawn()
        self.assertEqual([e[0] for e in events], ['size', 'exec'])
        self.assertEqual(events[0][1], (0, termios.TIOCSWINSZ, struct.pack('HHHH', 40, 120, 0, 0)))

    def test_parent_does_not_resize_after_fork(self):
        with patch('pty.fork', return_value=(1234, 99)), patch('fcntl.ioctl') as ioctl:
            self.assertEqual(budgets.spawn(), (1234, 99))
        ioctl.assert_not_called()

    def measured(self, chunks):
        clock = [1.0]
        def spawn():
            clock[0] = 1.01
            return 1234, 99
        pieces = iter(chunks + [(1.04, b'x' + budgets.FRAME_END)])
        def read(*args):
            try:
                clock[0], data = next(pieces)
                return data
            except StopIteration:
                raise OSError('the fake PTY closed')
        with contextlib.ExitStack() as stack:
            stack.enter_context(patch.object(budgets, 'spawn', side_effect=spawn))
            for name in ('time', 'monotonic'):
                stack.enter_context(patch.object(budgets.time, name, side_effect=lambda: clock[0]))
            stack.enter_context(patch.object(budgets.time, 'sleep'))
            stack.enter_context(patch.object(budgets, 'rss_kb', return_value=10000))
            stack.enter_context(patch.object(budgets, 'drain'))
            stack.enter_context(patch('select.select', return_value=([99], [], [])))
            stack.enter_context(patch('os.read', side_effect=read))
            stack.enter_context(patch('os.write'))
            stack.enter_context(patch('os.close'))
            stack.enter_context(patch('os.waitpid', return_value=(1234, 0)))
            return budgets.one_run()

    def test_cold_time_includes_fork(self):
        row = self.measured([(1.03, b'ask> ' + budgets.FRAME_END)])
        self.assertIsNotNone(row)
        self.assertAlmostEqual(row[0], 30.0)

    def test_prompt_needs_no_trailing_blank(self):
        # A diff can leave the already-blank cell after '>' untouched, then position the cursor there.
        row = self.measured([(1.03, b'ask>\x1b[40;6H' + budgets.FRAME_END)])
        self.assertIsNotNone(row)
        self.assertAlmostEqual(row[0], 30.0)

    def test_cold_time_waits_for_prompt_frame_to_close(self):
        row = self.measured([(1.02, b'ask> '), (1.03, budgets.FRAME_END)])
        self.assertIsNotNone(row)
        self.assertAlmostEqual(row[0], 30.0)

    def test_an_incomplete_run_cannot_be_a_green_budget_result(self):
        class FakeAction:
            @staticmethod
            def one_run(tool):
                return 2.0, 3.0
        limits = dict(coldStartMilliseconds=25, idleMemoryMebibytes=24,
                      inputDelayMilliseconds=2, actionToActionMilliseconds=5)
        with patch.object(budgets, 'RUNS', 2), patch.object(budgets, 'action_probe', return_value=FakeAction()), \
             patch.object(budgets, 'one_run', side_effect=[(10.0, 9000, 0.5), None]), \
             patch.object(budgets, 'load_budgets', return_value=limits), \
             contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(budgets.main(), 1)

    def test_p95_uses_nearest_rank_in_a_small_sample(self):
        # With 12 samples p95 is the last, not the second-to-last (91.7th percentile).
        self.assertIn('p95 12.00', action.summary(list(range(1, 13))))


if __name__ == '__main__':
    unittest.main()
