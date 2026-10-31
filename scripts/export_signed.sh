#!/bin/bash
set -euo pipefail
: "${BUILD_CERTIFICATE_BASE64:?Missing BUILD_CERTIFICATE_BASE64}"
: "${BUILD_PROVISION_PROFILE_BASE64:?Missing BUILD_PROVISION_PROFILE_BASE64}"
: "${P12_PASSWORD:?Missing P12_PASSWORD}"
: "${RUNNER_TEMP:?Requires GitHub runner temporary directory}"
case "${EXPORT_METHOD:-}" in debugging|release-testing|app-store-connect) ;; *) echo 'Invalid export method'; exit 1 ;; esac

CERT="$RUNNER_TEMP/ark-signing.p12"
PROFILE="$RUNNER_TEMP/ark-profile.mobileprovision"
KEYCHAIN="$RUNNER_TEMP/ark-signing.keychain-db"
KEYCHAIN_PASSWORD=$(openssl rand -hex 24)
echo "::add-mask::$KEYCHAIN_PASSWORD"
printf '%s' "$BUILD_CERTIFICATE_BASE64" | base64 --decode > "$CERT"
printf '%s' "$BUILD_PROVISION_PROFILE_BASE64" | base64 --decode > "$PROFILE"
security cms -D -i "$PROFILE" > "$RUNNER_TEMP/ark-profile.plist"

python3 - <<'PY'
import os, plistlib, datetime, fnmatch
from pathlib import Path
root = Path(os.environ['RUNNER_TEMP'])
profile = plistlib.loads((root / 'ark-profile.plist').read_bytes())
bundle = 'local.ark.fieldguide'
team = profile['TeamIdentifier'][0]
assert profile['ExpirationDate'] > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None), 'Provisioning profile expired'
assert fnmatch.fnmatchcase(team + '.' + bundle, profile['Entitlements']['application-identifier']), 'Profile does not cover bundle ID'
method = os.environ['EXPORT_METHOD']
if method == 'debugging':
    assert profile['Entitlements'].get('get-task-allow'), 'Debugging requires a development profile'
elif method == 'release-testing':
    assert profile.get('ProvisionedDevices') and not profile['Entitlements'].get('get-task-allow'), 'Release testing requires an Ad Hoc profile'
else:
    assert not profile.get('ProvisionedDevices') and not profile['Entitlements'].get('get-task-allow'), 'App Store export requires an App Store profile'
export = {'method': method, 'signingStyle': 'manual', 'teamID': team,
          'provisioningProfiles': {bundle: profile['UUID']}}
Path('build/ExportOptions.plist').write_bytes(plistlib.dumps(export))
dest = Path.home() / 'Library/MobileDevice/Provisioning Profiles' / (profile['UUID'] + '.mobileprovision')
dest.parent.mkdir(parents=True, exist_ok=True)
dest.write_bytes((root / 'ark-profile.mobileprovision').read_bytes())
(root / 'ark-installed-profile-path').write_text(str(dest))
with open(os.environ['GITHUB_ENV'], 'a') as out:
    out.write('ARK_TEAM_ID=' + team + '\nARK_PROFILE_UUID=' + profile['UUID'] + '\n')
# Environment values above become available to later steps; this shell reads these two safe identifiers.
(root / 'ark-signing-identifiers').write_text(team + '\n' + profile['UUID'] + '\n')
PY
ARK_TEAM_ID=$(sed -n '1p' "$RUNNER_TEMP/ark-signing-identifiers")
ARK_PROFILE_UUID=$(sed -n '2p' "$RUNNER_TEMP/ark-signing-identifiers")
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$CERT" -P "$P12_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN"
security set-key-partition-list -S apple-tool:,apple:,codesign: -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security list-keychains -d user -s "$KEYCHAIN"
IDENTITY=$(security find-identity -v -p codesigning "$KEYCHAIN" | awk '/"/ {print $2; exit}')
test -n "$IDENTITY"

xcodebuild archive -project ARKFieldGuide.xcodeproj -scheme ARKFieldGuide -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/ARKFieldGuide.xcarchive \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$ARK_TEAM_ID" \
  PROVISIONING_PROFILE_SPECIFIER="$ARK_PROFILE_UUID" CODE_SIGN_IDENTITY="$IDENTITY" \
  CURRENT_PROJECT_VERSION="${ARK_BUILD_NUMBER:-1}"
xcodebuild -exportArchive -archivePath build/ARKFieldGuide.xcarchive \
  -exportPath build/Export -exportOptionsPlist build/ExportOptions.plist
