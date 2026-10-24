# Regras de versão do Mural, num lugar só: o Xcode Cloud (ci_pre_xcodebuild.sh) e o release local (scripts/release.sh)
# usam estas funções, para as duas pontas nunca discordarem sobre qual tag vira build de release.
#
# Arquivo para `source` em zsh; não é um dos scripts que o Xcode Cloud roda sozinho (esses têm nome fixo).
#
# Uma tag vira build de release quando tem o formato vX.Y.Z (o "v" é opcional) e ainda:
#   - termina em -stable (v1.0.5-stable, v1.0.2-beta-stable); ou
#   - tem o patch 5 (v1.0.5); ou
#   - sobe o major ou o minor em relação à maior tag anterior (v1.1.0 depois de v1.0.x).
# Fora disso (v1.0.2 depois de v1.0.1, por exemplo), a build de release é recusada.

# A versão de `Config/Project.xcconfig` (CLOUD_MARKETING_VERSION), que vale para as builds sem tag.
# Uso: mural_project_version <raiz do repositório>
mural_project_version() {
    local config="$1/Config/Project.xcconfig"
    local version
    version="$(sed -n 's/^CLOUD_MARKETING_VERSION[[:space:]]*=[[:space:]]*\([0-9][0-9.]*\).*/\1/p' "$config" | head -n 1)"
    if [[ ! "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
        echo "CLOUD_MARKETING_VERSION não encontrada ou inválida em $config" >&2
        return 1
    fi
    print -r -- "$version"
}

# Imprime a versão X.Y.Z da tag se ela vira build de release; senão explica o motivo em stderr e devolve 1.
# Uso: mural_release_tag_version <tag> <raiz do repositório>
mural_release_tag_version() {
    local tag="${1#refs/tags/}"
    local root="$2"
    local major minor patch stable
    if [[ "$tag" =~ '^v?([0-9]+)\.([0-9]+)\.([0-9]+)(-[A-Za-z0-9][A-Za-z0-9.-]*-stable|-stable)?$' ]]; then
        major="${match[1]}"
        minor="${match[2]}"
        patch="${match[3]}"
        stable="${match[4]:-}"
    else
        echo "A tag $tag não serve para release: use vX.Y.Z ou uma tag terminada em -stable." >&2
        return 1
    fi
    local version="${major}.${minor}.${patch}"

    if [[ "$stable" == *-stable || "$patch" == "5" ]]; then
        print -r -- "$version"
        return 0
    fi

    # Os padrões de tag do Xcode Cloud são por prefixo, então a comparação de versões é feita aqui: vale a maior tag
    # anterior a esta.
    local candidate previous_major="" previous_minor=""
    while IFS= read -r candidate; do
        [[ "$candidate" == "$tag" ]] && continue
        if [[ "$candidate" =~ '^v?([0-9]+)\.([0-9]+)\.([0-9]+)(-[^+]+)?(\+.+)?$' ]]; then
            if (( match[1] < major || (match[1] == major && match[2] < minor) \
                || (match[1] == major && match[2] == minor && match[3] < patch) )); then
                previous_major="${match[1]}"
                previous_minor="${match[2]}"
                break
            fi
        fi
    done < <(git -C "$root" tag --sort=-v:refname)

    if [[ -z "$previous_major" || "$major" != "$previous_major" || "$minor" != "$previous_minor" ]]; then
        print -r -- "$version"
        return 0
    fi
    echo "A tag $tag não vira release: suba o major ou o minor, use o patch 5 ou termine a tag em -stable." >&2
    return 1
}
