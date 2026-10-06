"""Serve browser fixtures over HTTPS, as on GitHub Pages; no production TLS changes."""
import argparse
import http.server
import pathlib
import ssl
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("--port", type=int, default=4175)
args = parser.parse_args()
with tempfile.TemporaryDirectory(prefix="coco-test-tls-") as directory:
    cert, key = (pathlib.Path(directory) / name for name in ("cert.pem", "key.pem"))
    subprocess.run(
        ["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
         "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost,IP:127.0.0.1",
         "-keyout", str(key), "-out", str(cert)],
        check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(cert, key)
    with http.server.ThreadingHTTPServer(("127.0.0.1", args.port), http.server.SimpleHTTPRequestHandler) as server:
        server.socket = context.wrap_socket(server.socket, server_side=True)
        server.serve_forever()
