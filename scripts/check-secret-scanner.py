"""Check actual scanner behavior with non-live canaries; never prints token values."""
import json
from pathlib import Path
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
    return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python3 scripts/check-secret-scanner.py <verified-gitleaks-binary>")
    check(Path(sys.argv[1]), Path(__file__).resolve().parent.parent / ".gitleaks.toml")
    print("Scanner accepts public identifiers, detects a private canary and redacts findings.")
