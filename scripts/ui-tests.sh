#!/bin/sh
# Testes de interface: tomam a tela e o mouse por alguns minutos.
# Só começam com o Mac livre de outros testes e sem nenhum Mural aberto (scripts/check-tests-idle.sh).
# Uso: scripts/ui-tests.sh [MuralUITests/MuralUITests/testNome]   (sem argumento: todos)
set -eu
cd "$(dirname "$0")/.."

scripts/check-tests-idle.sh ui
xcodebuild -project Mural.xcodeproj -scheme Mural -destination platform=macOS -quiet \
    "-only-testing:${1:-MuralUITests}" test
