#!/usr/bin/env python3
"""Exercise cancellation/locking with disposable processes, never a real app."""
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest


class VerificationSessionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='browser-runner-test-')
        self.root = Path(self.temporary.name)
        (self.root / 'scripts').mkdir()
        self.runner = self.root / 'scripts/verification-session.py'
        shutil.copyfile(Path(__file__).with_name('verification-session.py'), self.runner)
        self.children = []

    def tearDown(self):
        for child in self.children:
            if child.poll() is None:
                child.terminate()
            child.wait(timeout=5)
        self.temporary.cleanup()

    def launch(self, *command, **kwargs):
        child = subprocess.Popen([sys.executable, str(self.runner), *command],
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)
        self.children.append(child)
        return child

    def testCancellationKillsOwnedDescendantsAndReleasesLock(self):
        sentinel = subprocess.Popen(['/bin/sleep', '30'])
        self.children.append(sentinel)
        pid_file = self.root / 'descendant.pid'
        script = self.root / 'fixture.py'
        script.write_text('import subprocess, time\nfrom pathlib import Path\n'
                          "p = subprocess.Popen(['/bin/sleep', '30'])\n"
                          f'Path({str(pid_file)!r}).write_text(str(p.pid))\n'
                          'time.sleep(30)\n')
        run = self.launch(sys.executable, str(script))
        deadline = time.monotonic() + 5
        while not pid_file.exists() and time.monotonic() < deadline:
            time.sleep(0.02)
        self.assertTrue(pid_file.exists())
        other = self.launch('/usr/bin/true')
        _, error = other.communicate(timeout=5)
        self.assertNotEqual(other.returncode, 0)
        self.assertIn(b'Another verification run', error)
        started = time.monotonic()
        run.send_signal(signal.SIGINT)
        run.communicate(timeout=5)
        self.assertEqual(run.returncode, 130)
        self.assertLess(time.monotonic() - started, 5)
        state = subprocess.run(['/bin/ps', '-p', pid_file.read_text(), '-o', 'stat='],
                               capture_output=True, text=True).stdout.strip()
        self.assertTrue(not state or state.startswith('Z'), state)
        self.assertIsNone(sentinel.poll())
        next_run = self.launch('/usr/bin/true')
        next_run.communicate(timeout=5)
        self.assertEqual(next_run.returncode, 0)

    def testInvalidConcurrencyFailsBeforeCommand(self):
        marker = self.root / 'should-not-exist'
        for jobs in ['0', '9', 'two']:
            run = self.launch('/usr/bin/touch', str(marker),
                              env=dict(os.environ, BROWSER_BUILD_JOBS=jobs))
            run.communicate(timeout=5)
            self.assertNotEqual(run.returncode, 0)
            self.assertFalse(marker.exists())

    def testBackgroundPriorityIsLoweredButInteractiveTimingPriorityIsPreserved(self):
        fixture = self.root / 'run-performance-tests.sh'
        fixture.write_text('#!/usr/bin/python3\nimport os\nprint(os.getpriority(os.PRIO_PROCESS, 0))\n')
        fixture.chmod(0o755)
        original = os.getpriority(os.PRIO_PROCESS, 0)
        for argument, expected in [('--interactive', original), ('--build-only', min(20, original + 10))]:
            run = self.launch(str(fixture), argument)
            output, error = run.communicate(timeout=5)
            self.assertEqual(run.returncode, 0, error)
            self.assertEqual(int(output), expected)

    def testFailedCommandPropagatesStatus(self):
        run = self.launch('/bin/sh', '-c', 'exit 17')
        run.communicate(timeout=5)
        self.assertEqual(run.returncode, 17)


if __name__ == '__main__':
    unittest.main()
