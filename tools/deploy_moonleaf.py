"""Deploy the existing Moonleaf host without racing its scheduled APK mirror."""
import argparse
import os
from pathlib import Path
import shlex
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--expected-build', type=int)
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.error('Run this host deployment command as root')
    repo = Path(__file__).resolve().parents[1]
    site = Path('/srv/websvc/sites/moonleaf/html')
    if not (site / 'index.html').exists():
        parser.error('Provision the Moonleaf website before deploying updates')
    subprocess.run(['sudo', '-u', 'chris', '-H', 'git', '-C', str(repo), 'pull', '--ff-only'], check=True)
    # The legacy timer locked its executable, so replacing it defeated its lock.
    # Stop it before migrating; all new entry points use the stable Python lock.
    subprocess.run(['systemctl', 'stop', 'moonleaf-apk.timer', 'moonleaf-apk.service'], check=True)
    try:
        publisher = repo / 'tools/moonleaf_publish.py'
        wrapper = Path('/usr/local/sbin/moonleaf-apk')
        wrapper.write_text('#!/bin/sh\nexec /usr/bin/python3 ' + shlex.quote(str(publisher)) + ' mirror "$@"\n')
        wrapper.chmod(0o755)
        Path('/etc/systemd/system/moonleaf-apk.service').write_text(
            '[Unit]\nDescription=Publish verified Moonleaf APK and update metadata\n'
            'After=network-online.target\nWants=network-online.target\n\n'
            '[Service]\nType=oneshot\n'
            'ExecStart=/usr/local/sbin/moonleaf-apk\nTimeoutStartSec=1800\n')
        subprocess.run(['systemctl', 'daemon-reload'], check=True)
        command = [sys.executable, str(publisher), 'deploy', '--site', str(site),
                   '--source', str(repo / 'site')]
        if args.expected_build:
            command += ['--expected-build', str(args.expected_build)]
        subprocess.run(command, check=True)
    finally:
        subprocess.run(['systemctl', 'enable', '--now', 'moonleaf-apk.timer'], check=True)


if __name__ == '__main__':
    main()
