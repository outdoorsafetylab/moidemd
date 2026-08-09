#!/usr/bin/env python3
"""Tests for scripts/fetch-dem.py's download path.

The retry and resume logic exists because tgos.tw drops long transfers, so the
interesting cases are all failures: a connection that dies partway, a server
that ignores Range, and one that never answers. Those are exactly the paths a
successful download never touches, so they get a local server that misbehaves
on purpose rather than the real one.

    usage: test_fetch.py
"""
import hashlib
import http.server
import importlib.util
import os
import socketserver
import sys
import tempfile
import threading
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
BODY = bytes(range(256)) * 400  # 102400 bytes, easy to compare

failures = []


def check(name, ok, detail=""):
    print(("  ok    %s" if ok else "  FAIL  %s") % name + (" -- %s" % detail if detail else ""))
    if not ok:
        failures.append(name)


def load():
    spec = importlib.util.spec_from_file_location(
        "fetchdem", os.path.join(HERE, os.pardir, "scripts", "fetch-dem.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


class Handler(http.server.BaseHTTPRequestHandler):
    """Serves BODY. cut_after truncates the body; ignore_range answers 200."""
    cut_after = None
    ignore_range = False
    fail_times = 0
    seen = 0

    def log_message(self, *a):
        pass

    def do_HEAD(self):
        self.send_response(200)
        self.send_header("Content-Length", str(len(BODY)))
        self.end_headers()

    def do_GET(self):
        cls = type(self)
        cls.seen += 1
        if cls.fail_times > 0:
            cls.fail_times -= 1
            self.send_response(503)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        start = 0
        rng = self.headers.get("Range")
        if rng and not cls.ignore_range:
            start = int(rng.split("=")[1].split("-")[0])
            self.send_response(206)
            self.send_header("Content-Range",
                             "bytes %d-%d/%d" % (start, len(BODY) - 1, len(BODY)))
        else:
            self.send_response(200)
        chunk = BODY[start:]
        if cls.cut_after is not None:
            chunk = chunk[:cls.cut_after]
        self.send_header("Content-Length", str(len(BODY) - start))
        self.end_headers()
        self.wfile.write(chunk)


def serve():
    httpd = socketserver.TCPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd, "http://127.0.0.1:%d/f.bin" % httpd.server_address[1]


def reset(**kw):
    Handler.cut_after = kw.get("cut_after")
    Handler.ignore_range = kw.get("ignore_range", False)
    Handler.fail_times = kw.get("fail_times", 0)
    Handler.seen = 0


def main():
    m = load()
    httpd, url = serve()
    tmp = tempfile.mkdtemp(prefix="fetch-test-")
    path = os.path.join(tmp, "f.bin")
    nopause = lambda n: None

    reset()
    m.download(url, path, pause=nopause)
    check("fresh download", open(path, "rb").read() == BODY)

    # The case the retry loop exists for: the body stops early, so the next
    # attempt has to resume from what landed rather than start over or give up.
    os.remove(path)
    reset(cut_after=40000)
    try:
        m.download(url, path, attempts=2, pause=nopause)
        short = os.path.getsize(path)
    except RuntimeError:
        short = os.path.getsize(path) if os.path.exists(path) else 0
    check("truncated transfer keeps what arrived", 0 < short < len(BODY),
          "%d bytes" % short)
    reset()
    m.download(url, path, pause=nopause)
    check("resumes to completion", open(path, "rb").read() == BODY)

    # A server that ignores Range replies 200 with the whole body; appending
    # that to a partial file would silently corrupt it.
    with open(path, "r+b") as f:
        f.truncate(30000)
    reset(ignore_range=True)
    m.download(url, path, pause=nopause)
    check("Range ignored -> restarts, not appends", open(path, "rb").read() == BODY)

    # An already-complete file must not be fetched again.
    reset()
    m.download(url, path, pause=nopause)
    check("complete file is not refetched", Handler.seen == 0, "%d GETs" % Handler.seen)

    # The bug this suite was written for: the first failure used to raise
    # FileNotFoundError/UnboundLocalError instead of retrying.
    os.remove(path)
    reset(fail_times=2)
    m.download(url, path, pause=nopause)
    check("retries past early failures", open(path, "rb").read() == BODY)

    os.remove(path)
    reset(fail_times=99)
    try:
        m.download(url, path, attempts=3, pause=nopause)
        check("gives up cleanly", False, "no exception raised")
    except RuntimeError:
        check("gives up cleanly", True)
    except Exception as e:
        check("gives up cleanly", False, "%s: %s" % (type(e).__name__, e))

    # A rejected certificate or a 404 will be rejected identically every time;
    # burning the whole retry budget on one costs ~20 minutes of build for
    # nothing, which is how this classification came to exist.
    import ssl, urllib.error
    cert_err = ssl.SSLCertVerificationError("Missing Subject Key Identifier")
    check("bare cert failure is not retryable", not m.is_retryable(cert_err))
    # This is the shape production actually sees: urlopen wraps a failed
    # handshake in URLError. Asserting only the bare exception let the
    # classifier pass the test while retrying the real thing twenty times.
    check("urlopen-wrapped cert failure is not retryable",
          not m.is_retryable(urllib.error.URLError(cert_err)))
    check("URLError with a string reason is retryable",
          m.is_retryable(urllib.error.URLError("connection reset")))
    check("404 is not retryable", not m.is_retryable(
        urllib.error.HTTPError("u", 404, "Not Found", None, None)))
    check("503 is retryable", m.is_retryable(
        urllib.error.HTTPError("u", 503, "Service Unavailable", None, None)))
    check("429 is retryable", m.is_retryable(
        urllib.error.HTTPError("u", 429, "Too Many Requests", None, None)))
    check("connection error is retryable", m.is_retryable(OSError("reset")))

    # ...and that download() acts on the classification rather than merely
    # computing it: a fatal error must not consume the retry budget.
    calls = []
    original = m.remote_size

    def boom(_url):
        raise urllib.error.URLError(cert_err)

    m.remote_size = boom
    try:
        m.download("https://example.invalid/x", os.path.join(tmp, "never.bin"),
                   attempts=20, pause=lambda n: calls.append(n))
        check("fatal error stops on the first attempt", False, "no exception raised")
    except RuntimeError:
        check("fatal error stops on the first attempt", not calls,
              "%d retries" % len(calls))
    finally:
        m.remote_size = original

    # Checksums: the extracted rasters must match what is recorded, so a
    # changed publication stops the build instead of silently changing the
    # elevations the service returns.
    zpath = os.path.join(tmp, "a.zip")
    with zipfile.ZipFile(zpath, "w") as z:
        z.writestr("d/x.tif", b"raster-bytes")
        z.writestr("d/x.tfw", b"world-file")
    good = {"x.tif": hashlib.sha256(b"raster-bytes").hexdigest(),
            "x.tfw": hashlib.sha256(b"world-file").hexdigest()}
    out = os.path.join(tmp, "out")
    os.makedirs(out, exist_ok=True)
    try:
        m.extract(zpath, out, good)
        check("matching checksums accepted", True)
    except Exception as e:
        check("matching checksums accepted", False, "%s: %s" % (type(e).__name__, e))

    bad = dict(good, **{"x.tif": "0" * 64})
    try:
        m.extract(zpath, out, bad)
        check("mismatch is rejected", False, "no exception raised")
    except m.ChecksumError:
        check("mismatch is rejected", True)

    try:
        m.extract(zpath, out, {"x.tif": good["x.tif"]})
        check("unrecorded file is rejected", False, "no exception raised")
    except m.ChecksumError:
        check("unrecorded file is rejected", True)

    try:
        m.extract(zpath, out, dict(good, **{"missing.tif": "0" * 64}))
        check("absent expected file is rejected", False, "no exception raised")
    except m.ChecksumError:
        check("absent expected file is rejected", True)

    httpd.shutdown()
    print()
    if failures:
        print("FAILED: %s" % ", ".join(failures))
        return 1
    print("PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
