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
import time
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


def remote_size(url):
    req = urllib.request.Request(url, method="HEAD")
    with urllib.request.urlopen(req, timeout=60) as r:
        return int(r.headers.get("Content-Length") or 0)


def download(url, path, attempts=20, pause=lambda n: time.sleep(min(2 ** n, 30))):
    """Fetch url to path, resuming a partial file rather than restarting.

    tgos.tw drops long transfers -- the main island archive is ~270 MB and
    rarely arrives in one go -- so every attempt re-reads what is already on
    disk and asks for the remainder. The expected size is taken from the
    server so a truncated file is never mistaken for a complete one.
    """
    expected = 0
    for attempt in range(1, attempts + 1):
        try:
            if not expected:
                expected = remote_size(url)
            have = os.path.getsize(path) if os.path.exists(path) else 0
            if expected and have == expected:
                return
            if have > expected:
                # Left over from a different (or corrupt) fetch.
                have = 0
            req = urllib.request.Request(url)
            if have:
                req.add_header("Range", "bytes=%d-" % have)
            with urllib.request.urlopen(req, timeout=120) as r:
                # A server free to ignore Range answers 200 with the whole
                # body; appending that to what we have would corrupt the file.
                if have and getattr(r, "status", r.getcode()) != 206:
                    have = 0
                with open(path, "ab" if have else "wb") as f:
                    while True:
                        chunk = r.read(1 << 20)
                        if not chunk:
                            break
                        f.write(chunk)
            got = os.path.getsize(path) if os.path.exists(path) else 0
            if expected and got >= expected:
                return
            print("  attempt %d: got %d of %d bytes" % (attempt, got, expected))
        except Exception as e:
            print("  attempt %d: %s" % (attempt, e))
        if attempt < attempts:
            pause(attempt)
    raise RuntimeError("failed to download %s" % url)


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
