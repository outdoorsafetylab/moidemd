#!/usr/bin/env python3
"""Download the MOI DTM rasters this image serves.

The files are written exactly as published -- unpacked from their distribution
archives and not otherwise touched. No reprojection, resampling, compression or
clipping: the elevations this service returns have to be the government's own
numbers, checkable against the originals.

That claim is only worth making if it is enforced, so every extracted file is
checked against a recorded SHA-256. A mismatch stops the build rather than
quietly baking different terrain into the image.

Two things about the distribution are worth knowing:

  * the URLs carry Chinese filenames and the server rejects them unless they
    are percent-encoded, and
  * the archives store those names in Big5, which Python's zipfile decodes as
    cp437 unless told otherwise.

    usage: fetch-dem.py [<target-dir>]
"""
import hashlib
import os
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile

TGOS = "https://www.tgos.tw/MDE/VirtualDir_TC/Product"

# (subdirectory, product uuid, archive name, {extracted file: sha256}).
#
# The archive name is the filename from the index's 連結網址 column, which is
# NOT the 圖資名稱 shown beside it: the main-island archive is published as
# 不分幅_全台20MDEM(2025).zip while its display name reads 台灣. Penghu and
# Kinmen happen to agree, so checking one of those proves nothing about this.
#
# The hashes are of the extracted rasters rather than of the archives: they are
# what ends up in the image and what the provenance claim is about, and they
# survive the archive being repackaged around identical data.
#
# 內政部 updates these irregularly. A mismatch is therefore expected eventually
# and is not automatically a fault -- but it does mean the served elevations
# would change, so it has to be a deliberate, reviewed update rather than
# something a build picks up on its own. See README.md.
ARCHIVES = [
    ("2025", "528530be-0710-431e-954e-2f2f5e98b0c5", "不分幅_全台20MDEM(2025).zip", {
        "DEM_tawiwan_V2025.tif": "59e5e980000d6e3f5a7734c6af197934a1a5432482b6caa789a1ec90b624015d",
        "DEM_tawiwan_V2025.tfw": "7e497cc09921a3fa2091d1a3680d99721883145ef77f700b88bc4211270ffa32",
    }),
    ("2025", "47910269-7315-4cd2-9101-7cdf524b47f5", "不分幅_澎湖20MDEM(2025).zip", {
        "DEM_Penghu_V2025.tif": "1185ce22a43b9134d60689467ebddb08e5ba14bf7ceef0fce453b158616e7e94",
        "DEM_Penghu_V2025.tfw": "ca97fa0bcb54b1890c638da4c288a977ebc6a067f5952c99699eda2a669b0bfb",
    }),
    ("2025", "0e018335-80f1-4489-990c-ecf2bef1a9b6", "不分幅_金門20MDEM(2025).zip", {
        "DEM_KinMen_V2025.tif": "51aefce42b8506ec808ca3b7117e95e09f7cc1ba5ebc8538abc4adcee4249bcd",
        "DEM_KinMen_V2025.tfw": "a34645e62f6ae29e8eb436b395bff9142155de00fcc3b890f17f3b5c278476cd",
    }),
]

KEEP = (".tif", ".tfw")


class ChecksumError(Exception):
    pass


def tls_context():
    """A verifying context that tolerates tgos.tw's certificate chain.

    OpenSSL 3.5 enables strict RFC 5280 conformance checks, and Python 3.13
    turns them on by default; one of the CA certificates in tgos.tw's chain
    has no Subject Key Identifier extension, so the handshake is rejected
    outright. Clearing that one flag keeps chain and hostname verification --
    it only stops requiring the certificates to be well-formed by the newer
    reading. The bytes are pinned by SHA-256 regardless.
    """
    ctx = ssl.create_default_context()
    ctx.verify_flags &= ~ssl.VERIFY_X509_STRICT
    return ctx


def is_retryable(err):
    """Whether another attempt could plausibly succeed.

    A rejected certificate or a 404 will be rejected identically twenty times
    over; only transport faults and server-side transients are worth repeating.

    urlopen() reports a failed handshake as URLError with the real exception
    in .reason -- the build log's "<urlopen error [SSL: ...]>" is that wrapper
    -- so the interesting exception is usually one level down.
    """
    if isinstance(err, urllib.error.HTTPError):
        return err.code == 429 or err.code >= 500
    if isinstance(err, urllib.error.URLError):
        reason = err.reason
        return is_retryable(reason) if isinstance(reason, BaseException) else True
    if isinstance(err, ssl.SSLCertVerificationError):
        return False
    return True


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def remote_size(url):
    req = urllib.request.Request(url, method="HEAD")
    with urllib.request.urlopen(req, timeout=60, context=tls_context()) as r:
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
            with urllib.request.urlopen(req, timeout=120, context=tls_context()) as r:
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
            if not is_retryable(e):
                raise RuntimeError("%s: %s" % (url, e)) from e
        if attempt < attempts:
            pause(attempt)
    raise RuntimeError("failed to download %s" % url)


def extract(archive, target, digests):
    """Unpack the rasters and verify each against its recorded SHA-256."""
    z = zipfile.ZipFile(archive)
    seen = []
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
            for chunk in iter(lambda: src.read(1 << 20), b""):
                dst.write(chunk)
        want = digests.get(base)
        if want is None:
            raise ChecksumError(
                "%s: no recorded SHA-256 for this file. The archive's contents "
                "have changed; see README.md before updating." % base)
        got = sha256(out)
        if got != want:
            raise ChecksumError(
                "%s: SHA-256 mismatch\n"
                "    recorded %s\n"
                "    got      %s\n"
                "  The published data has changed, so the elevations this "
                "service returns would change too. That has to be a reviewed "
                "update, not something a build picks up on its own; see "
                "README.md." % (base, want, got))
        seen.append(base)
        print("  %s (%d bytes, sha256 ok)" % (base, os.path.getsize(out)))
    missing = sorted(set(digests) - set(seen))
    if missing:
        raise ChecksumError(
            "%s: expected but not present in the archive: %s"
            % (os.path.basename(archive), ", ".join(missing)))


def check_urls():
    """HEAD every archive before fetching any of them.

    A wrong URL is otherwise indistinguishable from a withdrawn file, and only
    surfaces after the earlier downloads have already run. Reporting all of
    them together, in seconds, keeps a typo from looking like an outage.
    """
    bad = []
    for _sub, uuid, name, _digests in ARCHIVES:
        url = "%s/%s/%s" % (TGOS, uuid, urllib.parse.quote(name))
        try:
            size = remote_size(url)
            print("  ok   %-34s %d bytes" % (name, size))
        except Exception as e:
            print("  FAIL %-34s %s" % (name, e))
            bad.append((name, e))
    if bad:
        raise RuntimeError(
            "%d of %d archives are not reachable; check the 連結網址 column of "
            "the index at https://data.gov.tw/dataset/176927 -- the filename "
            "there differs from the 圖資名稱" % (len(bad), len(ARCHIVES)))


def main(root):
    check_urls()
    cache = os.path.join(root, ".archives")
    os.makedirs(cache, exist_ok=True)
    for sub, uuid, name, digests in ARCHIVES:
        target = os.path.join(root, sub)
        os.makedirs(target, exist_ok=True)
        url = "%s/%s/%s" % (TGOS, uuid, urllib.parse.quote(name))
        archive = os.path.join(cache, name)
        print("%s -> %s/" % (name, sub))
        download(url, archive)
        extract(archive, target, digests)
    # Filenames are kept as published, so the Makefile keys off this instead.
    with open(os.path.join(root, ".fetched"), "w") as f:
        for sub, _, name, _digests in ARCHIVES:
            f.write("%s\t%s\n" % (sub, name))


if __name__ == "__main__":
    args = sys.argv[1:]
    if "--check" in args:
        check_urls()
    else:
        main(args[0] if args else "dem")
