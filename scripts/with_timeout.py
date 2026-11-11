#!/usr/bin/env python3
"""Run a development command with a deadline, including its child processes."""

import argparse
import os
import signal
import subprocess
import sys


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("seconds", type=float)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.seconds <= 0 or not args.command:
        parser.error("provide a positive timeout and a command")

    process = subprocess.Popen(args.command, start_new_session=True)
    try:
        return process.wait(timeout=args.seconds)
    except (subprocess.TimeoutExpired, KeyboardInterrupt) as error:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        if isinstance(error, KeyboardInterrupt):
            return 130
        print(f"Stopped after {args.seconds:g} seconds: time limit exceeded.",
              file=sys.stderr)
        return 124


if __name__ == "__main__":
    sys.exit(main())
