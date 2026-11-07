# Fork maintenance

Fork-only files (keep them out of upstream merges' way):

- `HARDWARE_DISPLAY_RESTORATION.md` – the functional patch and how to verify it
- `.github/fork/sync-upstream.sh` – merges upstream into a candidate branch (git only)
- `.github/workflows/fork-sync-upstream.yml` – scheduled/manual upstream sync
- `.github/workflows/fork-build-macos.yml` – unsigned macOS build, read-only token, no secrets

Everything else is upstream code; `build.yml`, `release.yml` and `select_xcode.sh` are
upstream's and are left untouched so merges stay clean.

## How updates flow

`main` is the fork's known-good branch and carries the patch as normal commits on top of
upstream history. Upstream is integrated by **merging**, never by rebasing, so no history
is rewritten and no force push is needed.

`Fork - Sync upstream` (daily at 19:17 UTC / 03:17 UTC+8, or Run workflow):

1. **prepare** (`contents: write`, only runs git): if upstream `main` is already in
   fork `main`, stop. Otherwise create `fork-sync/upstream-<sha>` from fork `main`, merge
   upstream into it and push that new branch. Existing branches are never overwritten.
   The merge commit message records the upstream SHA and the fork `main` SHA it was based on.
2. **build** (`contents: read`, no secrets, credentials not persisted): builds that branch
   with `Fork - Build macOS (unsigned)` and uploads the app as an artifact.
3. **propose** (`pull-requests: write`): opens a PR `fork-sync/... → main` that links the
   upstream commit and the run with the artifact, including when the build failed.
4. **report**: run summary; the run fails on merge conflicts or build failure.

Nothing is merged automatically. Merging the PR (with a **merge commit**, not squash or
rebase) is what updates `main`. Until then `main` and its last good build stay as they are.
If a newer upstream commit arrives first, a new branch/PR is created; close the older one.

## Enabling

- Scheduled workflows only run from the default branch, so the workflow files must be on
  `main` (merge the PR that adds them). Manual runs can target any branch that has them.
- Actions must be enabled for the fork (Actions tab). GitHub disables scheduled workflows
  in public repositories after 60 days without repository activity; re-enable from the
  workflow page when that happens.
- For the propose step: Settings › Actions › General › Workflow permissions › enable
  "Allow GitHub Actions to create and approve pull requests". Without it the build still
  runs and the branch is pushed; open the PR by hand.
- Runner: `xcode-27`, the same label upstream's `build.yml` uses. Check GitHub's
  [Actions billing docs](https://docs.github.com/en/billing/managing-billing-for-github-actions/about-billing-for-github-actions)
  for the current terms for this repository.

## Upstream's own workflows in this fork

This fork only needs macOS builds, which the `fork-*` workflows provide. Upstream's
`build.yml` ("Build") would otherwise run on every push to `main`: its signed macOS job is
skipped (no Developer ID secrets), while its iOS IPA job and **Publish nightly** job run
and publish a "Nightly build" pre-release and move the `nightly` tag in this fork.

Recommended setup: Actions › "Build" › ⋯ › **Disable workflow**. This is a repository
setting, not a file change, so upstream merges stay conflict-free. `release.yml` only runs
when started by hand and can be left alone (or disabled the same way).

## Using the unsigned macOS build

Download `OpenScreenSharing-macOS-unsigned-<sha>` from the run, unzip, move the app to
/Applications. It is ad-hoc signed and not notarized, so macOS blocks the first launch:
use System Settings › Privacy & Security › Open Anyway, or
`xattr -dr com.apple.quarantine "/Applications/<app>.app"`.

An ad-hoc signed app cannot use the app group container (macOS denies it, and the app
would crash in `AppDatabase.open()` at launch). The workflow therefore compiles with
`UNSIGNED_BUILD`, which makes `AppDirectory.group` use
`~/Library/Application Support/io.nekohasekai.screensharing` instead. Connections saved by
the official app are not visible to this build. This is the only fork change outside the
Hardware Display patch, in `OpenScreenSharing/Model/AppDirectory.swift`.

## Resolving a conflict by hand

```bash
git fetch origin main
git fetch https://github.com/nekohasekai/open-screen-sharing.git main
git switch -c fork-sync/manual-$(date +%Y%m%d) origin/main
git merge FETCH_HEAD          # resolve; keep upstream's changes plus the patch
git push -u origin HEAD       # then open a PR to main
```

Keep the patch's invariants (see `HARDWARE_DISPLAY_RESTORATION.md`): `wantsVirtualDisplay`
requires `usesDynamicResolution`; the field is in `SessionMemory`, `SessionController` and
`Computer`; the `restore-hardware-display` migration stays after upstream's migrations.
Pushing a `cursor/**` branch runs the unsigned macOS build for it.

Local dry run of the merge (does not push):

```bash
.github/fork/sync-upstream.sh
```
