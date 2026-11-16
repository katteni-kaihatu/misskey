#!/usr/bin/env python3
# SPDX-FileCopyrightText: syuilo and misskey-project
# SPDX-License-Identifier: AGPL-3.0-only

"""Keep a paired wired CoreDevice transport alive for private parity tests."""
import argparse
import ipaddress
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import tempfile
import time


def endpoints(details, interfaces):
    connection = details.get('result', {}).get('connectionProperties', {})
    if connection.get('transportType') != 'wired' or connection.get('tunnelState') != 'connected':
        raise RuntimeError('A connected wired CoreDevice transport is required')
    peer = ipaddress.IPv6Address(connection.get('tunnelIPAddress', ''))
    if peer.packed[0] & 0xfe != 0xfc:
        raise RuntimeError('The USB peer must use a private IPv6 ULA address')
    network = ipaddress.IPv6Network((peer, 64), strict=False)
    candidates = set()
    for raw in re.findall(r'^\s*inet6\s+(\S+)', interfaces, re.MULTILINE):
        address = ipaddress.IPv6Address(raw.split('%', 1)[0])
        if address in network and address != peer:
            candidates.add(address)
    if len(candidates) != 1:
        raise RuntimeError('Exactly one Mac address must match the USB network')
    return {'address': next(iter(candidates)).compressed, 'peer': peer.compressed}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run-dir', type=Path, required=True)
    parser.add_argument('--seconds', type=int, default=900)
    args = parser.parse_args()
    if not 1 <= args.seconds <= 3600:
        parser.error('--seconds must be between 1 and 3600')
    device = os.environ.get('IOS_DEVICE')
    if not device:
        parser.error('Set IOS_DEVICE to the intended paired device identifier')
    os.umask(0o077)
    directory = args.run_dir.resolve()
    repository = Path(__file__).resolve().parents[3]
    if directory.is_relative_to(repository) or not directory.name.startswith('gridspace-ios-parity-'):
        parser.error('Use a dedicated private gridspace-ios-parity-* directory outside the checkout')
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    directory.chmod(0o700)
    output = directory / 'usb-transport.json'
    if output.exists():
        parser.error('Transport metadata already exists; stop its owner or use a fresh directory')
    expected = None
    deadline = time.monotonic() + args.seconds

    def stop(_signal, _frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, stop)
    try:
        with tempfile.TemporaryDirectory(prefix='gridspace-ios-parity-transport-') as temporary:
            details = Path(temporary) / 'device.json'
            while time.monotonic() < deadline:
                subprocess.run(['xcrun', 'devicectl', 'device', 'info', 'details', '--device', device,
                                '--json-output', str(details)], check=True, timeout=20,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                interfaces = subprocess.check_output(['ifconfig'], text=True, timeout=10)
                current = endpoints(json.loads(details.read_text()), interfaces)
                if expected is not None and current != expected:
                    raise RuntimeError('USB addresses changed; stop tests and recreate the private fixture')
                with tempfile.NamedTemporaryFile(mode='w', dir=directory, delete=False) as staging:
                    json.dump({'version': 1, 'transport': 'wired', 'pid': os.getpid(), 'updatedAt': time.time(), **current}, staging)
                os.replace(staging.name, output)
                if expected is None:
                    print('USB_PARITY_TRANSPORT_READY — private usb-transport.json is refreshed while this process runs', flush=True)
                expected = current
                time.sleep(min(5, max(0, deadline - time.monotonic())))
    except KeyboardInterrupt:
        pass
    except (RuntimeError, ValueError, OSError, subprocess.SubprocessError) as error:
        # Do not echo devicectl arguments, identifiers or its full device JSON.
        parser.exit(1, (str(error) if isinstance(error, RuntimeError) else 'USB parity transport unavailable') + '\n')
    finally:
        output.unlink(missing_ok=True)


if __name__ == '__main__':
    main()
