#!/bin/bash
set -euo pipefail
: "${APP_STORE_CONNECT_API_KEY_ID:?Missing APP_STORE_CONNECT_API_KEY_ID}"
: "${APP_STORE_CONNECT_ISSUER_ID:?Missing APP_STORE_CONNECT_ISSUER_ID}"
: "${APP_STORE_CONNECT_API_PRIVATE_KEY_BASE64:?Missing APP_STORE_CONNECT_API_PRIVATE_KEY_BASE64}"
python3 - <<'PY'
import base64, os, re
from pathlib import Path
key_id = os.environ['APP_STORE_CONNECT_API_KEY_ID']
assert re.fullmatch(r'[A-Za-z0-9]{8,20}', key_id), 'Invalid API key ID'
path = Path.home() / '.appstoreconnect/private_keys' / f'AuthKey_{key_id}.p8'
path.parent.mkdir(parents=True, exist_ok=True)
data = base64.b64decode(os.environ['APP_STORE_CONNECT_API_PRIVATE_KEY_BASE64'], validate=True)
assert b'BEGIN PRIVATE KEY' in data, 'Expected a PKCS8 private key'
path.write_bytes(data)
path.chmod(0o600)
(Path(os.environ['RUNNER_TEMP']) / 'ark-api-key-path').write_text(str(path))
PY
shopt -s nullglob
IPAS=(build/Export/*.ipa)
test "${#IPAS[@]}" -eq 1 || { echo 'Expected exactly one exported IPA'; exit 1; }
xcrun altool --upload-app --type ios --file "${IPAS[0]}" \
  --api-key "$APP_STORE_CONNECT_API_KEY_ID" --api-issuer "$APP_STORE_CONNECT_ISSUER_ID"
echo 'Upload command completed. Apple processing and tester availability must be checked in App Store Connect.'
