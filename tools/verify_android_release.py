"""Refuse to publish an APK whose signing identity or upgrade version changed."""
import os
from pathlib import Path
import re
import subprocess
import sys


def verify(apk, version):
    expected = os.environ.get("EXPECTED_CERT_SHA256", "").replace(":", "").lower()
    if not re.fullmatch(r"[0-9a-f]{64}", expected):
        raise ValueError("ANDROID_SIGNING_CERT_SHA256 must pin the release certificate")
    sdk = Path(os.environ.get("ANDROID_HOME") or os.environ["ANDROID_SDK_ROOT"])
    build_tools = sorted((sdk / "build-tools").iterdir(),
                         key=lambda p: tuple(int(n) for n in re.findall(r"\d+", p.name)))
    signer = next(p / "apksigner" for p in reversed(build_tools) if (p / "apksigner").exists())
    certs = subprocess.check_output([str(signer), "verify", "--print-certs", apk], text=True)
    # SDK 37 prints "V2 Signer:" (and can list multiple schemes); older
    # versions use "Signer #1" or SDK ranges. Source stamps aren't app signers.
    digests = {d.lower() for d in re.findall(
        r"^(?:Signer\b|V[0-9.]+ Signer\b)[^\r\n]*? certificate SHA-256 digest: "
        r"([0-9a-fA-F]{64})[ \t]*$", certs, re.M)}
    if digests != {expected}:
        raise ValueError("APK signer does not match Moonleaf's permanent certificate; "
                         f"expected {expected}, found {sorted(digests)}")
    manifest = subprocess.check_output([str(signer.parent / "aapt"), "dump", "badging", apk], text=True)
    package = re.search(r"package: name='([^']+)' versionCode='(\d+)'", manifest)
    if not package or package.groups() != ("com.noddlecake.novel_to_epub", str(int(version))):
        raise ValueError("APK application ID or version code would break in-place updates")
    if "application-debuggable" in manifest:
        raise ValueError("Published APK must be a release build")
    print(f"Release signature, application ID and version code {version} verified.")


if __name__ == "__main__":
    verify(*sys.argv[1:])
