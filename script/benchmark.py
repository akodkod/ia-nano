"""Measure real release client window-ready timings; uses macOS Accessibility access."""
import os
import pathlib
import re
import statistics
import subprocess
import time

root = pathlib.Path(__file__).resolve().parents[1]
client = root / 'dist/iA Nano.app/Contents/MacOS/ia-nano'
gui = client.with_name('ia-nano-gui')
subprocess.run([str(client), '--quit-if-idle'], check=True)
measurements = []
for index in range(31):
    process = subprocess.Popen([str(client)], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               env=dict(os.environ, IA_NANO_METRICS='1'))
    line = process.stderr.readline().decode()
    match = re.search(r'(cold|warm) window-ready in ([\d.]+) ms', line)
    if not match:
        raise RuntimeError(line)
    measurements.append(float(match[2]))
    time.sleep(.3)  # Let macOS finish foreground activation before sending a shortcut.
    pid = subprocess.check_output(['pgrep', '-f', '^' + re.escape(str(gui)) + '( |$)'], text=True).strip()
    subprocess.run(['osascript', '-e', f'tell application "System Events" to tell (first process whose unix id is {pid})\nset frontmost to true\nkeystroke "w" using command down\nend tell'], check=True, capture_output=True)
    output, error = process.communicate(timeout=10)
    assert process.returncode == 0 and output == b'', (output, error)
    print(index, line.strip(), flush=True)
    time.sleep(.1)
print(f'Cold: {measurements[0]:.1f} ms; warm n=30 median={statistics.median(measurements[1:]):.1f} ms p95={sorted(measurements[1:])[28]:.1f} ms')
subprocess.run([str(client), '--quit-if-idle'], check=True)
