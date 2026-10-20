#!/bin/sh
# Falha se algum project.xcproj versionado não estiver na forma canônica do
# xcprojformatter (chave desconhecida ou repetida some em silêncio na reescrita).
status=0
for file in $(git ls-files '*.xcodeproj/project.xcproj'); do
  project=$(dirname "$file")
  if ! xcrun xcprojformatter "$project" | diff -q "$file" - >/dev/null; then
    echo "fora da forma canônica: $file (rode: xcrun xcprojformatter --update $project)"
    status=1
  fi
done
exit $status
