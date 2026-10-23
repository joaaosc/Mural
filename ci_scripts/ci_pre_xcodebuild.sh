#!/bin/zsh

set -euo pipefail

# Builds initiated locally must keep using the version committed in the project.
if [[ "${CI_XCODE_CLOUD:-}" != "TRUE" && "${CI_XCODE_CLOUD:-}" != "true" ]]; then
    exit 0
fi

tag="${CI_TAG:-}"
tag="${tag#refs/tags/}"
repository_root="${CI_PRIMARY_REPOSITORY_PATH:-$PWD}"

build_number="${CI_BUILD_NUMBER:-}"
if [[ ! "$build_number" =~ '^[1-9][0-9]*$' ]]; then
    echo "CI_BUILD_NUMBER is missing or invalid: $build_number" >&2
    exit 1
fi

version="1.0.1"

if [[ -z "$tag" ]]; then
    version_file="$repository_root/Config/CloudVersion.xcconfig"
    cat > "$version_file" <<EOF
// Temporary build configuration; do not commit this file.
CLOUD_MARKETING_VERSION = $version
CLOUD_BUILD_NUMBER = $build_number
EOF
    echo "Using marketing version $version and build $build_number for the Xcode Cloud commit workflow."
    exit 0
fi

if [[ "$tag" =~ '^v?([0-9]+)\.([0-9]+)\.([0-9]+)(-[A-Za-z0-9][A-Za-z0-9.-]*-stable|-stable)?$' ]]; then
    major="${match[1]}"
    minor="${match[2]}"
    patch="${match[3]}"
    stable="${match[4]:-}"
    version="${major}.${minor}.${patch}"
else
    echo "The Xcode Cloud release workflow only accepts vMAJOR.MINOR.PATCH or a tag ending in -stable: $tag" >&2
    exit 1
fi

qualifies=false
if [[ "$stable" == *-stable || "$patch" == "5" ]]; then
    qualifies=true
else
    # Xcode Cloud tag patterns are prefix-based, so the semantic comparison
    # is enforced here after the tag-triggered workflow starts.
    previous_major=""
    previous_minor=""
    while IFS= read -r candidate; do
        [[ "$candidate" == "$tag" ]] && continue
        if [[ "$candidate" =~ '^v?([0-9]+)\.([0-9]+)\.([0-9]+)(-[^+]+)?(\+.+)?$' ]]; then
            candidate_major="${match[1]}"
            candidate_minor="${match[2]}"
            candidate_patch="${match[3]}"
            if (( candidate_major < major || (candidate_major == major && candidate_minor < minor) || (candidate_major == major && candidate_minor == minor && candidate_patch < patch) )); then
                previous_major="$candidate_major"
                previous_minor="$candidate_minor"
                break
            fi
        fi
    done < <(git -C "$repository_root" tag --sort=-v:refname)

    if [[ -z "$previous_major" || "$major" != "$previous_major" || "$minor" != "$previous_minor" ]]; then
        qualifies=true
    fi
fi

if [[ "$qualifies" != true ]]; then
    echo "Tag $tag is not a release build tag: use a major/minor increment, patch 5, or the -stable suffix." >&2
    exit 1
fi

version_file="$repository_root/Config/CloudVersion.xcconfig"

cat > "$version_file" <<EOF
// Temporary build configuration; do not commit this file.
CLOUD_MARKETING_VERSION = $version
CLOUD_BUILD_NUMBER = $build_number
EOF

echo "Using marketing version $version and build $build_number for tag $tag."
