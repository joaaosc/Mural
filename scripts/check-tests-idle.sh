#!/bin/sh
# Espera o Mac ficar livre de outros testes antes de começar os nossos: os testes do app abrem uma
# janela do Mural e os de interface tomam a tela e o mouse, então duas rodadas juntas se derrubam.
# Conta como ocupado: xcodebuild rodando testes, executor de testes de interface (*-Runner.app) e
# cópia de teste do Mural (-uiTesting, -manualTesting ou dentro de test-products). Com o argumento
# "ui", qualquer Mural aberto também conta, porque a cópia de teste tem o mesmo identificador.
# Libera depois de 5 s seguidos sem nada disso. Espera até IDLE_WAIT segundos (padrão 20) e, se
# continuar ocupado, lista os processos e sai com erro.
set -eu

MODE=${1:-}
WAIT=${IDLE_WAIT:-20}
QUIET=5

# Este script e quem o chamou podem citar xcodebuild na linha de comando: ficam de fora.
own_pids() {
    pid=$$
    while [ "${pid:-0}" -gt 1 ]; do
        echo "$pid"
        pid=$(ps -o ppid= -p "$pid" | tr -d ' ')
    done
}

busy() {
    skip=" $(own_pids | tr '\n' ' ') "
    ps -axww -o pid=,args= | while read -r pid args; do
        case "$skip" in *" $pid "*) continue ;; esac
        case "$args" in
            *"xcodebuild "*)
                case "$args " in
                    *" test "* | *" test-without-building "* | *" build-for-testing "*) ;;
                    *) continue ;;
                esac
                ;;
            *"-Runner.app/Contents/MacOS/"*) ;;
            *"/Mural.app/Contents/MacOS/Mural"*)
                if [ "$MODE" != ui ]; then
                    case "$args" in
                        *-uiTesting* | *-manualTesting* | */test-products/*) ;;
                        *) continue ;;
                    esac
                fi
                ;;
            *) continue ;;
        esac
        echo "$pid $args" | cut -c 1-200
    done
}

quiet=0
waited=0
announced=0
while :; do
    found=$(busy)
    if [ -z "$found" ]; then
        quiet=$((quiet + 1))
        if [ "$quiet" -ge "$QUIET" ]; then exit 0; fi
    else
        quiet=0
        if [ "$waited" -ge "$WAIT" ]; then
            echo "Outro teste está usando o Mac (ou há um Mural aberto). Espere terminar ou feche e rode de novo:" >&2
            echo "$found" >&2
            exit 1
        fi
        if [ "$announced" = 0 ]; then
            echo "Outro teste em andamento; esperando até ${WAIT} s o Mac ficar livre." >&2
            announced=1
        fi
    fi
    sleep 1
    waited=$((waited + 1))
done
