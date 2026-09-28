#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

tag="${1:-}"
version="$(cat VERSION)"
build="$(cat BUILD_NUMBER)"

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc)\.[0-9]+)?$ ]]; then
    echo "VERSION is not a supported release version: $version" >&2
    exit 1
fi
if [[ "$tag" != "v$version" ]]; then
    echo "Release tag $tag must match VERSION v$version." >&2
    exit 1
fi
if [[ ! "$build" =~ ^[1-9][0-9]*$ ]]; then
    echo "BUILD_NUMBER must be a positive integer." >&2
    exit 1
fi
if [[ "$(git rev-parse "refs/tags/$tag^{commit}")" != "$(git rev-parse HEAD)" ]]; then
    echo "The checked-out commit is not the tagged commit." >&2
    exit 1
fi
if ! git merge-base --is-ancestor HEAD origin/main; then
    echo "The release commit must already be on origin/main." >&2
    exit 1
fi

while IFS= read -r previous_tag; do
    [[ "$previous_tag" == "$tag" ]] && continue
    previous_build="$(git show "$previous_tag:BUILD_NUMBER" 2>/dev/null || true)"
    if [[ ! "$previous_build" =~ ^[1-9][0-9]*$ ]]; then
        echo "Cannot validate BUILD_NUMBER from $previous_tag." >&2
        exit 1
    fi
    # A later release tag may exist when this workflow is retried. Only tags
    # at or before this commit determine whether its build number increased.
    if git merge-base --is-ancestor "refs/tags/$previous_tag^{commit}" HEAD && (( build <= previous_build )); then
        echo "BUILD_NUMBER $build must exceed $previous_tag build $previous_build." >&2
        exit 1
    fi
done < <(git tag --list 'v*')

printf 'Validated %s at build %s (%s).\n' "$tag" "$build" "$(git rev-parse --short HEAD)"
