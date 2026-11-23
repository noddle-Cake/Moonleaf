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
              version=50, extra='', signer_output=None):
        outputs = [signer_output if signer_output is not None else
                   f'Signer #1 certificate SHA-256 digest: {certificate}',
                   f"package: name='{package}' versionCode='{version}' versionName='1.0.0'\n{extra}"]
        with patch('subprocess.check_output', side_effect=outputs):
            verify('app.apk', '50')

    def test_valid_release(self):
        self.check()

    def test_sdk_37_signer_labels(self):
        for label in ['V1 Signer:', 'V2 Signer:', 'V3.0 Signer:', 'V3.1 Signer:']:
            with self.subTest(label=label):
                self.check(signer_output=f'{label} certificate SHA-256 digest: ' + 'ab' * 32)

    def test_sdk_range_signer_label(self):
        self.check(signer_output='Signer (minSdkVersion=24, maxSdkVersion=32) '
                   'certificate SHA-256 digest: ' + 'ab' * 32)

    def test_same_certificate_in_multiple_signature_schemes(self):
        self.check(signer_output='\n'.join(
            f'{label} certificate SHA-256 digest: ' + 'ab' * 32
            for label in ['V2 Signer:', 'V3.0 Signer:']))

    def test_different_certificate_in_another_scheme_is_rejected(self):
        output = ('V2 Signer: certificate SHA-256 digest: ' + 'ab' * 32 + '\n'
                  'V3.0 Signer: certificate SHA-256 digest: ' + 'cd' * 32)
        with self.assertRaisesRegex(ValueError, 'permanent certificate'):
            self.check(signer_output=output)

    def test_source_stamp_does_not_supply_the_app_signing_identity(self):
        with self.assertRaisesRegex(ValueError, 'permanent certificate'):
            self.check(signer_output='Source Stamp Signer certificate SHA-256 digest: ' + 'ab' * 32)

    def test_unknown_certificate_output_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'permanent certificate'):
            self.check(signer_output='No certificates found')

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
