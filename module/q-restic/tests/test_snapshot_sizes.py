"""Legacy snapshots lack summary; unknown must not become a zero-byte backup."""
import contextlib
import io
import threading
import time
import unittest
from unittest.mock import patch

from test_q_restic import q, snapshot, test_app, test_config


def legacy_snapshot(n=1):
    value = snapshot(n)
    del value['summary']
    return value


class SnapshotSizeTests(unittest.TestCase):
    def test_missing_and_invalid_sizes_differ_from_zero(self):
        for summary in ({}, {'total_bytes_processed': None}, {'total_bytes_processed': -1},
                        {'total_bytes_processed': True}):
            self.assertIsNone(q.snap_size({'summary': summary}))
        self.assertIsNone(q.snap_added(legacy_snapshot()))
        self.assertEqual(q.human_size(q.snap_size(legacy_snapshot())), '未知')
        self.assertEqual(q.snap_size({'summary': {'total_bytes_processed': 0}}), 0)
        self.assertEqual(q.human_size(0), '0 B')

    def test_fallback_queries_exact_snapshot_and_validates_response(self):
        cfg = test_config()
        with patch.object(q, 'run_json', return_value={'total_size': 4096}) as run:
            self.assertEqual(q.snapshot_total_size('restic', cfg, 'a'*64), 4096)
            self.assertEqual(run.call_args.args[2], ['stats', '--json', '--mode', 'restore-size', 'a'*64] + q.snapshot_args(cfg))
        for result in ({}, {'total_size': -1}, {'total_size': True}, []):
            with patch.object(q, 'run_json', return_value=result), self.assertRaises(RuntimeError):
                q.snapshot_total_size('restic', cfg, 'a'*64)

    def test_cli_legacy_sizes_and_missing_added_are_not_zero(self):
        cfg = test_config()
        with patch.object(q, 'restic_bin', return_value='restic'), patch.object(q, 'snapshots', return_value=[legacy_snapshot()]), patch.object(q, 'snapshot_stats', return_value={'total_size': 4096}), patch.object(q, 'repo_stats', return_value={'total_size': 2048}), contextlib.redirect_stdout(io.StringIO()) as out:
            self.assertEqual(q.do_status(cfg), 0)
        self.assertIn('4.0 KiB', out.getvalue())
        self.assertIn('未知', out.getvalue())
        self.assertNotIn('0 B', out.getvalue())
        self.assertNotIn('压缩比', out.getvalue())

    def test_cli_failed_stats_reports_unknown_and_nonzero(self):
        with patch.object(q, 'restic_bin'), patch.object(q, 'snapshots', return_value=[legacy_snapshot()]), patch.object(q, 'snapshot_total_size', side_effect=RuntimeError('offline')), patch.object(q, 'snapshot_stats', return_value=None), patch.object(q, 'repo_stats', return_value=None), contextlib.redirect_stdout(io.StringIO()) as out, contextlib.redirect_stderr(io.StringIO()) as err:
            self.assertEqual(q.do_status(test_config()), 1)
        self.assertIn('未知', out.getvalue())
        self.assertIn('offline', err.getvalue())
        self.assertNotIn('0 B', out.getvalue())

    def wait_for(self, app, predicate):
        until = time.monotonic() + 3
        while time.monotonic() < until:
            app.poll_data()
            if predicate():
                return
            time.sleep(.005)
        self.fail('background statistics did not finish')

    def test_background_size_is_lazy_cached_and_zero_is_valid(self):
        app = test_app()
        app.restic = 'restic'
        app.snaps = [legacy_snapshot()]
        app.repo_size_loaded = True
        release = threading.Event()
        def load(*args):
            release.wait(3)
            return 0
        with patch.object(q, 'snapshot_total_size', side_effect=load) as load_size:
            app.start_stats_load()
            load_size.assert_not_called()  # Main menu never scans legacy trees.
            app.screen = 'snapshots'
            start = time.monotonic()
            app.start_stats_load()
            self.assertLess(time.monotonic()-start, .2)
            try:
                self.assertEqual(app.snapshot_items()[0]['size'], '统计中…')
            finally:
                release.set()
            self.wait_for(app, lambda: bool(app.snapshot_sizes))
            self.assertEqual(app.snapshot_items()[0]['size'], '0 B')
            app.start_stats_load()
            self.assertEqual(load_size.call_count, 1)

    def test_failed_sizes_stay_unavailable_until_retry_and_stale_results_are_ignored(self):
        app = test_app()
        app.restic = 'restic'
        app.screen = 'snapshots'
        app.snaps = [legacy_snapshot()]
        app.repo_size_loaded = True
        with patch.object(q, 'snapshot_total_size', side_effect=RuntimeError('offline')) as loader:
            app.start_stats_load()
            self.wait_for(app, lambda: bool(app.snapshot_size_errors))
            app.poll_data()
            self.assertEqual(loader.call_count, 1)
        self.assertEqual(app.snapshot_items()[0]['size'], '不可用')
        self.assertIn('offline', ''.join(app.footer(120)))
        stale = object()
        app._requests['snapshot_size'] = stale
        app.invalidate_stats()
        app._results.put(('snapshot_size', stale, 123, ''))
        app.screen = 'menu'
        app.poll_data()
        self.assertEqual(app.snapshot_sizes, {})
        self.assertEqual(app.snapshot_size_errors, {})
