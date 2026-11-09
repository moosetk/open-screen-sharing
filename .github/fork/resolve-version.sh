#!/usr/bin/env bash
# Resolves the marketing version and build number for the upstream source that
# is actually contained in HEAD.
#
# Marketing version (CFBundleShortVersionString) is the `version` field of the
# newest upstream GitHub release whose vX.Y.Z tag is an ancestor of that
# commit. It is never incremented. Upstream's nightly metadata.json labels the
# current tip with the next marketing version (latest release + 1) before that
# version is tagged; that value is reported and not used.
#
# Build number (CFBundleVersion) is the positive integer upstream published for
# the newest build contained in the tree:
#   - a release contributes the `build` field of its metadata.json
#   - the upstream `nightly` tag contributes its annotation, which is the build
#     number of that nightly, only when that commit is contained in the tree
#     and the annotation is greater than or equal to the release build
# The fork's own tags are ignored. The next build number is not invented.
#
# Env:
#   UPSTREAM_URL            default https://github.com/nekohasekai/open-screen-sharing.git
#   UPSTREAM_REF            default main
#   UPSTREAM_SHA            integrated commit; default is the merge-base of HEAD and upstream
#   METADATA_DIR            read <tag>.json from this directory instead of GitHub
#   RELEASE_DOWNLOAD_BASE   default the upstream releases/download URL
#   VERSION_ENV             write shell assignments here
#   VERSION_JSON            write package metadata here
#
# Prints KEY=VALUE. Also appends to $GITHUB_OUTPUT and $GITHUB_STEP_SUMMARY when set.

set -euo pipefail

UPSTREAM_URL=${UPSTREAM_URL:-https://github.com/nekohasekai/open-screen-sharing.git}
UPSTREAM_REF=${UPSTREAM_REF:-main}
RELEASE_DOWNLOAD_BASE=${RELEASE_DOWNLOAD_BASE:-https://github.com/nekohasekai/open-screen-sharing/releases/download}

export GIT_TERMINAL_PROMPT=0

cd "$(git rev-parse --show-toplevel)"

die() {
  echo "resolve-version: $*" >&2
  exit 1
}

is_dotted_version() {
  case $1 in
    *[!0-9.]* | .* | *. | *..* | "") return 1 ;;
  esac
}

# Prints 1, 0, or -1. Components are decimal, so leading zeros are not octal.
version_cmp() {
  local left=$1 right=$2
  local IFS=.
  local -a left_parts right_parts
  local i count x y
  read -r -a left_parts <<< "$left"
  read -r -a right_parts <<< "$right"
  count=${#left_parts[@]}
  if [ "${#right_parts[@]}" -gt "$count" ]; then
    count=${#right_parts[@]}
  fi
  i=0
  while [ "$i" -lt "$count" ]; do
    if [ "$i" -lt "${#left_parts[@]}" ]; then
      x=${left_parts[$i]}
    else
      x=0
    fi
    if [ "$i" -lt "${#right_parts[@]}" ]; then
      y=${right_parts[$i]}
    else
      y=0
    fi
    if [ "$((10#$x))" -gt "$((10#$y))" ]; then
      printf '%s\n' 1
      return 0
    fi
    if [ "$((10#$x))" -lt "$((10#$y))" ]; then
      printf '%s\n' -1
      return 0
    fi
    i=$((i + 1))
  done
  printf '%s\n' 0
}

clear_upstream_refs() {
  local refs ref
  refs=$(git for-each-ref --format='%(refname)' refs/fork-upstream || true)
  if [ -z "$refs" ]; then
    return 0
  fi
  printf '%s\n' "$refs" | while read -r ref; do
    if [ -n "$ref" ]; then
      git update-ref -d "$ref"
    fi
  done
}

fetch_metadata() {
  local tag=$1 dest=$2
  if [ -n "${METADATA_DIR:-}" ]; then
    if [ ! -f "$METADATA_DIR/$tag.json" ]; then
      die "missing metadata fixture $METADATA_DIR/$tag.json"
    fi
    cp "$METADATA_DIR/$tag.json" "$dest"
    return 0
  fi
  curl -fsSL --retry 3 --retry-delay 2 \
    "$RELEASE_DOWNLOAD_BASE/$tag/metadata.json" -o "$dest"
}

# Prints "<version>\n<build>".
read_metadata() {
  python3 - "$1" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)
version = data.get("version")
build = data.get("build")
if not isinstance(version, str) or not version:
    sys.exit("metadata version must be a non-empty string")
if isinstance(build, bool) or not isinstance(build, int) or build < 1:
    sys.exit("metadata build must be a positive integer")
sys.stdout.write(version + "\n" + str(build) + "\n")
PY
}

clear_upstream_refs
git fetch --quiet --no-tags "$UPSTREAM_URL" \
  "+refs/heads/${UPSTREAM_REF}:refs/fork-upstream/head" \
  "+refs/tags/v*:refs/fork-upstream/tags/v*"

nightly_fetch_err=$(mktemp)
if ! git fetch --quiet --no-tags "$UPSTREAM_URL" \
  "+refs/tags/nightly:refs/fork-upstream/nightly" 2>"$nightly_fetch_err"; then
  if grep -q "couldn't find remote ref" "$nightly_fetch_err"; then
    echo "resolve-version: upstream has no nightly tag; using the release build number" >&2
  else
    cat "$nightly_fetch_err" >&2
    rm -f "$nightly_fetch_err"
    exit 1
  fi
fi
rm -f "$nightly_fetch_err"

if [ -z "$(git for-each-ref --format='%(refname)' refs/fork-upstream/tags)" ]; then
  die "upstream has no v* release tags"
fi

upstream_head=$(git rev-parse refs/fork-upstream/head^{commit})
if [ -n "${UPSTREAM_SHA:-}" ]; then
  upstream_sha=$(git rev-parse --verify "${UPSTREAM_SHA}^{commit}")
else
  upstream_sha=$(git merge-base HEAD "$upstream_head")
fi

if ! git merge-base --is-ancestor "$upstream_sha" "$upstream_head"; then
  die "$upstream_sha is not an upstream commit of $UPSTREAM_URL $UPSTREAM_REF"
fi
if ! git merge-base --is-ancestor "$upstream_sha" HEAD; then
  die "$upstream_sha is not contained in HEAD $(git rev-parse HEAD)"
fi

best_ver=""
best_tag=""
best_sha=""
while read -r ref; do
  [ -n "$ref" ] || continue
  tag=${ref##*/}
  ver=${tag#v}
  if ! is_dotted_version "$ver"; then
    continue
  fi
  sha=$(git rev-parse "${ref}^{commit}")
  if git merge-base --is-ancestor "$sha" "$upstream_sha"; then
    if [ -z "$best_ver" ] || [ "$(version_cmp "$ver" "$best_ver")" -gt 0 ]; then
      best_ver=$ver
      best_tag=$tag
      best_sha=$sha
    fi
  fi
done < <(git for-each-ref --format='%(refname)' 'refs/fork-upstream/tags/v*')

if [ -z "$best_tag" ]; then
  die "no upstream release tag is contained in $upstream_sha"
fi

meta_file=$(mktemp)
fetch_metadata "$best_tag" "$meta_file"
if ! meta=$(read_metadata "$meta_file"); then
  rm -f "$meta_file"
  die "unreadable metadata for $best_tag"
fi
rm -f "$meta_file"
{
  read -r release_version
  read -r release_build
} <<< "$meta"
if [ "$release_version" != "$best_ver" ]; then
  die "release $best_tag metadata version $release_version does not match tag"
fi
if ! is_dotted_version "$release_version"; then
  die "release $best_tag metadata version $release_version is not a numeric version"
fi

marketing_version=$release_version
marketing_version_source="upstream release ${best_tag} metadata.json at ${best_sha}"
build_number=$release_build
build_number_source="upstream release ${best_tag} metadata.json build ${release_build} at ${best_sha}"
nightly_sha=""
nightly_build=""
ignored_nightly_marketing_version=""

if git rev-parse --verify --quiet refs/fork-upstream/nightly >/dev/null; then
  nightly_commit=$(git rev-parse refs/fork-upstream/nightly^{commit})
  if git merge-base --is-ancestor "$nightly_commit" "$upstream_sha"; then
    object_type=$(git for-each-ref --format='%(objecttype)' refs/fork-upstream/nightly)
    if [ "$object_type" != tag ]; then
      die "upstream nightly tag is not annotated; the build number lives in the tag message"
    fi
    annotation=$(git for-each-ref --format='%(contents:subject)' refs/fork-upstream/nightly)
    case $annotation in
      "" | *[!0-9]* | 0 | 0*) die "nightly tag annotation is not a positive integer: $annotation" ;;
    esac
    meta_file=$(mktemp)
    fetch_metadata nightly "$meta_file"
    if ! meta=$(read_metadata "$meta_file"); then
      rm -f "$meta_file"
      die "unreadable nightly metadata"
    fi
    rm -f "$meta_file"
    {
      read -r nightly_meta_version
      read -r nightly_meta_build
    } <<< "$meta"
    if [ "$nightly_meta_build" != "$annotation" ]; then
      die "nightly metadata build $nightly_meta_build does not match tag annotation $annotation"
    fi
    if ! is_dotted_version "$nightly_meta_version"; then
      die "nightly metadata version $nightly_meta_version is not a numeric version"
    fi
    if [ "$((10#$annotation))" -lt "$((10#$release_build))" ]; then
      die "nightly build $annotation is older than release build $release_build"
    fi
    cmp=$(version_cmp "$nightly_meta_version" "$marketing_version")
    if [ "$cmp" -gt 0 ]; then
      ignored_nightly_marketing_version=$nightly_meta_version
    elif [ "$cmp" -lt 0 ]; then
      die "nightly metadata version $nightly_meta_version is older than the released version $marketing_version"
    fi
    nightly_sha=$nightly_commit
    nightly_build=$annotation
    if [ "$((10#$annotation))" -gt "$((10#$release_build))" ]; then
      build_number=$annotation
      build_number_source="upstream nightly tag annotation ${annotation} at ${nightly_commit}"
    fi
  fi
fi

if [ -n "${VERSION_ENV:-}" ]; then
  mkdir -p "$(dirname "$VERSION_ENV")"
  : > "$VERSION_ENV"
fi

emit() {
  printf '%s=%s\n' "$1" "$2"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"
  fi
  if [ -n "${VERSION_ENV:-}" ]; then
    printf '%s=%q\n' "$1" "$2" >> "$VERSION_ENV"
  fi
}

emit marketing_version "$marketing_version"
emit build_number "$build_number"
emit upstream_sha "$upstream_sha"
emit release_tag "$best_tag"
emit release_sha "$best_sha"
emit marketing_version_source "$marketing_version_source"
emit build_number_source "$build_number_source"
emit ignored_nightly_marketing_version "$ignored_nightly_marketing_version"
emit nightly_sha "$nightly_sha"
emit nightly_build "$nightly_build"

if [ -n "${VERSION_JSON:-}" ]; then
  mkdir -p "$(dirname "$VERSION_JSON")"
  MARKETING_VERSION="$marketing_version" \
    BUILD_NUMBER="$build_number" \
    UPSTREAM_SHA="$upstream_sha" \
    RELEASE_TAG="$best_tag" \
    RELEASE_SHA="$best_sha" \
    MARKETING_VERSION_SOURCE="$marketing_version_source" \
    BUILD_NUMBER_SOURCE="$build_number_source" \
    IGNORED_NIGHTLY_MARKETING_VERSION="$ignored_nightly_marketing_version" \
    NIGHTLY_SHA="$nightly_sha" \
    python3 - "$VERSION_JSON" <<'PY'
import json
import os
import sys

build = os.environ["BUILD_NUMBER"]
if not build.isdigit() or build.startswith("0"):
    sys.exit("build number is not a positive integer")
data = {
    "version": os.environ["MARKETING_VERSION"],
    "build": int(build),
    "display": os.environ["MARKETING_VERSION"] + " (" + build + ")",
    "upstream_commit": os.environ["UPSTREAM_SHA"],
    "release_tag": os.environ["RELEASE_TAG"],
    "release_commit": os.environ["RELEASE_SHA"],
    "marketing_version_source": os.environ["MARKETING_VERSION_SOURCE"],
    "build_number_source": os.environ["BUILD_NUMBER_SOURCE"],
    "ignored_nightly_marketing_version": os.environ["IGNORED_NIGHTLY_MARKETING_VERSION"],
    "nightly_commit": os.environ["NIGHTLY_SHA"],
}
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PY
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### Upstream version"
    echo ""
    echo "| | |"
    echo "|---|---|"
    echo "| display | ${marketing_version} (${build_number}) |"
    echo "| marketing version | ${marketing_version} |"
    echo "| build number | ${build_number} |"
    echo "| upstream commit | \`${upstream_sha}\` |"
    echo "| release | \`${best_tag}\` \`${best_sha}\` |"
    echo "| marketing version source | ${marketing_version_source} |"
    echo "| build number source | ${build_number_source} |"
    echo "| ignored nightly marketing version | ${ignored_nightly_marketing_version:-none} |"
  } >> "$GITHUB_STEP_SUMMARY"
fi

echo "resolve-version: ${marketing_version} (${build_number}) for ${upstream_sha}" >&2
