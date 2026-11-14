#!/usr/bin/env bash
# Regression checks for resolve-version.sh.
# Hermetic cases use a local upstream. Live cases use nekohasekai/open-screen-sharing
# release metadata and tags. Set SKIP_LIVE_UPSTREAM=1 to skip the network cases.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
RESOLVE=$ROOT/.github/fork/resolve-version.sh
WORKFLOW=$ROOT/.github/workflows/fork-build-macos.yml
LIVE_UPSTREAM=https://github.com/nekohasekai/open-screen-sharing.git

RELEASE_106=199d9d1b7ed17cb03a1459931e6ea21db0b7c65d
RELEASE_104=ace2b093f8202a251a469a00ea03ae50675499e5
RELEASE_101=78ff8dee7cf37cd45ad70abaa366d29011a9241b
UNRELEASED=5a85706eb4abafb4cf1d341aae626f636a28c5b3
AFTER_104=0d5e712148169d968fae245a62435e4255c6ef41

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_eq() {
  local name=$1 expected=$2 actual=$3
  if [ "$expected" != "$actual" ]; then
    fail "$name: expected [$expected] got [$actual]"
  fi
  echo "ok $name"
}

# The unsigned build has to inject both values. The committed Xcode settings
# are upstream placeholders and are not what the app displays.
grep -q 'resolve-version.sh' "$WORKFLOW" || fail "build workflow does not resolve the version"
grep -q 'MARKETING_VERSION=' "$WORKFLOW" || fail "build workflow does not pass MARKETING_VERSION"
grep -q 'CURRENT_PROJECT_VERSION=' "$WORKFLOW" || fail "build workflow does not pass CURRENT_PROJECT_VERSION"
grep -q 'CFBundleShortVersionString' "$WORKFLOW" || fail "build workflow does not check CFBundleShortVersionString"
grep -q 'CFBundleVersion' "$WORKFLOW" || fail "build workflow does not check CFBundleVersion"
grep -q 'var wantsVirtualDisplay' "$ROOT/OpenScreenSharing/Session/SessionController.swift" || fail "Hardware Display patch is missing"
grep -q 'Hardware Display' "$ROOT/OpenScreenSharing/SessionUI/SessionMenus.swift" || fail "Hardware Display menu string is missing"
echo "ok workflow injects marketing version and build number"

bare=$tmp/upstream.git
work=$tmp/work
meta=$tmp/meta
git init -q --bare "$bare"
git init -q -b main "$work"
git -C "$work" config user.email "version-test@example.com"
git -C "$work" config user.name "version-test"
git -C "$work" config commit.gpgsign false

commit() {
  printf '%s\n' "$1" >> "$work/file"
  git -C "$work" add file
  git -C "$work" commit -q -m "$1"
  git -C "$work" rev-parse HEAD
}

c0=$(commit base)
c4=$(commit release-104)
c4b=$(commit between)
c6=$(commit release-106)
cn=$(commit nightly-tip)
git -C "$work" tag v1.0.4 "$c4"
git -C "$work" tag v1.0.6 "$c6"
git -C "$work" tag -a nightly -m '59' "$cn"
git -C "$work" push -q "$bare" main
git -C "$work" push -q "$bare" v1.0.4 v1.0.6 nightly
# Decoys that exist only in the checkout. The resolver must use the upstream
# remote, not these, and not a fork's own nightly tag.
git -C "$work" tag -a -f nightly -m '1' "$c0" >/dev/null
git -C "$work" tag v9.9.9 "$cn"

mkdir -p "$meta"
printf '%s\n' '{"version":"1.0.4","build":51}' > "$meta/v1.0.4.json"
printf '%s\n' '{"version":"1.0.6","build":58}' > "$meta/v1.0.6.json"
printf '%s\n' '{"version":"1.0.7","build":59}' > "$meta/nightly.json"

envfile=$tmp/out.env
json=$tmp/version.json

resolve() {
  local rev=$1
  rm -f "$envfile" "$json"
  git -C "$work" checkout -q --detach "$rev"
  (
    cd "$work"
    env -u GITHUB_OUTPUT -u GITHUB_STEP_SUMMARY \
      UPSTREAM_URL="$bare" \
      METADATA_DIR="$meta" \
      VERSION_ENV="$envfile" \
      VERSION_JSON="$json" \
      UPSTREAM_SHA="${UPSTREAM_SHA_OVERRIDE:-}" \
      "$RESOLVE"
  ) >"$tmp/stdout"
  # shellcheck disable=SC1090
  . "$envfile"
}

UPSTREAM_SHA_OVERRIDE=
resolve "$cn"
assert_eq "unreleased tip marketing version" "1.0.6" "$marketing_version"
assert_eq "unreleased tip build" "59" "$build_number"
assert_eq "unreleased tip does not become 1.0.7" "1.0.7" "$ignored_nightly_marketing_version"
assert_eq "unreleased tip upstream" "$cn" "$upstream_sha"
assert_eq "unreleased tip release tag" "v1.0.6" "$release_tag"
assert_eq "unreleased tip release commit" "$c6" "$release_sha"
assert_eq "unreleased tip nightly commit" "$cn" "$nightly_sha"
case $build_number_source in
  "upstream nightly tag annotation 59 at $cn") ;;
  *) fail "build source [$build_number_source]" ;;
esac
case $marketing_version_source in
  "upstream release v1.0.6 metadata.json at $c6") ;;
  *) fail "marketing source [$marketing_version_source]" ;;
esac
grep -q '^marketing_version=1.0.6$' "$tmp/stdout" || fail "stdout missing marketing version"
python3 - "$json" "$cn" "$c6" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["version"] == "1.0.6", data
assert data["build"] == 59, data
assert data["display"] == "1.0.6 (59)", data
assert data["ignored_nightly_marketing_version"] == "1.0.7", data
assert data["upstream_commit"] == sys.argv[2], data
assert data["release_tag"] == "v1.0.6", data
assert data["release_commit"] == sys.argv[3], data
assert isinstance(data["build"], int)
PY
echo "ok unreleased tip keeps the released marketing version and the nightly build"

resolve "$c6"
assert_eq "release commit marketing version" "1.0.6" "$marketing_version"
assert_eq "release commit build" "58" "$build_number"
assert_eq "release commit ignores nothing" "" "$ignored_nightly_marketing_version"
assert_eq "release commit has no nightly build" "" "$nightly_build"
case $build_number_source in
  "upstream release v1.0.6 metadata.json build 58 at $c6") ;;
  *) fail "release build source [$build_number_source]" ;;
esac
echo "ok exact release uses that release's metadata"

resolve "$c4b"
assert_eq "commit after 1.0.4 marketing version" "1.0.4" "$marketing_version"
assert_eq "commit after 1.0.4 build" "51" "$build_number"
assert_eq "commit after 1.0.4 is not labeled 1.0.6" "v1.0.4" "$release_tag"
echo "ok a later release tag that is not an ancestor is not used"

resolve "$c4"
assert_eq "1.0.4 commit marketing version" "1.0.4" "$marketing_version"
assert_eq "1.0.4 commit build" "51" "$build_number"

expect_reject() {
  local name=$1 rev=$2 pattern=$3
  git -C "$work" checkout -q --detach "$rev"
  if (
    cd "$work"
    env -u GITHUB_OUTPUT -u GITHUB_STEP_SUMMARY \
      UPSTREAM_URL="$bare" \
      METADATA_DIR="${META_OVERRIDE:-$meta}" \
      VERSION_ENV="$envfile" \
      UPSTREAM_SHA="${UPSTREAM_SHA_OVERRIDE:-}" \
      "$RESOLVE"
  ) >"$tmp/stdout" 2>"$tmp/stderr"; then
    fail "$name: expected rejection"
  fi
  if ! grep -q "$pattern" "$tmp/stderr"; then
    echo "stderr:" >&2
    cat "$tmp/stderr" >&2
    fail "$name: stderr did not match [$pattern]"
  fi
  echo "ok $name"
}

UPSTREAM_SHA_OVERRIDE=
META_OVERRIDE=
expect_reject "commit before any release" "$c0" "no upstream release tag is contained in"

UPSTREAM_SHA_OVERRIDE=$cn
expect_reject "upstream commit not in HEAD" "$c6" "is not contained in HEAD"
UPSTREAM_SHA_OVERRIDE=

git -C "$work" checkout -q --detach "$cn"
printf '%s\n' side >> "$work/file"
git -C "$work" add file
git -C "$work" commit -q -m side
side=$(git -C "$work" rev-parse HEAD)
UPSTREAM_SHA_OVERRIDE=$side
expect_reject "non-upstream commit" "$side" "is not an upstream commit"
UPSTREAM_SHA_OVERRIDE=

bad=$tmp/bad-meta
mkdir -p "$bad"
cp "$meta/v1.0.4.json" "$bad/v1.0.4.json"
printf '%s\n' '{"version":"9.9.9","build":58}' > "$bad/v1.0.6.json"
printf '%s\n' '{"version":"1.0.7","build":59}' > "$bad/nightly.json"
META_OVERRIDE=$bad
expect_reject "metadata version disagreeing with the tag" "$cn" "does not match tag"
META_OVERRIDE=

older=$tmp/older-nightly
mkdir -p "$older"
cp "$meta/v1.0.4.json" "$older/v1.0.4.json"
cp "$meta/v1.0.6.json" "$older/v1.0.6.json"
printf '%s\n' '{"version":"1.0.5","build":59}' > "$older/nightly.json"
META_OVERRIDE=$older
expect_reject "nightly marketing version older than the release" "$cn" "is older than the released version"
META_OVERRIDE=

mismatch=$tmp/mismatch
mkdir -p "$mismatch"
cp "$meta/v1.0.4.json" "$mismatch/v1.0.4.json"
cp "$meta/v1.0.6.json" "$mismatch/v1.0.6.json"
printf '%s\n' '{"version":"1.0.7","build":60}' > "$mismatch/nightly.json"
META_OVERRIDE=$mismatch
expect_reject "nightly metadata build disagreeing with the tag" "$cn" "does not match tag annotation"
META_OVERRIDE=

# Same commit as the nightly tip, but the published annotation regressed.
git -C "$work" tag -a -f nightly -m '1' "$cn" >/dev/null
git -C "$work" push -q -f "$bare" nightly
low=$tmp/low
mkdir -p "$low"
cp "$meta/v1.0.4.json" "$low/v1.0.4.json"
cp "$meta/v1.0.6.json" "$low/v1.0.6.json"
printf '%s\n' '{"version":"1.0.7","build":1}' > "$low/nightly.json"
META_OVERRIDE=$low
expect_reject "nightly build older than the release build" "$cn" "is older than release build"
echo "ok hermetic cases"

if [ "${SKIP_LIVE_UPSTREAM:-}" = 1 ]; then
  echo "skipped live upstream cases"
  exit 0
fi

live=$tmp/live
git clone -q --filter=blob:none "$LIVE_UPSTREAM" "$live"
git -C "$live" config user.email "version-test@example.com"
git -C "$live" config user.name "version-test"

resolve_live() {
  local rev=$1
  rm -f "$envfile" "$json"
  git -C "$live" checkout -q --detach "$rev"
  (
    cd "$live"
    env -u GITHUB_OUTPUT -u GITHUB_STEP_SUMMARY -u METADATA_DIR -u UPSTREAM_SHA \
      UPSTREAM_URL="$LIVE_UPSTREAM" \
      VERSION_ENV="$envfile" \
      VERSION_JSON="$json" \
      "$RESOLVE"
  ) >"$tmp/stdout"
  # shellcheck disable=SC1090
  . "$envfile"
}

resolve_live "$RELEASE_106"
assert_eq "v1.0.6 marketing version" "1.0.6" "$marketing_version"
assert_eq "v1.0.6 build" "58" "$build_number"
assert_eq "v1.0.6 upstream commit" "$RELEASE_106" "$upstream_sha"
assert_eq "v1.0.6 release tag" "v1.0.6" "$release_tag"
assert_eq "v1.0.6 ignored nightly version" "" "$ignored_nightly_marketing_version"
python3 - "$json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["display"] == "1.0.6 (58)", data
assert data["build"] == 58
PY

resolve_live "$RELEASE_101"
assert_eq "v1.0.1 marketing version" "1.0.1" "$marketing_version"
assert_eq "v1.0.1 build" "26" "$build_number"
assert_eq "v1.0.1 release tag" "v1.0.1" "$release_tag"

resolve_live "$RELEASE_104"
assert_eq "v1.0.4 marketing version" "1.0.4" "$marketing_version"
assert_eq "v1.0.4 build" "51" "$build_number"

resolve_live "$AFTER_104"
assert_eq "commit after v1.0.4 stays on 1.0.4" "1.0.4" "$marketing_version"
assert_eq "commit after v1.0.4 keeps build 51" "51" "$build_number"
if [ "$marketing_version" = "1.0.6" ] || [ "$marketing_version" = "1.0.7" ]; then
  fail "commit after v1.0.4 was labeled $marketing_version"
fi

resolve_live "$UNRELEASED"
assert_eq "5a85706 marketing version" "1.0.6" "$marketing_version"
assert_eq "5a85706 upstream commit" "$UNRELEASED" "$upstream_sha"
assert_eq "5a85706 release" "v1.0.6" "$release_tag"
nightly_commit=$(git -C "$live" rev-parse refs/fork-upstream/nightly^{commit})
nightly_annotation=$(git -C "$live" for-each-ref --format='%(contents:subject)' refs/fork-upstream/nightly)
if [ "$nightly_commit" = "$UNRELEASED" ] && [ "$nightly_annotation" = 59 ]; then
  assert_eq "5a85706 is not labeled 1.0.7" "1.0.7" "$ignored_nightly_marketing_version"
  assert_eq "5a85706 build" "59" "$build_number"
  python3 - "$json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["version"] == "1.0.6", data
assert data["build"] == 59, data
assert data["display"] == "1.0.6 (59)", data
assert data["ignored_nightly_marketing_version"] == "1.0.7", data
PY
else
  echo "note: upstream nightly tag is $nightly_annotation at $nightly_commit; not the 2026-11-08 nightly"
  if [ "$nightly_commit" = "$UNRELEASED" ] || git -C "$live" merge-base --is-ancestor "$nightly_commit" "$UNRELEASED"; then
    assert_eq "5a85706 build follows the contained nightly annotation" "$nightly_annotation" "$build_number"
  else
    assert_eq "5a85706 build falls back to v1.0.6" "58" "$build_number"
  fi
fi

fork=$tmp/fork
git clone -q --local "$ROOT" "$fork"
git -C "$fork" config user.email "version-test@example.com"
git -C "$fork" config user.name "version-test"
git -C "$fork" config commit.gpgsign false
# A fork nightly tag and a fake newer release must not affect the result.
git -C "$fork" tag -a -f nightly -m '1' HEAD >/dev/null
git -C "$fork" tag -f v9.9.9 HEAD >/dev/null
rm -f "$envfile" "$json"
(
  cd "$fork"
  env -u GITHUB_OUTPUT -u GITHUB_STEP_SUMMARY -u METADATA_DIR -u UPSTREAM_SHA \
    UPSTREAM_URL="$LIVE_UPSTREAM" \
    VERSION_ENV="$envfile" \
    VERSION_JSON="$json" \
    "$RESOLVE"
) >"$tmp/stdout"
# shellcheck disable=SC1090
. "$envfile"
assert_eq "fork checkout marketing version" "1.0.6" "$marketing_version"
if [ "$nightly_commit" = "$UNRELEASED" ] && [ "$nightly_annotation" = 59 ]; then
  assert_eq "fork checkout ignored nightly marketing version" "1.0.7" "$ignored_nightly_marketing_version"
fi
assert_eq "fork checkout upstream commit" "$UNRELEASED" "$upstream_sha"
if [ "$build_number" = 1 ] || [ "$marketing_version" = "1.0.1" ] || [ "$marketing_version" = "9.9.9" ]; then
  fail "fork checkout used a local placeholder or decoy: $marketing_version ($build_number)"
fi
if [ "$nightly_commit" = "$UNRELEASED" ] && [ "$nightly_annotation" = 59 ]; then
  assert_eq "fork checkout build" "59" "$build_number"
  python3 - "$json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["display"] == "1.0.6 (59)", data
assert data["version"] == "1.0.6"
assert data["build"] == 59
PY
fi
echo "ok live upstream metadata"
