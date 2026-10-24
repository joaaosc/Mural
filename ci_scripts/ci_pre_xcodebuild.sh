#!/bin/zsh

set -euo pipefail

# Builds initiated locally must keep using the version committed in the project.
if [[ "${CI_XCODE_CLOUD:-}" != "TRUE" && "${CI_XCODE_CLOUD:-}" != "true" ]]; then
    exit 0
fi

# The version rules live in one file, shared with the local release script (scripts/release.sh).
source "${0:A:h}/release_rules.sh"

tag="${CI_TAG:-}"
tag="${tag#refs/tags/}"
repository_root="${CI_PRIMARY_REPOSITORY_PATH:-$PWD}"

build_number="${CI_BUILD_NUMBER:-}"
if [[ ! "$build_number" =~ '^[1-9][0-9]*$' ]]; then
    echo "CI_BUILD_NUMBER is missing or invalid: $build_number" >&2
    exit 1
fi

if [[ -z "$tag" ]]; then
    # Commit workflow: the version committed in Config/Project.xcconfig.
    version="$(mural_project_version "$repository_root")"
else
    # Release workflow: the version comes from the tag, which must qualify as a release (see release_rules.sh).
    version="$(mural_release_tag_version "$tag" "$repository_root")"
fi

version_file="$repository_root/Config/CloudVersion.xcconfig"

cat > "$version_file" <<EOF
// Temporary build configuration; do not commit this file.
CLOUD_MARKETING_VERSION = $version
CLOUD_BUILD_NUMBER = $build_number
EOF

echo "Using marketing version $version and build $build_number${tag:+ for tag $tag}."
