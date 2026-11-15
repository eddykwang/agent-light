"""Exercise packaging gates without certificates, Apple uploads or user data."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
MOCK = r'''#!/usr/bin/env python3
import json, os, pathlib, shutil, sys, zipfile
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['EVENTS'], 'a') as log:
    log.write(json.dumps([name, *args]) + '\n')
if os.environ.get('FAIL') == name or os.environ.get('FAIL') == ' '.join([name, *args[:2]]):
    sys.exit(1)
if name == 'swift' and '--show-bin-path' in args:
    print(os.environ['BINARIES'])
elif name == 'codesign' and '--display' in args:
    print('TeamIdentifier=' + os.environ.get('ACTUAL_TEAM', os.environ['APPLE_TEAM_ID']))
    print('Authority=Developer ID Application: Test')
    print('Timestamp=Nov 14, 2026')
    print('CodeDirectory v=20500 flags=0x10000(runtime)')
elif name == 'xcrun' and args[:2] == ['notarytool', 'submit']:
    print(json.dumps({'id': 'test-submission', 'status': os.environ.get('NOTARY_STATUS', 'Accepted')}))
elif name == 'ditto':
    source, dest = map(pathlib.Path, args[-2:])
    if '-c' in args:
        with zipfile.ZipFile(dest, 'w') as archive:
            for item in source.rglob('*'):
                if item.is_file():
                    archive.write(item, item.relative_to(source.parent))
    else:
        with zipfile.ZipFile(source) as archive:
            archive.extractall(dest)
'''


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'script').mkdir()
        for name in ('package_release.sh', 'verify_release.sh', 'check_release_contents.py'):
            shutil.copy(REPO / 'script' / name, self.root / 'script' / name)
        resources = self.root / 'Resources'
        resources.mkdir()
        (resources / 'AppIcon.icns').write_text('icon')
        for name in ('ProviderIcons', 'DesktopLightAssets'):
            (resources / name).mkdir()
            (resources / name / 'asset').write_text('asset')
        binaries = self.root / 'binaries'
        binaries.mkdir()
        for name in ('AgentTrafficLights', 'AgentStatusCollector', 'AgentClaudeHook', 'AgentCopilotHook'):
            (binaries / name).write_text('test executable')
        mocks = self.root / 'mocks'
        mocks.mkdir()
        for name in ('swift', 'codesign', 'xcrun', 'spctl', 'ditto'):
            path = mocks / name
            path.write_text(MOCK)
            path.chmod(0o755)
        self.env = {**os.environ, 'PATH': f'{mocks}:{os.environ["PATH"]}',
                    'SIGNING_IDENTITY': 'Developer ID Application: Test',
                    'APPLE_TEAM_ID': 'TESTTEAM00', 'NOTARY_PROFILE': 'test-profile',
                    'EVENTS': str(self.root / 'events'), 'BINARIES': str(binaries),
                    'GITHUB_RUN_NUMBER': '1'}
        self.output = self.root / 'dist/Agent-Light-v0.1.6-macOS.zip'

    def run_package(self, version='v0.1.6'):
        return subprocess.run(['bash', str(self.root / 'script/package_release.sh'), version],
                              env=self.env, capture_output=True, text=True)

    def events(self):
        path = Path(self.env['EVENTS'])
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def test_missing_credentials_fails_before_build(self):
        for key in ('SIGNING_IDENTITY', 'APPLE_TEAM_ID', 'NOTARY_PROFILE'):
            with self.subTest(key=key):
                value = self.env.pop(key)
                self.assertNotEqual(self.run_package().returncode, 0)
                self.env[key] = value
        self.assertEqual(self.events(), [])

    def test_invalid_identity_team_or_version_fails_before_build(self):
        for key, invalid in (('SIGNING_IDENTITY', '-'), ('APPLE_TEAM_ID', 'bad'),
                             ('GITHUB_RUN_NUMBER', '1<bad>')):
            with self.subTest(key=key):
                original = self.env[key]
                self.env[key] = invalid
                self.assertNotEqual(self.run_package().returncode, 0)
                self.env[key] = original
        self.assertNotEqual(self.run_package('v0.1.6<bad>').returncode, 0)
        self.assertEqual(self.events(), [])

    def test_failures_do_not_produce_release(self):
        for command in ('xcrun notarytool history', 'codesign', 'xcrun notarytool submit',
                        'xcrun stapler staple', 'xcrun stapler validate', 'spctl'):
            with self.subTest(command=command):
                self.env['FAIL'] = command
                result = self.run_package()
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertFalse(self.output.exists())

    def test_rejected_notarization_stops_before_stapling(self):
        self.env['NOTARY_STATUS'] = 'Invalid'
        self.assertNotEqual(self.run_package().returncode, 0)
        self.assertFalse(any(e[:3] == ['xcrun', 'stapler', 'staple'] for e in self.events()))
        self.assertFalse(self.output.exists())

    def test_wrong_team_is_rejected(self):
        self.env['ACTUAL_TEAM'] = 'WRONGTEAM0'
        self.assertNotEqual(self.run_package().returncode, 0)
        self.assertFalse(self.output.exists())

    def test_private_material_is_rejected(self):
        asset = self.root / 'Resources/ProviderIcons'
        for name, content in (('secret.p12', 'binary'),
                              ('unexpected.txt', '-----BEGIN PRIVATE KEY-----')):
            with self.subTest(name=name):
                path = asset / name
                path.write_text(content)
                result = self.run_package()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('in app:', result.stderr)
                self.assertFalse(self.output.exists())
                self.assertFalse(any(e[:3] == ['xcrun', 'notarytool', 'submit'] for e in self.events()))
                path.unlink()

    def test_success_signs_inside_out_and_repacks_after_stapling(self):
        result = self.run_package()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(self.output.exists())
        events = self.events()
        signed = [Path(e[-1]).name for e in events if e[0] == 'codesign' and '--sign' in e]
        self.assertEqual(signed, ['AgentStatusCollector', 'AgentClaudeHook', 'AgentCopilotHook', 'Agent Light.app'])
        staple = next(i for i, e in enumerate(events) if e[:3] == ['xcrun', 'stapler', 'staple'])
        archives = [i for i, e in enumerate(events) if e[0] == 'ditto' and '-c' in e]
        self.assertEqual(len(archives), 2)
        self.assertLess(archives[0], staple)
        self.assertGreater(archives[1], staple)
