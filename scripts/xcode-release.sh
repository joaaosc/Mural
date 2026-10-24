#!/bin/zsh
# Release pelo Xcode, para um comportamento: Xcode › Ajustes › Comportamentos › + › "Executar" › este arquivo, e um atalho
# de teclado se quiser.
#
# O comportamento não tem terminal, então tudo é por janelas do macOS: pergunta a versão (com a próxima já sugerida),
# confere a regra do Xcode Cloud, mostra quantos commits vão subir e pede a confirmação antes de enviar. O trabalho de
# verdade é do scripts/release.sh; o que ele escreveu fica em $TMPDIR/mural-release.log.
#
# Os textos das janelas vão para o AppleScript como argumentos, e não dentro do código dele: assim os acentos chegam
# certos, seja qual for a codificação que o osascript supõe para o código.
set -uo pipefail

# O Xcode roda o comportamento com o PATH mínimo do sistema; o git pode precisar do gh ou de outro ajudante de senha.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

root="${0:A:h:h}"
cd "$root" || exit 1
source ci_scripts/release_rules.sh

log="${TMPDIR:-/tmp}/mural-release.log"

# Uma janela de aviso: título e mensagem.
alert() {
    osascript - "$1" "$2" >/dev/null <<'APPLESCRIPT'
on run argv
    activate
    display alert (item 1 of argv) message (item 2 of argv) as critical
end run
APPLESCRIPT
}

# Uma notificação do sistema com o texto dado.
notify() {
    osascript - "$1" >/dev/null <<'APPLESCRIPT'
on run argv
    display notification (item 1 of argv) with title "Mural"
end run
APPLESCRIPT
}

current="$(mural_project_version "$root")" || {
    alert "O release não começou" "Não deu para ler a versão em Config/Project.xcconfig."
    exit 1
}
# A sugestão é o patch seguinte; a pessoa troca na própria janela.
parts=("${(@s:.:)current}")
suggested="${parts[1]}.${parts[2]}.$(( parts[3] + 1 ))"

# 1. A versão e o tipo de release. Cancelar sai sem fazer nada.
choice="$(osascript - "Versão do release (agora: $current)" "$suggested" "Cancelar" "Release" "Release estável" <<'APPLESCRIPT'
on run argv
    activate
    set reply to display dialog (item 1 of argv) default answer (item 2 of argv) buttons {item 3 of argv, item 4 of argv, item 5 of argv} default button (item 5 of argv) cancel button (item 3 of argv) with title "Mural"
    return (button returned of reply) & tab & (text returned of reply)
end run
APPLESCRIPT
)" || exit 0
button="${choice%%$'\t'*}"
version="${${choice#*$'\t'}// /}"
flags=()
[[ "$button" == "Release estável" ]] && flags+=(--stable)

# 2. Confere tudo sem mudar nada e mostra o que vai acontecer.
if ! summary="$(scripts/release.sh "$version" "${flags[@]}" --check 2>&1)"; then
    alert "O release não começou" "$summary"
    exit 1
fi
question="Enviar para o GitHub?

$summary

O Xcode Cloud começa a build de release quando a tag chegar."
osascript - "$question" "Cancelar" "Enviar" >/dev/null <<'APPLESCRIPT' || exit 0
on run argv
    activate
    display dialog (item 1 of argv) buttons {item 2 of argv, item 3 of argv} default button (item 3 of argv) cancel button (item 2 of argv) with title "Mural"
end run
APPLESCRIPT

# 3. O release, sem perguntas: a confirmação já foi feita acima.
if scripts/release.sh "$version" "${flags[@]}" --yes >"$log" 2>&1; then
    notify "$(tail -n 1 "$log")"
else
    alert "O release falhou" "$(tail -n 12 "$log")"
    exit 1
fi
