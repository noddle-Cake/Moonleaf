"""Failed or concurrent deployments must not publish partial APKs or roll back updates."""
import hashlib
from io import BytesIO
import json
import multiprocessing
from pathlib import Path
from tempfile import TemporaryDirectory
import time
import unittest
from unittest.mock import patch

from tools import moonleaf_publish as publish

DATA = b'a verified APK fixture'
CHECKSUM = hashlib.sha256(DATA).hexdigest()
CONFIG = {'package': 'com.noddlecake.novel_to_epub', 'certificate_sha256': 'ab' * 32}


def release(build=54):
    base = f'https://github.com/noddle-Cake/Moonleaf/releases/download/android-build-{build}/'
    return {'tag_name': f'android-build-{build}', 'draft': False, 'prerelease': False,
        'body': 'Release notes', 'assets': [
            {'name': 'chapter-and-verse.apk', 'size': len(DATA), 'browser_download_url': base + 'chapter-and-verse.apk'},
            {'name': 'chapter-and-verse.apk.sha256', 'browser_download_url': base + 'chapter-and-verse.apk.sha256'}]}


def concurrent_writer(lock, site, started):
    with publish.publication_lock(lock):
        part = Path(site) / 'download' / '.in-progress.apk.part'
        part.write_bytes(b'partial')
        started.set()
        time.sleep(.25)
        part.write_bytes(b'complete')


def concurrent_deploy(lock, source, site, result):
    with publish.publication_lock(lock):
        publish.deploy_static(source, site)
        result.put((Path(site) / 'download' / '.in-progress.apk.part').read_bytes())


class PublisherTests(unittest.TestCase):
    def setUp(self):
        self.temp = TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.site = self.root / 'site'
        (self.site / 'download').mkdir(parents=True)
        (self.site / 'index.html').write_text('https://github.com/noddle-Cake/Moonleaf/releases/latest/download/chapter-and-verse.apk')
        self.old = {'build': 52, 'sha256': 'cd' * 32}
        (self.site / 'app-update.json').write_text(json.dumps(self.old))

    def mirror(self, *, data=DATA, verify_error=None, current_release=None):
        checksum = (CHECKSUM + '  chapter-and-verse.apk\n').encode()
        with patch.object(publish, 'fetch', return_value=checksum), \
             patch.object(publish, 'urlopen', return_value=BytesIO(data)), \
             patch.object(publish, 'verify', return_value={'version_name': '1.0.0'}, side_effect=verify_error):
            return publish.mirror(self.site, self.root, release=current_release or release(), config=CONFIG)

    def test_verified_apk_precedes_atomic_metadata_and_links(self):
        manifest = self.mirror()
        self.assertEqual(manifest['build'], 54)
        self.assertEqual(manifest['sha256'], CHECKSUM)
        self.assertEqual((self.site / 'download/moonleaf-54.apk').read_bytes(), DATA)
        self.assertIn('/download/moonleaf-54.apk', (self.site / 'index.html').read_text())
        self.assertEqual(json.loads((self.site / 'app-update.json').read_text()), manifest)
        self.assertFalse(list(self.site.rglob('*.part')))

    def test_checksum_failure_keeps_previous_manifest_and_does_not_expose_apk(self):
        with self.assertRaisesRegex(ValueError, 'checksum'):
            self.mirror(data=b'incomplete')
        self.assertEqual(json.loads((self.site / 'app-update.json').read_text()), self.old)
        self.assertFalse((self.site / 'download/moonleaf-54.apk').exists())
        self.assertFalse(list(self.site.rglob('*.part')))

    def test_wrong_signer_keeps_previous_manifest_and_does_not_expose_apk(self):
        with self.assertRaisesRegex(ValueError, 'wrong signer'):
            self.mirror(verify_error=ValueError('wrong signer'))
        self.assertEqual(json.loads((self.site / 'app-update.json').read_text()), self.old)
        self.assertFalse((self.site / 'download/moonleaf-54.apk').exists())
        self.assertFalse(list(self.site.rglob('*.part')))

    def test_cached_apk_is_reverified_without_redownloading(self):
        (self.site / 'download/moonleaf-54.apk').write_bytes(DATA)
        with patch.object(publish, 'urlopen', side_effect=AssertionError('unexpected download')), \
             patch.object(publish, 'fetch', return_value=(CHECKSUM + '  chapter-and-verse.apk\n').encode()), \
             patch.object(publish, 'verify', return_value={'version_name': '1.0.0'}) as verify:
            publish.mirror(self.site, self.root, release=release(), config=CONFIG)
            verify.assert_called_once()

    def test_stale_github_response_does_not_roll_back_manifest_or_links(self):
        newer = {'build': 60, 'sha256': 'ef' * 32}
        (self.site / 'app-update.json').write_text(json.dumps(newer))
        self.assertEqual(self.mirror(), newer)
        self.assertIn('/download/moonleaf-60.apk', (self.site / 'index.html').read_text())
        self.assertEqual(json.loads((self.site / 'app-update.json').read_text()), newer)

    def test_republished_version_cannot_change_bytes(self):
        (self.site / 'app-update.json').write_text(json.dumps({'build': 54, 'sha256': 'ef' * 32}))
        with self.assertRaisesRegex(ValueError, 'different APK bytes'):
            self.mirror()

    def test_unexpected_or_ambiguous_release_urls_are_rejected(self):
        for case in ['host', 'duplicate', 'preview', 'old-debug']:
            with self.subTest(case=case):
                item = release(48 if case == 'old-debug' else 54)
                if case == 'host': item['assets'][0]['browser_download_url'] = 'https://evil.test/payload.apk'
                if case == 'duplicate': item['assets'].append(item['assets'][0])
                if case == 'preview': item['prerelease'] = True
                with self.assertRaises(ValueError): publish.release_assets(item)

    def test_static_deploy_preserves_verified_apks_live_metadata_and_parts(self):
        source = self.root / 'source'
        source.mkdir()
        (source / 'index.html').write_text('New website')
        (source / 'app-update.json').write_text('Never deploy generated metadata from source')
        apk = self.site / 'download/moonleaf-52.apk'
        apk.write_bytes(DATA)
        part = self.site / 'download/.in-progress.apk.part'
        part.write_bytes(b'partial')
        publish.deploy_static(source, self.site)
        self.assertEqual(apk.read_bytes(), DATA)
        self.assertEqual(part.read_bytes(), b'partial')
        self.assertEqual(json.loads((self.site / 'app-update.json').read_text()), self.old)

    def test_concurrent_deploy_waits_for_download_and_never_removes_its_part(self):
        source = self.root / 'source'
        source.mkdir()
        (source / 'index.html').write_text('New website')
        context = multiprocessing.get_context('fork')
        started, result = context.Event(), context.Queue()
        lock = self.root / 'outside-site.lock'
        writer = context.Process(target=concurrent_writer, args=(lock, self.site, started))
        deploy = context.Process(target=concurrent_deploy, args=(lock, source, self.site, result))
        writer.start()
        self.assertTrue(started.wait(3))
        deploy.start()
        writer.join(5); deploy.join(5)
        self.assertEqual(writer.exitcode, 0)
        self.assertEqual(deploy.exitcode, 0)
        self.assertEqual(result.get(timeout=2), b'complete')
        result.close()


if __name__ == '__main__': unittest.main()
