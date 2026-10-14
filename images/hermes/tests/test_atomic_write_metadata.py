"""Real UID/GID regressions for the shell backend, without shared vault mounts.

Run as root in an isolated image. Every writer command drops to UID/GID 1001
with supplementary GID 0; the calendar reader drops to UID/GID 60 with GID 0.
"""
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, '/opt/hermes')
from tools.file_operations import ShellFileOperations


def identity(uid, gid, groups, mask=0o007):
    def drop():
        os.setgroups(groups)
        os.setgid(gid)
        os.setuid(uid)
        os.umask(mask)
    return drop


class WriterShell:
    def __init__(self, directory, mask=0o007, command_dir=None):
        self.cwd = str(directory)
        self.mask = mask
        self.command_dir = command_dir

    def execute(self, command, cwd=None, stdin_data=None, timeout=None):
        env = os.environ.copy()
        if self.command_dir:
            env['PATH'] = str(self.command_dir) + ':' + env['PATH']
        result = subprocess.run(
            ['/bin/sh', '-c', command], cwd=cwd or self.cwd, input=stdin_data,
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            env=env, timeout=timeout or 30,
            preexec_fn=identity(1001, 1001, [0], self.mask))
        return {'output': result.stdout, 'returncode': result.returncode}


class AtomicMetadataTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='hermes-metadata-')
        self.root = Path(self.tmp.name)
        old_safe_root = os.environ.get('HERMES_WRITE_SAFE_ROOT')
        os.environ['HERMES_WRITE_SAFE_ROOT'] = str(self.root)
        if old_safe_root is None:
            self.addCleanup(os.environ.pop, 'HERMES_WRITE_SAFE_ROOT', None)
        else:
            self.addCleanup(os.environ.__setitem__, 'HERMES_WRITE_SAFE_ROOT', old_safe_root)
        os.chown(self.root, 0, 0)
        os.chmod(self.root, 0o2770)
        # A quote and spaces also exercise failed-write trap escaping.
        self.directory = self.root / "calendar's notes"
        self.directory.mkdir()
        os.chown(self.directory, 0, 0)
        # Existing-group preservation must work without setgid hiding the bug.
        os.chmod(self.directory, 0o770)

    def tearDown(self):
        self.tmp.cleanup()

    def original(self, mode=0o660, gid=0):
        path = self.directory / 'diary.md'
        path.write_text('Original diary\n', encoding='utf-8')
        os.chown(path, 0, gid)
        os.chmod(path, mode)
        return path

    def operations(self, mask=0o007, command_dir=None):
        return ShellFileOperations(WriterShell(self.directory, mask, command_dir))

    def mutate(self, kind, ops, path):
        if kind == 'write':
            return ops.write_file(str(path), 'Original diary\nCook note\n')
        if kind == 'replace':
            return ops.patch_replace(str(path), 'Original diary', 'Original diary\nCook note')
        return ops.patch_v4a(
            '*** Begin Patch\n*** Update File: ' + str(path) +
            '\n@@\n Original diary\n+Cook note\n*** End Patch\n')

    def calendar_read(self, path):
        return subprocess.run(
            [sys.executable, '-c', 'from pathlib import Path; print(Path(__import__("sys").argv[1]).read_text())', str(path)],
            text=True, capture_output=True, preexec_fn=identity(60, 60, [0]))

    def snapshot(self, path):
        info = path.stat()
        return (info.st_ino, info.st_uid, info.st_gid, stat.S_IMODE(info.st_mode), path.read_bytes())

    def failure_command(self, name):
        command_dir = self.root / 'commands'
        command_dir.mkdir(exist_ok=True)
        script = command_dir / name
        script.write_text('#!/bin/sh\necho "injected metadata failure" >&2\nexit 1\n')
        script.chmod(0o755)
        return command_dir

    def test_all_write_tools_preserve_root_group_and_calendar_access(self):
        for kind in ('write', 'replace', 'v4a'):
            with self.subTest(kind=kind):
                path = self.original()
                result = self.mutate(kind, self.operations(), path)
                self.assertFalse(result.error, result.error)
                self.assertEqual((path.stat().st_uid, path.stat().st_gid), (1001, 0))
                self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o660)
                self.assertIn('Cook note', path.read_text())
                reader = self.calendar_read(path)
                self.assertEqual(reader.returncode, 0, reader.stderr)
                self.assertIn('Cook note', reader.stdout)

    def test_metadata_failures_keep_original_and_clean_temp_for_all_tools(self):
        for command in ('stat', 'chgrp', 'chmod'):
            command_dir = self.failure_command(command)
            for kind in ('write', 'replace', 'v4a'):
                with self.subTest(command=command, kind=kind):
                    path = self.original()
                    before = self.snapshot(path)
                    result = self.mutate(kind, self.operations(command_dir=command_dir), path)
                    self.assertTrue(result.error)
                    self.assertIn('atomic write', result.error)
                    self.assertEqual(self.snapshot(path), before)
                    self.assertEqual(sorted(p.name for p in self.directory.iterdir()), ['diary.md'])
            (command_dir / command).unlink()

    def test_real_disallowed_group_change_keeps_original(self):
        path = self.original(mode=0o644, gid=12345)
        before = self.snapshot(path)
        result = self.operations().write_file(str(path), 'Changed\n')
        self.assertTrue(result.error)
        self.assertIn('preserve target group', result.error)
        self.assertEqual(self.snapshot(path), before)
        self.assertEqual(sorted(p.name for p in self.directory.iterdir()), ['diary.md'])

    def test_new_diaries_inherit_setgid_group_and_calendar_can_read(self):
        os.chmod(self.directory, 0o2770)
        for mask, expected_mode in ((0o007, 0o660), (0o022, 0o644)):
            with self.subTest(mask=mask):
                path = self.directory / 'new.md'
                result = self.operations(mask=mask).write_file(str(path), 'New diary\n')
                self.assertFalse(result.error, result.error)
                self.assertEqual((path.stat().st_uid, path.stat().st_gid), (1001, 0))
                self.assertEqual(stat.S_IMODE(path.stat().st_mode), expected_mode)
                self.assertEqual(self.calendar_read(path).returncode, 0)
                path.unlink()
        # Private directories retain the writer's group and umask; no global chgrp.
        private = self.root / 'private'
        private.mkdir()
        os.chown(private, 1001, 1001)
        os.chmod(private, 0o700)
        path = private / 'private.md'
        ops = ShellFileOperations(WriterShell(private, mask=0o077))
        self.assertFalse(ops.write_file(str(path), 'Private\n').error)
        self.assertEqual((path.stat().st_gid, stat.S_IMODE(path.stat().st_mode)), (1001, 0o600))

    def test_new_file_chmod_failure_leaves_no_target_or_temp(self):
        path = self.directory / 'new.md'
        result = self.operations(command_dir=self.failure_command('chmod')).write_file(str(path), 'New\n')
        self.assertTrue(result.error)
        self.assertEqual(list(self.directory.iterdir()), [])

    def test_v4a_new_diary_inherits_directory_group(self):
        os.chmod(self.directory, 0o2770)
        path = self.directory / 'new.md'
        result = self.operations().patch_v4a(
            '*** Begin Patch\n*** Add File: ' + str(path) +
            '\n+New diary\n*** End Patch\n')
        self.assertFalse(result.error, result.error)
        self.assertEqual((path.stat().st_uid, path.stat().st_gid), (1001, 0))
        self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o660)
        self.assertEqual(self.calendar_read(path).returncode, 0)
        self.assertEqual(stat.S_IMODE(self.directory.stat().st_mode), 0o2770)

    def test_symlink_target_preserves_group_mode_and_link(self):
        target = self.original(mode=0o2660)
        link = self.directory / 'link.md'
        link.symlink_to(target)
        result = self.operations().write_file(str(link), 'Linked diary\n')
        self.assertFalse(result.error, result.error)
        self.assertTrue(link.is_symlink())
        self.assertEqual((target.stat().st_gid, stat.S_IMODE(target.stat().st_mode)), (0, 0o2660))
        self.assertEqual(self.calendar_read(link).returncode, 0)


if __name__ == '__main__':
    if os.getuid() != 0:
        raise SystemExit('Run in an isolated container as root; tests drop writer and reader privileges.')
    unittest.main(verbosity=2)
