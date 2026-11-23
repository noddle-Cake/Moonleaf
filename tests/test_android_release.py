"""Publishing must reject APKs that Android cannot accept as our next update."""
import os
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from tools.verify_android_release import verify


class ReleaseVerificationTests(unittest.TestCase):
    def setUp(self):
        self.temp = TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        folder = Path(self.temp.name) / 'build-tools' / '36.0.0'
        folder.mkdir(parents=True)
        (folder / 'apksigner').touch()
        self.env = patch.dict(os.environ, {
            'ANDROID_HOME': self.temp.name,
            'EXPECTED_CERT_SHA256': 'ab' * 32,
        })
        self.env.start()
        self.addCleanup(self.env.stop)

    def check(self, certificate='ab' * 32, package='com.noddlecake.novel_to_epub',
              version=50, extra=''):
        outputs = [f'Signer #1 certificate SHA-256 digest: {certificate}',
                   f"package: name='{package}' versionCode='{version}' versionName='1.0.0'\n{extra}"]
        with patch('subprocess.check_output', side_effect=outputs):
            verify('app.apk', '50')

    def test_valid_release(self):
        self.check()

    def test_missing_or_invalid_certificate_pin(self):
        for value in ['', 'not-a-certificate']:
            with self.subTest(value=value), patch.dict(os.environ, {'EXPECTED_CERT_SHA256': value}):
                with self.assertRaisesRegex(ValueError, 'pin the release certificate'):
                    self.check()

    def test_wrong_key(self):
        with self.assertRaisesRegex(ValueError, 'permanent certificate'):
            self.check(certificate='cd' * 32)

    def test_changed_application_id(self):
        with self.assertRaisesRegex(ValueError, 'application ID or version code'):
            self.check(package='com.example.changed')

    def test_stale_version(self):
        with self.assertRaisesRegex(ValueError, 'application ID or version code'):
            self.check(version=49)

    def test_debug_build(self):
        with self.assertRaisesRegex(ValueError, 'release build'):
            self.check(extra='application-debuggable')


if __name__ == '__main__':
    unittest.main()
