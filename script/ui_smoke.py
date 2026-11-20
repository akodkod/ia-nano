# Run after script/package.sh; follow each printed instruction in the editor.
import os, pathlib, subprocess, tempfile, time
root = pathlib.Path(__file__).resolve().parent.parent
launcher = root / 'bin/ia-nano'
env = dict(os.environ, IA_NANO_METRICS='1')
with tempfile.TemporaryDirectory(prefix='ia-nano-check-') as temp:
    file = pathlib.Path(temp) / 'file-workflow.md'
    file.write_bytes(b'original\r\n')
    proc = subprocess.Popen([str(launcher), str(file)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    print('FILE: replace text with "Saved from iA Nano 👋" then Ctrl+W', flush=True)
    out, err = proc.communicate(timeout=600)
    assert proc.returncode == 0 and out == b'', (proc.returncode, out, err)
    assert file.read_bytes() == 'Saved from iA Nano 👋'.encode(), file.read_bytes()
    print('PASS file save, Ctrl+W, blocking completion:', err.decode().strip(), flush=True)
    proc = subprocess.Popen([str(launcher), '-'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    proc.stdin.write('Pipe input 👋\n'.encode()); proc.stdin.close(); proc.stdin = None
    print('PIPE: leave input unchanged, then Cmd+W', flush=True)
    out, err = proc.communicate(timeout=600)
    assert proc.returncode == 0 and out == 'Pipe input 👋\n'.encode(), (proc.returncode, out, err)
    print('PASS pipe round trip and Cmd+W:', err.decode().strip(), flush=True)
    proc = subprocess.Popen([str(launcher), '-'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    proc.stdin.write(b'Cancel this buffer'); proc.stdin.close(); proc.stdin = None
    print('CANCEL: Cmd+Escape', flush=True)
    out, err = proc.communicate(timeout=600)
    assert proc.returncode == 1 and out == b'', (proc.returncode, out, err)
    print('PASS cancellation emits nothing', flush=True)
    first = pathlib.Path(temp) / 'first-caller.md'; first.write_text('First caller')
    second = pathlib.Path(temp) / 'second-caller.md'; second.write_text('Second caller')
    a = subprocess.Popen([str(launcher), str(first)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    time.sleep(1)
    b = subprocess.Popen([str(launcher), str(second)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    print('CONCURRENT: close first-caller.md first with Cmd+W', flush=True)
    a.communicate(timeout=600)
    assert a.returncode == 0 and b.poll() is None
    print('PASS second caller still blocked. Now close second-caller.md', flush=True)
    b.communicate(timeout=600)
    assert b.returncode == 0
    print('PASS independent concurrent sessions; ALL GUI WORKFLOW CHECKS PASSED', flush=True)
