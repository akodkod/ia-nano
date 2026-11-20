"""Integration tests against disposable release executables on a logged-in Mac.
Build with script/package.sh. Set IA_NANO_UI_TESTS=1 for keyboard-driven tests.
"""
import base64
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import struct
import subprocess
import tempfile
import time
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'dist/iA Nano.app/Contents/MacOS'


def send(sock, kind, id='', **fields):
    payload = json.dumps(dict(version=1, kind=kind, id=id, **fields)).encode()
    sock.sendall(struct.pack('!I', len(payload)) + payload)


def receive(sock):
    def exact(n):
        data = b''
        while len(data) < n:
            part = sock.recv(n - len(data))
            if not part:
                raise EOFError('host disconnected')
            data += part
        return data
    return json.loads(exact(struct.unpack('!I', exact(4))[0]))


class ResidentTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='ia-resident-')
        self.root = Path(self.temp.name).resolve()
        for name in ['ia-nano', 'ia-nano-gui']:
            shutil.copy2(SOURCE / name, self.root / name)
        self.client = self.root / 'ia-nano'
        self.gui = self.root / 'ia-nano-gui'
        # Foundation canonicalizes existing /private/var paths to /var on macOS.
        canonical = str(self.root).removeprefix('/private')
        digest = hashlib.sha256(canonical.encode()).hexdigest()[:32]
        self.endpoint = Path(f'/tmp/ia-nano-{os.getuid()}-{digest}')
        self.processes = []
        self.sockets = []

    def tearDown(self):
        for sock in self.sockets:
            sock.close()
        # Only processes created in this test's isolated binary location.
        pids = subprocess.run(['pgrep', '-f', '^' + str(self.gui) + '( |$)'], capture_output=True, text=True).stdout.split()
        for pid in pids:
            try: os.kill(int(pid), 15)
            except ProcessLookupError: pass
        for process in self.processes:
            if process.poll() is None: process.terminate()
            process.communicate(timeout=5)
        shutil.rmtree(self.endpoint, ignore_errors=True)
        self.temp.cleanup()

    def launch(self, *arguments, **kwargs):
        process = subprocess.Popen(arguments, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)
        self.processes.append(process)
        return process

    def start(self):
        host = self.launch(str(self.gui), '--background')
        self.connect().close()
        return host

    def connect(self):
        deadline = time.monotonic() + 5
        while True:
            sock = socket.socket(socket.AF_UNIX)
            sock.settimeout(5)
            try:
                sock.connect(str(self.endpoint / 'socket'))
                greeting = receive(sock)
                self.assertEqual(greeting['kind'], 'hello')
                self.sockets.append(sock)
                return sock
            except (FileNotFoundError, ConnectionRefusedError):
                sock.close()
                if time.monotonic() >= deadline: raise
                time.sleep(.01)

    def open(self, data=b'', path=None):
        sock = self.connect()
        id = str(uuid.uuid4())
        send(sock, 'open', id, **({'path': str(path)} if path else {}))
        for offset in range(0, len(data), 48 * 1024):
            send(sock, 'chunk', id, data=base64.b64encode(data[offset:offset + 48 * 1024]).decode())
        send(sock, 'end', id)
        packet = receive(sock)
        self.assertEqual(packet['kind'], 'ready', packet)
        return sock, id

    def quit_idle(self, success=True):
        result = subprocess.run([str(self.client), '--quit-if-idle'], capture_output=True, timeout=6)
        self.assertEqual(result.returncode == 0, success, result.stderr)

    def key(self, host, key, modifiers='command down'):
        time.sleep(.3)
        script = f'tell application "System Events" to tell (first process whose unix id is {host.pid})\nset frontmost to true\nkeystroke "{key}" using {modifiers}\nend tell'
        subprocess.run(['osascript', '-e', script], check=True, capture_output=True, timeout=5)

    def test_startup_race_and_independent_concurrent_sessions(self):
        hosts = [self.launch(str(self.gui), '--background') for _ in range(8)]
        self.connect().close()
        with concurrent.futures.ThreadPoolExecutor() as pool:
            sessions = list(pool.map(lambda i: self.open(f'caller {i} 🦊'.encode()), range(8)))
        self.quit_idle(False)
        for index, (sock, id) in enumerate(sessions):
            send(sock, 'cancel', id)
            result = receive(sock)
            self.assertEqual((result['id'], result['code']), (id, 1))
            if index < len(sessions) - 1: self.quit_idle(False)
        time.sleep(.1)
        self.assertEqual(sum(p.poll() is None for p in hosts), 1)
        self.quit_idle()

    def test_stale_socket_and_no_host_quit(self):
        self.quit_idle()
        sock = socket.socket(socket.AF_UNIX)
        sock.bind(str(self.endpoint / 'socket'))
        sock.close()
        self.start()
        self.quit_idle()

    def test_disconnect_keeps_session_and_refuses_quit(self):
        self.start()
        sock, _ = self.open(b'recover this')
        sock.close()
        time.sleep(.1)
        self.quit_idle(False)

    def test_host_crash_releases_client_without_replay(self):
        host = self.start()
        client = self.launch(str(self.client), env=dict(os.environ, IA_NANO_METRICS='1'))
        self.assertIn(b'window-ready', client.stderr.readline())
        host.kill(); host.wait()
        out, err = client.communicate(timeout=5)
        self.assertEqual(out, b'')
        self.assertEqual(client.returncode, 2)
        self.assertIn(b'not replayed', err)

    def test_protocol_mismatch_is_rejected(self):
        self.start()
        sock = self.connect()
        payload = json.dumps(dict(version=99, kind='open', id='wrong')).encode()
        sock.sendall(struct.pack('!I', len(payload)) + payload)
        with self.assertRaises(EOFError): receive(sock)
        self.quit_idle()

    def test_incompatible_idle_build_replaced_active_build_refused(self):
        host = self.start()
        sock, id = self.open()
        stamp = self.gui.stat().st_mtime + 2
        os.utime(self.gui, (stamp, stamp))
        result = subprocess.run([str(self.client)], capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 2)
        self.assertIn(b'open', result.stderr)
        self.assertIsNone(host.poll())
        send(sock, 'cancel', id); receive(sock)
        client = self.launch(str(self.client), env=dict(os.environ, IA_NANO_METRICS='1'))
        self.assertIn(b'window-ready', client.stderr.readline())
        host.wait(timeout=5)
        self.assertEqual(host.returncode, 0)
        client.terminate(); client.wait()

    @unittest.skipUnless(os.getenv('IA_NANO_UI_TESTS') == '1', 'requires Accessibility keyboard access')
    def test_quit_finishes_file_pipe_and_empty_without_crosstalk(self):
        host = self.start()
        file = self.root / 'document.md'; file.write_bytes(b'file\r\n')
        callers = [self.launch(str(self.client), str(file), env=dict(os.environ, IA_NANO_METRICS='1')),
                   self.launch(str(self.client), '-', stdin=subprocess.PIPE, env=dict(os.environ, IA_NANO_METRICS='1')),
                   self.launch(str(self.client), env=dict(os.environ, IA_NANO_METRICS='1'))]
        callers[1].stdin.write('pipe 🦊\r\n'.encode()); callers[1].stdin.close(); callers[1].stdin = None
        for client in callers: self.assertIn(b'window-ready', client.stderr.readline())
        self.key(host, 'q')
        for client, expected in zip(callers, [b'', 'pipe 🦊\r\n'.encode(), b'']):
            out, err = client.communicate(timeout=5)
            self.assertEqual((client.returncode, out), (0, expected), err)
        self.assertEqual(file.read_bytes(), b'file\r\n')
        host.wait(timeout=5)

    @unittest.skipUnless(os.getenv('IA_NANO_UI_TESTS') == '1', 'requires Accessibility keyboard access')
    def test_failed_stdout_keeps_recoverable_editor(self):
        host = self.start()
        client = self.launch(str(self.client), '-', stdin=subprocess.PIPE, env=dict(os.environ, IA_NANO_METRICS='1'))
        client.stdin.write(b'recover me'); client.stdin.close(); client.stdin = None
        self.assertIn(b'window-ready', client.stderr.readline())
        client.stdout.close(); client.stdout = None
        self.key(host, 'w')
        _, err = client.communicate(timeout=5)
        self.assertEqual(client.returncode, 2)
        self.assertIn(b'Text remains', err)
        self.quit_idle(False)


if __name__ == '__main__':
    unittest.main()
