#!/usr/bin/env python3
"""Test MediaRecorder in an isolated Chrome profile with synthetic audio only."""
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
chrome = os.environ.get("CHROME_EXECUTABLE") or (
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" if sys.platform == "darwin"
    else shutil.which("google-chrome") or shutil.which("chromium")
)
flutter = shutil.which("flutter")
if not chrome or not Path(chrome).is_file() or not flutter:
    raise SystemExit("Chrome and Flutter are required for the browser audio test.")
with tempfile.TemporaryDirectory(prefix="royal-brick-browser-test-") as temporary:
    wrapper = Path(temporary) / "chrome"
    wrapper.write_text("#!/bin/sh\nexec " + shlex.quote(chrome) +
                       ' --autoplay-policy=no-user-gesture-required "$@"\n')
    wrapper.chmod(0o700)
    environment = dict(os.environ, CHROME_EXECUTABLE=str(wrapper))
    result = subprocess.run([sys.executable, str(root / "scripts/with_timeout.py"), "90", flutter,
        "--suppress-analytics", "test", "--no-pub", "--platform", "chrome",
        "test/web/audio_recorder_test.dart", "--reporter", "expanded"], cwd=root, env=environment)
    raise SystemExit(result.returncode)
