#!/bin/zsh
# Faz um release do Mural num comando: sobe a versão em Config/Project.xcconfig, cria a tag e envia a main e a tag
# juntas para o GitHub, onde o Xcode Cloud começa a build de release.
#
# Uso:
#   scripts/release.sh 1.1.0              tag v1.1.0
#   scripts/release.sh 1.0.6 --stable     tag v1.0.6-stable
#
# Opções:
#   --stable    a tag termina em -stable (sempre vira build de release)
#   --check     só confere e mostra o resumo (no máximo volta para a main, se o HEAD estiver solto)
#   --no-push   cria o commit e a tag, mas não envia
#   --yes       envia sem perguntar (para o script do Xcode, que não tem terminal)
#   --verify    roda scripts/verify.sh antes (formatação, projeto e testes)
#
# A regra de qual tag vira release é a do Xcode Cloud (ci_scripts/release_rules.sh): o erro aparece aqui, antes de enviar,
# e não depois de a build falhar.
#
# O número da build local (CLOUD_BUILD_NUMBER) sobe um a cada release, no mesmo commit da versão: é o que vale num archive
# feito no Mac. No Xcode Cloud vale o número dele (ci_scripts/ci_pre_xcodebuild.sh), desde que o projeto não fixe
# CURRENT_PROJECT_VERSION; por isso o release recusa um projeto que troque $(CLOUD_BUILD_NUMBER) por um número.
set -euo pipefail

script="${0:A}"
root="${script:h:h}"
cd "$root"
source ci_scripts/release_rules.sh

# Dentro de uma função o zsh troca o $0 pelo nome dela: o caminho do script vem de $script.
usage() {
    sed -n '2,17s/^# \{0,1\}//p' "$script"
}

die() {
    echo "release: $*" >&2
    exit 1
}

version=""
stable=false
check_only=false
push=true
assume_yes=false
verify=false
for argument in "$@"; do
    case "$argument" in
        --stable) stable=true ;;
        --check) check_only=true ;;
        --no-push) push=false ;;
        --yes) assume_yes=true ;;
        --verify) verify=true ;;
        -h | --help)
            usage
            exit 0
            ;;
        -*) die "opção desconhecida: $argument" ;;
        *) version="$argument" ;;
    esac
done

current="$(mural_project_version "$root")"
# Número da build local, lido do mesmo arquivo da versão.
build="$(sed -n 's/^CLOUD_BUILD_NUMBER[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' Config/Project.xcconfig | head -n 1)"
[[ "$build" =~ '^[0-9]+$' ]] || die "CLOUD_BUILD_NUMBER não encontrado ou inválido em Config/Project.xcconfig"
next_build=$(( build + 1 ))
if [[ -z "$version" ]]; then
    usage
    echo
    echo "Versão atual: $current (build local $build)"
    exit 2
fi
[[ "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || die "versão inválida: $version (use X.Y.Z, como 1.1.0)"

tag="v$version"
$stable && tag="$tag-stable"
remote="${RELEASE_REMOTE:-$(git config branch.main.remote || echo origin)}"

# Conferências, antes de mudar qualquer coisa.
git diff --quiet && git diff --cached --quiet || die "há mudanças sem commit em arquivos versionados; faça o commit antes"
branch="$(git symbolic-ref --quiet --short HEAD || true)"
if [[ -z "$branch" ]] && git merge-base --is-ancestor HEAD main; then
    # HEAD solto num commit que já está na main (depois de abrir uma tag, por exemplo): volta para a main, de onde o
    # release sai. Nada se perde: o commit está na main e não há mudanças sem commit.
    echo "O HEAD estava solto em $(git rev-parse --short HEAD); voltando para a main."
    git switch --quiet main
    branch=main
    current="$(mural_project_version "$root")"
fi
[[ "$branch" == main ]] || die "o release sai da main (agora: ${branch:-HEAD solto}); volte com: git switch main"
git rev-parse --quiet --verify "refs/tags/$tag" >/dev/null && die "a tag $tag já existe"
# Um número fixo no projeto passa por cima do xcconfig, aqui e no Xcode Cloud: todas as builds sairiam com ele.
fixed="$(grep -E '"CURRENT_PROJECT_VERSION"' Mural.xcodeproj/project.xcproj | grep -v -F '"$(CLOUD_BUILD_NUMBER)"' || true)"
[[ -z "$fixed" ]] || die "o projeto fixa CURRENT_PROJECT_VERSION; volte para \$(CLOUD_BUILD_NUMBER) com: xcrun xcodeproj setting set CURRENT_PROJECT_VERSION '\$(CLOUD_BUILD_NUMBER)' --target Mural"
mural_release_tag_version "$tag" "$root" >/dev/null || exit 1
git fetch --quiet "$remote" main || die "não deu para ler a main de $remote"
git merge-base --is-ancestor "$remote/main" main || die "a main de $remote tem commits que a local não tem; atualize antes"

pending="$(git rev-list --count "$remote/main..main")"
if $check_only; then
    echo "$tag: versão $current → $version, build local $build → $next_build, $pending commits a enviar para $remote"
    exit 0
fi

$verify && scripts/verify.sh

# Versão, build local e tag: a build sobe a cada release, mesmo que a versão já seja a pedida.
sed -i '' "s/^CLOUD_BUILD_NUMBER[[:space:]]*=.*/CLOUD_BUILD_NUMBER = $next_build/" Config/Project.xcconfig
if [[ "$current" != "$version" ]]; then
    sed -i '' "s/^CLOUD_MARKETING_VERSION[[:space:]]*=.*/CLOUD_MARKETING_VERSION = $version/" Config/Project.xcconfig
    git commit --quiet -m "Sobe a versão para $version e a build local para $next_build" -- Config/Project.xcconfig
else
    git commit --quiet -m "Sobe a build local para $next_build" -- Config/Project.xcconfig
fi
git tag -a "$tag" -m "Mural $version (build $next_build)"

pending="$(git rev-list --count "$remote/main..main")"
echo "Pronto: $tag, com $pending commits na main ainda não enviados para $remote:"
# `-n 20`, e não `| head`: o head fecha a saída antes de o git terminar, e com `pipefail` o script parava aqui, sem enviar.
git log --oneline -n 20 "$remote/main..main"
(( pending > 20 )) && echo "  … e mais $(( pending - 20 ))"

if ! $push; then
    echo "Nada foi enviado. Para enviar: git push --atomic $remote main $tag"
    exit 0
fi
if ! $assume_yes; then
    read -r "answer?Enviar a main e a tag $tag agora? [s/N] "
    if [[ "$answer" != [sS]* ]]; then
        echo "Nada foi enviado. Para enviar depois: git push --atomic $remote main $tag"
        exit 0
    fi
fi

# A main e a tag vão juntas: ou chegam as duas, ou nenhuma.
if ! git push --atomic "$remote" main "$tag"; then
    die "o envio falhou; o commit e a tag continuam aqui. Para tentar de novo: git push --atomic $remote main $tag"
fi
echo "Enviado. O Xcode Cloud começa a build de $tag."
