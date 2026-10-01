"""Fetch the reviewed source and build a fresh, credential-free bootstrap schema.

Does not start services, issue documents, or create accounts.
"""
import pathlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
RUNTIME = ROOT / '.runtime'
REVISION = 'b41a7c79ba3fb2f0977efd3065bc126e1d9651ac'
RUNTIME.mkdir(exist_ok=True)
checkout = RUNTIME / 'openapi'
if not checkout.exists():
    subprocess.run(['git', 'clone', 'https://github.com/AngeloBarzolaVillamar/open-api-facturacion-sri.git', str(checkout)], check=True)
subprocess.run(['git', '-C', str(checkout), 'checkout', '--detach', REVISION], check=True)
assert subprocess.check_output(['git', '-C', str(checkout), 'rev-parse', 'HEAD'], text=True).strip() == REVISION
source = (checkout / 'database/init.sql').read_text()
# Upstream dump contains a default superadministrator. Retain only static catalogs
# and non-secret system configuration, never example tenants/users/certificates.
lines = []
for line in source.splitlines():
    if line.startswith('INSERT INTO ') and not re.match(r'INSERT INTO public\.(catalogo_[a-z_]+|sistema_config)\b', line):
        continue
    if line.startswith('COPY '):
        raise RuntimeError('Unexpected COPY data: review bootstrap before use')
    lines.append(line.replace('OWNER TO postgres', 'OWNER TO sri_app'))
clean = '\n'.join(lines) + '\n'
assert 'superadmin@openapi-sri.com' not in clean
(RUNTIME / 'init.sql').write_text(clean)
# Avoid upstream entrypoint's world-writable certificate directory.
entrypoint = checkout / 'docker-entrypoint.sh'
entrypoint.write_text(entrypoint.read_text().replace('u+rwX,g+rwX,o+rwX', 'u+rwX,g-rwx,o-rwx'))
print('Pinned source and sanitized bootstrap prepared; services are not started.')
