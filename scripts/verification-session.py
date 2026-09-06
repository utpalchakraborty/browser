#!/usr/bin/env python3
"""Serialize verification and cancel only this run's process groups/test products."""
import fcntl
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def processes():
    output = subprocess.check_output(['/bin/ps', '-axo', 'pid=,comm='], text=True)
    return {int(line.strip().split(None, 1)[0]): line.strip().split(None, 1)[1]
            for line in output.splitlines() if len(line.strip().split(None, 1)) == 2}


def signal_group(pid, sig):
    try:
        os.killpg(pid, sig)
    except ProcessLookupError:
        pass


def main():
    jobs = os.environ.get('BROWSER_BUILD_JOBS', '2')
    if not jobs.isdigit() or not 1 <= int(jobs) <= 8:
        sys.exit('BROWSER_BUILD_JOBS must be an integer from 1 to 8')
    build = ROOT / '.build'
    build.mkdir(exist_ok=True)
    with (build / 'verification.lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            sys.exit('Another verification run owns the fixtures. Stop it before starting another.')
        before = processes()
        env = dict(os.environ, BROWSER_VERIFICATION_SUPERVISED='1', BROWSER_BUILD_JOBS=jobs)
        child = None
        cancelled = 0

        def cancel(sig, _frame):
            nonlocal cancelled
            cancelled = 128 + sig
            if child is not None:
                signal_group(child.pid, signal.SIGTERM)

        signal.signal(signal.SIGINT, cancel)
        signal.signal(signal.SIGTERM, cancel)
        # Background work yields to the desktop. Explicit interactive timing gates
        # retain the caller's priority so baseline comparisons do not change priority.
        interactive_performance = (
            Path(sys.argv[1]).name == 'run-performance-tests.sh'
            and '--interactive' in sys.argv[2:]
        )
        if not interactive_performance:
            os.nice(10)
        try:
            child = subprocess.Popen(sys.argv[1:], env=env, start_new_session=True)
            while child.poll() is None and not cancelled:
                time.sleep(0.1)
            if cancelled:
                signal_group(child.pid, signal.SIGTERM)
                try:
                    child.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    signal_group(child.pid, signal.SIGKILL)
                    child.wait()
            return cancelled or child.returncode
        finally:
            if child is not None:
                signal_group(child.pid, signal.SIGTERM)
                time.sleep(0.2)
                signal_group(child.pid, signal.SIGKILL)
            # testmanagerd may launch outside the shell process group. Restrict cleanup
            # to new processes with exact executable paths in our Testing products.
            prefix = str(build / 'TestingDerivedData' / 'Build' / 'Products') + '/'
            for pid, executable in processes().items():
                if pid not in before and executable.startswith(prefix) and (
                    executable.endswith('/Browser.app/Contents/MacOS/Browser') or
                    '.app/Contents/MacOS/BrowserUITests-Runner' in executable or
                    '.app/Contents/MacOS/BrowserPerformanceTests-Runner' in executable
                ):
                    try:
                        os.kill(pid, signal.SIGTERM)
                    except ProcessLookupError:
                        pass


if __name__ == '__main__':
    sys.exit(main())
