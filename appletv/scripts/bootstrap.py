#!/usr/bin/env python3
"""Install a pinned official VLC binary for TV or mobile before building."""
import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
URL = "https://download.videolan.org/cocoapods/prod/TVVLCKit-3.7.2-3e42ae47-79128878.tar.xz"
SHA256 = "fa264c2eb17d648669d9d12b51e76e5b6769828354517d09b340387b30825f58"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', choices=['tv', 'mobile'], default='tv')
    args = parser.parse_args()
    name = 'TVVLCKit' if args.platform == 'tv' else 'MobileVLCKit'
    url = URL if args.platform == 'tv' else "https://download.videolan.org/cocoapods/prod/MobileVLCKit-3.7.2-3e42ae47-79128878.tar.xz"
    checksum = SHA256 if args.platform == 'tv' else "77b867667e5e62aa4062e71b7a4f76a0e2f505425916091c0eb0f94d9ad4af80"
    vendor = ROOT / "Vendor"
    framework = vendor / f"{name}.xcframework"
    marker = vendor / f"{name}.sha256"
    if framework.is_dir() and marker.exists() and marker.read_text().strip() == checksum:
        print(f"{name} 3.7.2 is ready.")
        return
    vendor.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="torrenttube-vlckit-") as temporary:
        staging = Path(temporary)
        archive = staging / f"{name}.tar.xz"
        print(f"Downloading official {name} 3.7.2…", flush=True)
        digest = hashlib.sha256()
        with urllib.request.urlopen(url, timeout=60) as response, archive.open("wb") as output:
            while chunk := response.read(1024 * 1024):
                digest.update(chunk)
                output.write(chunk)
        if digest.hexdigest() != checksum:
            raise RuntimeError(f"{name} checksum mismatch; nothing was installed.")
        subprocess.run(["tar", "-xJf", str(archive), "-C", str(staging),
                        f"{name}-binary/{name}.xcframework", f"{name}-binary/COPYING.txt"], check=True)
        if framework.exists():
            shutil.rmtree(framework)
        shutil.copytree(staging / f"{name}-binary/{name}.xcframework", framework)
        shutil.copyfile(staging / f"{name}-binary/COPYING.txt", ROOT / "TorrentTube/VLCKit-COPYING.txt")
        marker.write_text(checksum + "\n")
    print(f"{name} 3.7.2 is ready. Open TorrentTubeTV.xcodeproj.")


if __name__ == "__main__":
    main()
