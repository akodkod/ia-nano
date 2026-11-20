"""Exercise install/uninstall using a disposable app and installation root."""
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[2]


class InstallationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="ia-nano install test ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.project = self.root / "checkout"
        self.destination = self.root / "installed home"
        shutil.copytree(PROJECT / "script", self.project / "script")
        shutil.copytree(PROJECT / "bin", self.project / "bin")
        self.source = self.project / "dist/iA Nano.app"
        (self.source / "Contents/MacOS").mkdir(parents=True)
        with (self.source / "Contents/Info.plist").open("wb") as output:
            plistlib.dump({"CFBundleIdentifier": "app.ianano.editor"}, output)
        shutil.copy("/bin/sleep", self.source / "Contents/MacOS/ia-nano")
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-",
                        str(self.source / "Contents/MacOS/ia-nano")],
                       check=True, capture_output=True)
        (self.source / "version").write_text("one")
        self.app = self.destination / "Applications/iA Nano.app"
        self.launcher = self.destination / ".local/bin/ia-nano"
        self.env = dict(os.environ, IA_NANO_INSTALL_ROOT=str(self.destination))

    def run_script(self, name, success=True, env=None):
        result = subprocess.run([str(self.project / "script" / name)], cwd="/",
                                env=env or self.env, capture_output=True, text=True)
        if success:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
        return result

    def test_repeat_install_update_and_uninstall(self):
        self.run_script("install.sh")
        self.run_script("install.sh")
        self.assertEqual(self.launcher.read_bytes(), (PROJECT / "bin/ia-nano").read_bytes())
        self.assertTrue(os.access(self.launcher, os.X_OK))
        (self.app / "obsolete").write_text("remove on update")
        (self.source / "version").write_text("two")
        self.run_script("install.sh")
        self.assertFalse((self.app / "obsolete").exists())
        self.assertEqual((self.app / "version").read_text(), "two")
        document = self.destination / "notes.txt"
        document.write_text("keep")
        self.run_script("uninstall.sh")
        self.run_script("uninstall.sh")
        self.assertFalse(self.app.exists())
        self.assertFalse(self.launcher.exists())
        self.assertEqual(document.read_text(), "keep")

    def test_missing_build_does_not_change_installation(self):
        self.run_script("install.sh")
        shutil.rmtree(self.source)
        self.run_script("install.sh", success=False)
        self.assertEqual((self.app / "version").read_text(), "one")

    def test_unrelated_launcher_is_not_overwritten_or_removed(self):
        self.run_script("install.sh")
        self.launcher.write_text("unrelated tool")
        self.run_script("install.sh", success=False)
        self.run_script("uninstall.sh", success=False)
        self.assertEqual(self.launcher.read_text(), "unrelated tool")
        self.assertTrue(self.app.exists())

    def test_unrelated_app_is_not_overwritten_or_removed(self):
        self.app.mkdir(parents=True)
        (self.app / "keep").write_text("unrelated")
        self.run_script("install.sh", success=False)
        self.run_script("uninstall.sh", success=False)
        self.assertTrue((self.app / "keep").exists())

    def test_existing_launcher_symlink_does_not_modify_checkout(self):
        self.launcher.parent.mkdir(parents=True)
        original = self.project / "bin/ia-nano"
        expected = original.read_bytes()
        self.launcher.symlink_to(original)
        self.run_script("install.sh")
        self.assertFalse(self.launcher.is_symlink())
        self.assertEqual(original.read_bytes(), expected)
        self.run_script("uninstall.sh")
        self.assertEqual(original.read_bytes(), expected)

    def test_running_installed_app_is_not_replaced_or_removed(self):
        self.run_script("install.sh")
        process = subprocess.Popen([str(self.app / "Contents/MacOS/ia-nano"), "30"])
        try:
            self.run_script("install.sh", success=False)
            self.run_script("uninstall.sh", success=False)
            self.assertIsNone(process.poll())
            self.assertTrue(self.app.exists())
        finally:
            process.terminate()
            process.wait()

    def test_resident_idle_control_and_busy_refusal(self):
        self.run_script("install.sh")
        executable = self.app / "Contents/MacOS/ia-nano"
        (self.app / "Contents/MacOS/ia-nano-gui").write_text("resident marker")
        (self.app / "Contents/MacOS/ia-nano-gui").chmod(0o755)
        executable.unlink()
        executable.write_text('#!/bin/sh\n[ "$1" = --quit-if-idle ] || exit 9\nexit 2\n')
        executable.chmod(0o755)
        self.run_script("install.sh", success=False)
        self.run_script("uninstall.sh", success=False)
        self.assertTrue(self.app.exists())
        executable.write_text('#!/bin/sh\n[ "$1" = --quit-if-idle ] || exit 9\nexit 0\n')
        self.run_script("uninstall.sh")
        self.assertFalse(self.app.exists())

    def test_failed_launcher_install_restores_previous_app(self):
        self.run_script("install.sh")
        (self.source / "version").write_text("two")
        fake_bin = self.root / "fake-bin"
        fake_bin.mkdir()
        fake_mv = fake_bin / "mv"
        fake_mv.write_text('#!/bin/bash\ncase "${!#}" in */.local/bin/ia-nano) exit 1 ;; esac\nexec /bin/mv "$@"\n')
        fake_mv.chmod(0o755)
        env = dict(self.env, PATH=str(fake_bin) + os.pathsep + os.environ["PATH"])
        self.run_script("install.sh", success=False, env=env)
        self.assertEqual((self.app / "version").read_text(), "one")
        self.assertEqual(self.launcher.read_bytes(), (PROJECT / "bin/ia-nano").read_bytes())


if __name__ == "__main__":
    unittest.main()
