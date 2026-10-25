#!/bin/bash
# Verifica o .app de distribuição ou o .pkg exportado pelo Xcode, antes do upload.
# O .app dentro do archive normalmente ainda tem assinatura de desenvolvimento.
set -euo pipefail
if [[ $# != 1 || "$1" == --help ]]; then
    echo 'Uso: scripts/verify-app-store.sh /caminho/Mural.pkg (ou Mural.app exportado)'
    [[ "${1:-}" == --help ]] && exit 0
    exit 2
fi
input="$1"
work="$(mktemp -d "${TMPDIR:-/tmp}/mural-store-check.XXXXXX")"
trap 'rm -rf "$work"' EXIT
if [[ "$input" == *.pkg ]]; then
    pkgutil --check-signature "$input"
    pkgutil --expand-full "$input" "$work/package"
    app="$(find "$work/package" -type d -name Mural.app -print -quit)"
else
    app="$input"
fi
[[ -d "$app/Contents" ]] || { echo 'Mural.app não encontrado.' >&2; exit 1; }
# Imprime os diagnósticos mesmo se a validação falhar (inclusive o DR problemático).
codesign -d --verbose=4 "$app" 2> "$work/signature.txt"
cat "$work/signature.txt"
codesign -d -r- "$app"
if ! codesign --verify --deep --strict --all-architectures --verbose=4 "$app"; then
    echo 'ERRO: a assinatura não passa na verificação estrita.' >&2
    echo 'Se a mensagem for "does not satisfy its designated Requirement", compare acima o nome do certificado' >&2
    echo '(Authority=) com o subject.CN do requisito: nomes com acento podem vir em formas Unicode diferentes.' >&2
    exit 1
fi
codesign -d --entitlements - --xml "$app" > "$work/entitlements.plist"
/usr/bin/python3 - "$app" "$work/entitlements.plist" "$work/signature.txt" <<'PY'
import pathlib, plistlib, sys
app = pathlib.Path(sys.argv[1])
ent = plistlib.loads(pathlib.Path(sys.argv[2]).read_bytes())
signature = pathlib.Path(sys.argv[3]).read_text()
errors = []
for key in ('com.apple.security.app-sandbox', 'com.apple.security.network.client',
            'com.apple.security.files.user-selected.read-write',
            'com.apple.security.personal-information.calendars'):
    if ent.get(key) is not True:
        errors.append(f'Permissão necessária ausente: {key}')
for key, value in ent.items():
    if value and (key.startswith('com.apple.security.temporary-exception.') or
                  key.startswith('com.apple.security.cs.') or
                  key in ('com.apple.security.get-task-allow', 'get-task-allow',
                          'com.apple.security.automation.apple-events',
                          'com.apple.security.network.server')):
        errors.append(f'Permissão inesperada em distribuição: {key}')
# O arquivo de entitlements do projeto diz "development"; a exportação para a loja troca para "production".
if ent.get('com.apple.developer.aps-environment') != 'production':
    errors.append('com.apple.developer.aps-environment deveria ser "production" na distribuição.')
if ent.get('com.apple.developer.icloud-container-environment') == 'Development':
    errors.append('O iCloud está no ambiente Development; a distribuição usa Production.')
if 'Authority=Apple Distribution:' not in signature and 'Authority=3rd Party Mac Developer Application:' not in signature:
    errors.append('Exige assinatura Mac App Store de distribuição; desenvolvimento/Developer ID/ad hoc não servem.')
if 'TeamIdentifier=33FPG9442W' not in signature:
    errors.append('TeamIdentifier diferente do projeto.')
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
if info.get('CFBundleIdentifier') != 'com.joaocosta.Mural':
    errors.append('Bundle ID diferente do projeto.')
for key in ('NSRemindersFullAccessUsageDescription', 'NSAppleMusicUsageDescription'):
    if not info.get(key):
        errors.append(f'Descrição de uso ausente: {key}')
manifest = app / 'Contents/Resources/PrivacyInfo.xcprivacy'
if not manifest.exists():
    errors.append('PrivacyInfo.xcprivacy não foi incluído no produto.')
else:
    privacy = plistlib.loads(manifest.read_bytes())
    reasons = {item['NSPrivacyAccessedAPIType']: item['NSPrivacyAccessedAPITypeReasons']
               for item in privacy.get('NSPrivacyAccessedAPITypes', [])}
    for category, reason in [('UserDefaults', 'CA92.1'), ('FileTimestamp', 'C617.1'), ('DiskSpace', 'E174.1')]:
        if reason not in reasons.get('NSPrivacyAccessedAPICategory' + category, []):
            errors.append(f'Manifesto sem {category}: {reason}')
for error in errors:
    print('ERRO:', error, file=sys.stderr)
if errors:
    sys.exit(1)
print(f'OK: assinatura, sandbox e verificações locais de distribuição — versão {info.get("CFBundleShortVersionString")}, build {info.get("CFBundleVersion")}.')
print('A aprovação ainda depende da App Review, metadados e testes funcionais.')
PY
