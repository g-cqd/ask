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
import tempfile
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
startup = load('measure-startup')


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
        row = self.measured([(1.03, '────'.encode() + budgets.FRAME_END)])
        self.assertIsNotNone(row)
        self.assertAlmostEqual(row[0], 30.0)

    def test_prompt_needs_no_trailing_blank(self):
        # A separator can be followed directly by cursor positioning, without a trailing blank.
        row = self.measured([(1.03, '────'.encode() + b'\x1b[40;6H' + budgets.FRAME_END)])
        self.assertIsNotNone(row)
        self.assertAlmostEqual(row[0], 30.0)

    def test_cold_time_waits_for_prompt_frame_to_close(self):
        row = self.measured([(1.02, '────'.encode()), (1.03, budgets.FRAME_END)])
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

    def test_startup_summary_keeps_nearest_rank_and_empty_cohorts(self):
        self.assertEqual(startup.stats(list(range(1, 13)))['p95'], 12)
        self.assertIsNone(startup.stats([]))

    def test_only_complete_untraced_unchanged_cohorts_can_certify_a_budget(self):
        good = dict(error=None, phases=[])
        self.assertTrue(startup.shipping_cohort([good]))
        for rows, changed, traced in [([], False, False), ([good], True, False), ([good], False, True),
                                      ([dict(error='missing frame', phases=[])], False, False),
                                      ([dict(error=None, phases=[dict(phase='arguments')])], False, False)]:
            with self.subTest(rows=rows, changed=changed, traced=traced):
                self.assertFalse(startup.shipping_cohort(rows, changed, traced))

    def test_core_class_boundary_and_a_host_without_efficiency_cores(self):
        self.assertEqual(startup.core_class(3, 4), 'efficiency')
        self.assertEqual(startup.core_class(4, 4), 'performance')
        self.assertEqual(startup.core_class(0, 0), 'performance', 'no efficiency level: nothing is efficiency')

    def test_by_core_groups_by_first_marker_and_reports_what_it_left_out(self):
        def row(core, cold, error=None, phases=True):
            marker = [dict(phase='arguments', cpu_number=core)] if phases else []
            return dict(cold_ms=cold, error=error, phases=marker)
        rows = [row(1, 24.0), row(2, 26.0), row(5, 12.0), row(8, 14.0), row(9, 13.0),
                row(6, 99.0, error='missing frame'), row(0, 50.0, phases=False)]
        report = startup.by_core(rows, 4)
        self.assertEqual(report['left_out'], 2)
        self.assertEqual({k: v['count'] for k, v in report['groups'].items()}, dict(efficiency=2, performance=3))
        self.assertEqual(report['groups']['efficiency']['p50'], 25.0)
        self.assertEqual(report['groups']['performance']['p50'], 13.0)

    def test_phase_markers_decode_sampled_cpu_and_requested_priority(self):
        raw = b'\x1b[0mTRACE arguments 123 456 4 21 25 0\r\n'
        self.assertEqual(startup.phases(raw), [dict(
            phase='arguments', wall_ns=123, cpu_us=456, cpu_number=4,
            requested_qos=21, task_priority=25, cpu_query_status=0)])

    def fake_startup(self, frame):
        # A real isolated PTY, but no ask binary, sleep or latency assertion. The fake blocks on input until reaped.
        program = 'import os; os.write(1, ' + repr(frame) + '); os.read(0, 1)'
        with tempfile.TemporaryDirectory(prefix='ask-measurement-test-') as directory:
            return startup.sample(sys.executable, directory, startup.isolated_environment(Path(directory)),
                                  arguments=('-c', program))

    def test_a_real_prompt_frame_without_a_blank_is_measurable(self):
        row = self.fake_startup(b'\x1b[?2026h' + '────'.encode() + b'\x1b[40;6H\x1b[?2026l')
        self.assertIsNone(row['error'])
        self.assertIsNotNone(row['cold_ms'])
        self.assertEqual(row['exit_code'], -9, 'the probe deliberately stops and reaps only its own child')

    def test_a_failed_phase_query_is_retained_not_certified(self):
        row = self.fake_startup(b'TRACE arguments 123 456 4 21 25 5\n' + '────'.encode() + b'\x1b[?2026l')
        self.assertEqual(row['error'], 'phase probe reported a query error')
        self.assertIn('TRACE arguments', row['output_tail'])


if __name__ == '__main__':
    unittest.main()
