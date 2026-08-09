#!/usr/bin/env python3
"""Download the MOI DTM rasters this image serves.

The files are written exactly as published -- unpacked from their distribution
archives and not otherwise touched. No reprojection, resampling, compression or
clipping: the elevations this service returns have to be the government's own
numbers, checkable against the originals.

Two things about the distribution are worth knowing:

  * the URLs carry Chinese filenames and the server rejects them unless they
    are percent-encoded, and
  * the archives store those names in Big5, which Python's zipfile decodes as
    cp437 unless told otherwise.

    usage: fetch-dem.py [<target-dir>]
"""
import os
import sys
import urllib.parse
import urllib.request
import zipfile

TGOS = "https://www.tgos.tw/MDE/VirtualDir_TC/Product"

# (subdirectory, product uuid, archive name).
ARCHIVES = [
    ("2025", "528530be-0710-431e-954e-2f2f5e98b0c5", "不分幅_台灣20MDEM(2025).zip"),
    ("2025", "47910269-7315-4cd2-9101-7cdf524b47f5", "不分幅_澎湖20MDEM(2025).zip"),
    ("2025", "0e018335-80f1-4489-990c-ecf2bef1a9b6", "不分幅_金門20MDEM(2025).zip"),
]

KEEP = (".tif", ".tfw")


def download(url, path):
    # tgos.tw drops long transfers, so resume rather than restart.
    have = os.path.getsize(path) if os.path.exists(path) else 0
    for attempt in range(20):
        req = urllib.request.Request(url)
        if have:
            req.add_header("Range", "bytes=%d-" % have)
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                total = have + int(r.headers.get("Content-Length") or 0)
                with open(path, "ab" if have else "wb") as f:
                    while True:
                        chunk = r.read(1 << 20)
                        if not chunk:
                            break
                        f.write(chunk)
                        have += len(chunk)
        except Exception as e:
            print("  attempt %d: %s" % (attempt + 1, e))
        have = os.path.getsize(path)
        if total and have >= total:
            return
        print("  resuming at %d bytes" % have)
    sys.exit("failed to download %s" % url)


def extract(archive, target):
    z = zipfile.ZipFile(archive)
    for info in z.infolist():
        name = info.filename
        try:
            name = name.encode("cp437").decode("big5")
        except (UnicodeEncodeError, UnicodeDecodeError):
            pass
        base = os.path.basename(name)
        if not base.lower().endswith(KEEP):
            continue
        out = os.path.join(target, base)
        with z.open(info) as src, open(out, "wb") as dst:
            dst.write(src.read())
        print("  %s (%d bytes)" % (base, os.path.getsize(out)))


def main(root):
    cache = os.path.join(root, ".archives")
    os.makedirs(cache, exist_ok=True)
    for sub, uuid, name in ARCHIVES:
        target = os.path.join(root, sub)
        os.makedirs(target, exist_ok=True)
        url = "%s/%s/%s" % (TGOS, uuid, urllib.parse.quote(name))
        archive = os.path.join(cache, name)
        print("%s -> %s/" % (name, sub))
        download(url, archive)
        extract(archive, target)
    # Filenames are kept as published, so the Makefile keys off this instead.
    with open(os.path.join(root, ".fetched"), "w") as f:
        for sub, _, name in ARCHIVES:
            f.write("%s\t%s\n" % (sub, name))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "dem")
