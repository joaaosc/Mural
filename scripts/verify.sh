#!/bin/sh
# Verificação completa antes de um commit: formatação, arquivo de projeto,
# testes do domínio, build e testes do app. UI=1 inclui os testes de interface.
# Os testes do app e os de interface só começam com o Mac livre de outros testes.
set -eu
cd "$(dirname "$0")/.."

SOURCES="Mural MuralTests MuralUITests Packages/MuralKit/Sources Packages/MuralKit/Tests"
XCODEBUILD="xcodebuild -project Mural.xcodeproj -scheme Mural -destination platform=macOS -quiet"

echo "1/5 formatação"
# shellcheck disable=SC2086
swift format lint --strict -r $SOURCES

echo "2/5 arquivo de projeto"
scripts/check-xcproj.sh

echo "3/5 domínio (MuralKit)"
swift test --package-path Packages/MuralKit

echo "4/5 build e testes do app"
scripts/check-tests-idle.sh
$XCODEBUILD -only-testing:MuralTests test

if [ "${UI:-0}" = "1" ]; then
    echo "5/5 testes de interface"
    scripts/ui-tests.sh
else
    echo "5/5 testes de interface: pulados (rode com UI=1)"
fi
echo "ok"
