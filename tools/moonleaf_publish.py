"""Serialize website deployment and verified APK publication with one stable lock.

This is also the installed moonleaf-apk timer's implementation. Signing keys
are never needed here: only the public certificate pin and Android SDK tools.
"""
import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from urllib.request import Request, urlopen

if __package__:
    from .verify_android_release import verify
else:
    from verify_android_release import verify

REPO = "noddle-Cake/Moonleaf"
ORIGIN = "https://moonleaf.cjservin.com"
CONFIG = Path(__file__).resolve().parents[1] / "flutter_app/assets/android-update.json"


@contextmanager
def publication_lock(path):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    # A stable file, outside the served tree and the scripts being replaced.
    with path.open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def fetch(url, limit=1048576):
    request = Request(url, headers={"User-Agent": "Moonleaf-Publisher", "Cache-Control": "no-cache"})
    with urlopen(request, timeout=30) as response:
        data = response.read(limit + 1)
    if len(data) > limit:
        raise ValueError("Release metadata exceeds its size limit")
    return data


def permissions(path, site):
    path.chmod(0o644)
    if os.geteuid() == 0:
        owner = site.stat()
        os.chown(path, owner.st_uid, owner.st_gid)
        if Path("/sys/fs/selinux/enforce").exists():
            subprocess.run(["chcon", "--reference", str(site / "index.html"), str(path)], check=True)


def atomic_write(path, data, site):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".part", dir=path.parent)
    temp = Path(temp)
    try:
        with os.fdopen(fd, "wb") as output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
        permissions(temp, site)
        os.replace(temp, path)
    finally:
        temp.unlink(missing_ok=True)


def deploy_static(source, site):
    """Never remove the download directory, in-progress files or live metadata."""
    source, site = Path(source), Path(site)
    if not (source / "index.html").is_file():
        raise ValueError("Website source is missing index.html")
    for item in source.rglob("*"):
        if item.is_symlink():
            raise ValueError("Website source must not contain symbolic links")
        if item.is_file() and item.name != "app-update.json":
            atomic_write(site / item.relative_to(source), item.read_bytes(), site)


def release_assets(release):
    tag = release.get("tag_name", "")
    match = re.fullmatch(r"android-build-([0-9]+)", tag)
    if not match or release.get("draft") or release.get("prerelease") or int(match[1]) < 52:
        raise ValueError("Latest release is not a stable signed Android build")
    assets = {}
    for name in ("chapter-and-verse.apk", "chapter-and-verse.apk.sha256"):
        found = [a for a in release.get("assets", []) if a.get("name") == name]
        expected = f"https://github.com/{REPO}/releases/download/{tag}/{name}"
        if len(found) != 1 or found[0].get("browser_download_url") != expected:
            raise ValueError(f"Release asset is missing or has an unexpected URL: {name}")
        assets[name] = found[0]
    size = assets["chapter-and-verse.apk"].get("size")
    if not isinstance(size, int) or not 0 < size <= 1073741824:
        raise ValueError("Invalid release APK size")
    return int(match[1]), assets


def file_matches(path, size, checksum):
    if not path.is_file() or path.stat().st_size != size:
        return False
    with path.open("rb") as data:
        digest = hashlib.sha256()
        while chunk := data.read(65536):
            digest.update(chunk)
        return digest.hexdigest() == checksum


def download_apk(url, target, size, checksum, site):
    fd, temp = tempfile.mkstemp(prefix=f".{target.name}.", suffix=".part", dir=target.parent)
    temp = Path(temp)
    try:
        digest, count = hashlib.sha256(), 0
        with os.fdopen(fd, "wb") as output:
            with urlopen(Request(url, headers={"User-Agent": "Moonleaf-Publisher"}), timeout=30) as response:
                while chunk := response.read(65536):
                    count += len(chunk)
                    if count > size:
                        raise ValueError("APK is larger than the published asset")
                    digest.update(chunk)
                    output.write(chunk)
            output.flush()
            os.fsync(output.fileno())
        if count != size or digest.hexdigest() != checksum:
            raise ValueError("APK size or checksum does not match the release")
        # Do not expose the final filename until the certificate is checked.
        return temp
    except BaseException:
        temp.unlink(missing_ok=True)
        raise


def update_links(site, build):
    url = f"{ORIGIN}/download/moonleaf-{build}.apk"
    for page in site.rglob("*.html"):
        old = page.read_text()
        new = old.replace(f"https://github.com/{REPO}/releases/latest/download/chapter-and-verse.apk", url)
        new = re.sub(r"(?:https://moonleaf\.cjservin\.com)?/download/moonleaf-[0-9]+\.apk", url, new)
        if old != new:
            atomic_write(page, new.encode(), site)


def mirror(site, sdk, expected_build=None, release=None, config=None):
    site = Path(site)
    config = config or json.loads(CONFIG.read_text())
    release = release or json.loads(fetch(f"https://api.github.com/repos/{REPO}/releases/latest"))
    build, assets = release_assets(release)
    if expected_build is not None and build < expected_build:
        raise ValueError("GitHub has not exposed the expected release yet; retry shortly")
    current_path = site / "app-update.json"
    current = json.loads(current_path.read_text()) if current_path.exists() else {}
    if current.get("build", 0) > build:
        # A stale GitHub response must never roll back the update or site links.
        update_links(site, current["build"])
        return current
    checksum_data = fetch(assets["chapter-and-verse.apk.sha256"]["browser_download_url"], 1024).decode()
    match = re.fullmatch(r"([a-f0-9]{64})\s+\*?chapter-and-verse\.apk\s*", checksum_data)
    if not match:
        raise ValueError("Invalid release checksum file")
    checksum = match[1]
    if current.get("build") == build and current.get("sha256") != checksum:
        raise ValueError("A published version cannot be replaced with different APK bytes")
    asset = assets["chapter-and-verse.apk"]
    size = asset["size"]
    target = site / "download" / f"moonleaf-{build}.apk"
    target.parent.mkdir(parents=True, exist_ok=True)
    temp = None
    try:
        candidate = target
        if not file_matches(target, size, checksum):
            temp = download_apk(asset["browser_download_url"], target, size, checksum, site)
            candidate = temp
        # Verification uses only public data. No signing credentials are read.
        previous = {key: os.environ.get(key) for key in ("ANDROID_HOME", "EXPECTED_CERT_SHA256")}
        try:
            os.environ.update(ANDROID_HOME=str(sdk), EXPECTED_CERT_SHA256=config["certificate_sha256"])
            metadata = verify(str(candidate), str(build))
        finally:
            for key, value in previous.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value
        permissions(candidate, site)
        if temp is not None:
            os.replace(temp, target)
            temp = None
        notes = str(release.get("body") or "")
        if notes.startswith("## Download"):
            notes = "Published Android release. See the release page for details."
        else:
            notes = notes.split("\n## Download", 1)[0].removeprefix("## What’s new").strip()
        manifest = {"schema": 1, "package": config["package"], "build": build,
            "version_name": metadata["version_name"], "certificate_sha256": config["certificate_sha256"],
            "size": size, "sha256": checksum, "apk_url": f"{ORIGIN}/download/{target.name}",
            "release_url": f"https://github.com/{REPO}/releases/tag/android-build-{build}",
            "notes": notes[:8000]}
        atomic_write(current_path, json.dumps(manifest, ensure_ascii=False).encode(), site)
        update_links(site, build)
        print(f"Published verified Android build {build}")
        return manifest
    finally:
        if temp is not None:
            temp.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("mirror", "deploy"))
    parser.add_argument("--site", type=Path, default=Path("/srv/websvc/sites/moonleaf/html"))
    parser.add_argument("--source", type=Path)
    parser.add_argument("--sdk", type=Path, default=Path("/home/chris/Android/Sdk"))
    parser.add_argument("--lock", type=Path, default=Path("/run/lock/moonleaf-publish.lock"))
    parser.add_argument("--expected-build", type=int)
    args = parser.parse_args()
    with publication_lock(args.lock):
        if args.action == "deploy":
            if not args.source:
                parser.error("deploy requires --source")
            deploy_static(args.source, args.site)
        mirror(args.site, args.sdk, args.expected_build)


if __name__ == "__main__":
    main()
