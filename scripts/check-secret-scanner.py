"""Check actual scanner behavior with non-live canaries; never prints token values."""
import json
import hashlib
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def check(binary, configuration):
    suffix = "A8dL0pW4xR9qT2vN6hK1mF7sB5zC3uY0"
    samples = [
        ("public", 'public_key="sb_' + "publishable_" + suffix + '"', False),
        ("private", 'service_key="sb_' + "secret_" + suffix + '"', True),
    ]
    with tempfile.TemporaryDirectory(prefix="coco-scanner-") as scratch:
        for label, value, expected in samples:
            report = Path(scratch) / (label + ".json")
            result = subprocess.run(
                [str(binary), "stdin", "--config", str(configuration), "--redact", "--no-banner", "--report-format", "json", "--report-path", str(report)],
                input=value, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20,
            )
            if result.returncode not in (0, 1) or not report.is_file():
                raise RuntimeError("SCANNER_CANARY_UNAVAILABLE")
            findings = json.loads(report.read_text())
            if bool(findings) is not expected or any(item.get("Secret") != "REDACTED" for item in findings):
                raise RuntimeError("SCANNER_CANARY_FAILED:" + label)
        # This one reviewed encryption literal is synthetic and local to the
        # mocked assistant fixture. Both its exact value AND its path must match.
        # A real-looking key in the same test file must still be detected.
        root = Path(configuration).resolve().parent
        source = (root / 'tests' / 'assistant-server.test.mjs').read_text()
        match = re.search(r"GAMA_AI_ENCRYPTION_KEY:'([^']+)'", source)
        if not match or hashlib.sha256(match.group(1).encode()).hexdigest() != '87766ec92f418ce730bb793eaa8d689d7838d5da2dcc27759a32927009d9946c':
            raise RuntimeError('REVIEWED_ENCRYPTION_FIXTURE_CHANGED')
        fixture = match.group(1)
        file_cases = [
            ('reviewed-fixture', 'tests/assistant-server.test.mjs', 'GAMA_AI_ENCRYPTION_KEY="' + fixture + '"', False),
            ('private-in-fixture-path', 'tests/assistant-server.test.mjs', 'service_key="sb_' + 'secret_' + suffix + '"', True),
            ('other-encryption-in-fixture-path', 'tests/assistant-server.test.mjs', 'GAMA_AI_ENCRYPTION_KEY="' + suffix + '"', True),
            ('same-value-outside-fixture', 'tests/other.test.mjs', 'GAMA_AI_ENCRYPTION_KEY="' + fixture + '"', True),
        ]
        for label, relative, value, expected in file_cases:
            repository = Path(scratch) / label
            target = repository / relative
            target.parent.mkdir(parents=True)
            target.write_text(value)
            for args in [['init', '-q'], ['add', '.'], ['-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'Synthetic scanner fixture']]:
                subprocess.run(['git', *args], cwd=repository, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
            report = Path(scratch) / (label + '.json')
            result = subprocess.run(
                [str(binary), 'git', '--config', str(configuration), '--redact', '--no-banner', '--report-format', 'json', '--report-path', str(report), str(repository)],
                text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20,
            )
            if result.returncode not in (0, 1) or not report.is_file():
                raise RuntimeError('SCANNER_PATH_CANARY_UNAVAILABLE:' + label)
            findings = json.loads(report.read_text())
            if bool(findings) is not expected or any(item.get('Secret') != 'REDACTED' for item in findings):
                raise RuntimeError('SCANNER_PATH_CANARY_FAILED:' + label)
    return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python3 scripts/check-secret-scanner.py <verified-gitleaks-binary>")
    check(Path(sys.argv[1]), Path(__file__).resolve().parent.parent / ".gitleaks.toml")
    print("Scanner accepts public identifiers, detects a private canary and redacts findings.")
