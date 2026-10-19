#!/usr/bin/env python3
"""Read-only packaging/signature gate; never launches the app or contacts Apple.

Use --distribution on an exported App Store candidate, not a development build.
Passing this local gate does not replace Xcode/App Store Connect validation.
"""
import argparse
import json
from pathlib import Path
import plistlib
import subprocess


def command(*args):
    return subprocess.run(args, check=True, capture_output=True).stdout


def verify(app, distribution=False, team=None, expected_id=None):
    app = Path(app).resolve(strict=True)
    with (app / 'Contents/Info.plist').open('rb') as source:
        info = plistlib.load(source)
    bundle_id = info.get('CFBundleIdentifier')
    if expected_id and bundle_id != expected_id:
        raise ValueError('Unexpected app identifier.')
    if distribution and bundle_id == 'art.genstation.demo':
        raise ValueError('Demo apps are not release candidates.')
    executable = app / 'Contents/MacOS' / info['CFBundleExecutable']
    launcher = app / 'Contents/Helpers/genstation-mcp'
    resource = app / 'Contents/Resources/genstation-mcp'
    for name in ('CLAUDE.md', 'settings.local.json', 'CHANGELOG.md'):
        if (app / 'Contents/Resources' / name).exists():
            raise ValueError('Development-only resource was packaged: ' + name)
    if not launcher.is_symlink() or launcher.resolve(strict=True) != resource:
        raise ValueError('Compatibility launcher must link to the sealed resource in this app.')
    expected = Path(__file__).parent / 'launcher/genstation-mcp'
    if resource.read_bytes() != expected.read_bytes():
        raise ValueError('Launcher differs from the reviewed source.')
    if not resource.stat().st_mode & 0o111:
        raise ValueError('Launcher is not executable.')
    # No second, unsandboxed helper executable may remain in the shipping bundle.
    helpers = list((app / 'Contents/Helpers').iterdir())
    if helpers != [launcher]:
        raise ValueError('Unexpected embedded helper files; review packaging.')
    command('codesign', '--verify', '--deep', '--strict', str(app))
    entitlement_bytes = command('codesign', '-d', '--entitlements', ':-', str(executable))
    entitlements = plistlib.loads(entitlement_bytes)
    if entitlements.get('com.apple.security.app-sandbox') is not True:
        raise ValueError('App executable must establish its own sandbox.')
    if entitlements.get('com.apple.security.inherit'):
        raise ValueError('External stdio launch cannot rely on sandbox inheritance.')
    signature = subprocess.run(['codesign', '-dvv', str(app)], check=True,
                               capture_output=True, text=True).stderr
    signed_team = next((line.split('=', 1)[1] for line in signature.splitlines()
                        if line.startswith('TeamIdentifier=')), 'not set')
    if signed_team == 'not set' or (team and signed_team != team) \
            or f'Identifier={bundle_id}\n' not in signature:
        raise ValueError('Unexpected signing team or identifier.')
    development = entitlements.get('com.apple.security.get-task-allow') is True
    if distribution:
        if development:
            raise ValueError('Distribution executable still permits debugger attachment.')
        if not any(authority in signature for authority in (
                'Authority=Apple Distribution:', 'Authority=3rd Party Mac Developer Application:')):
            raise ValueError('Expected App Store distribution signing identity.')
    architectures = command('lipo', '-archs', str(executable)).decode().strip().split()
    return {'bundle_id': bundle_id, 'version': info.get('CFBundleShortVersionString'),
            'build': info.get('CFBundleVersion'), 'architectures': architectures,
            'signature_verified': True, 'sandbox': True, 'inherits_sandbox': False,
            'development_debugging': development, 'launcher': str(launcher),
            'mcp_execution': 'sandboxed_app_stdio',
            'distribution_signing_checked': distribution,
            'app_store_validation': 'not_performed'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app')
    parser.add_argument('--distribution', action='store_true')
    parser.add_argument('--team', help='expected Apple Developer Team ID (default: any signed team)')
    parser.add_argument('--bundle-id', help='expected bundle identifier (default: any)')
    args = parser.parse_args()
    try:
        print(json.dumps(verify(args.app, args.distribution, args.team, args.bundle_id), indent=2))
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'Bundle verification failed: {error}\n')
