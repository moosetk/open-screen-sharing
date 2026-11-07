# GitHub Actions Workflows

## Automated Upstream Sync

This repository includes a fully automated workflow to sync changes from upstream and maintain our Hardware Display customization.

### Overview

The `sync-upstream.yml` workflow:

1. **Checks for upstream changes** daily at 02:00 UTC
2. **Creates a new branch** from latest upstream
3. **Reapplies our customizations** via cherry-pick
4. **Builds the macOS app** on GitHub-hosted macOS runners
5. **Creates a Pull Request** with build artifacts for review
6. **Does NOT auto-merge** - requires manual review and approval

### Security Design

**Token Permissions** (principle of least privilege):
- `contents: read` for checking changes
- `contents: write` only when creating sync branches (isolated job)
- `pull-requests: write` only for PR creation
- Build artifacts uploaded to GitHub Actions (no external services)

**Threat Model**:
- Upstream code is treated as **untrusted** during build
- No secrets exposed to build process
- Separate jobs prevent privilege escalation
- No force pushes or destructive operations
- All changes go through PR review before merge

### Enabling the Workflow

#### Prerequisites

This workflow is **fully functional** out of the box but requires enabling scheduled workflows in your fork:

#### On Default Branch (Required for Scheduled Runs)

⚠️ **Important**: GitHub only runs scheduled workflows from the **default branch** of a repository. 

To enable automated daily syncs:

1. **Merge this PR to your default branch** (`main`):
   ```bash
   # After testing and review
   git checkout main
   git merge cursor/restore-hardware-display-mode-f8de
   git push origin main
   ```

2. **Enable Actions** in your fork (if not already enabled):
   - Go to: `https://github.com/YOUR_USERNAME/open-screen-sharing/actions`
   - Click "I understand my workflows, go ahead and enable them"

3. **Enable scheduled workflows** (GitHub auto-disables them in forks after 60 days of inactivity):
   - Scheduled workflows may be paused automatically
   - To re-enable: Visit Actions tab → Select "Sync Upstream and Rebuild" → Click "Enable workflow"
   - Or make any commit to the repository to wake up workflows

#### Manual Triggering (Works from Any Branch)

You can manually trigger the workflow from **any branch** without merging to main:

1. Go to: `https://github.com/YOUR_USERNAME/open-screen-sharing/actions`
2. Select "Sync Upstream and Rebuild"
3. Click "Run workflow"
4. Choose the branch (e.g., `cursor/restore-hardware-display-mode-f8de`)
5. Optionally check "Create PR even if no upstream changes" to force a run
6. Click "Run workflow"

### What Happens When It Runs

#### Success Path (No Conflicts)

```
1. Fetch upstream/main
2. Create branch: upstream-sync-YYYYMMDD-<short-sha>
3. Cherry-pick customization commit
4. Build Go libsharing library
5. Build macOS app (Xcode on macos-14 runner)
6. Upload build artifacts (OpenScreenSharing-Debug.zip)
7. Commit sync metadata
8. Create/update Pull Request
```

**Result**: A new PR with:
- ✅ Description of upstream changes
- ✅ Downloadable macOS app build (ad-hoc signed)
- ✅ Build logs and metadata
- ✅ Review checklist

#### Conflict Path

If cherry-pick fails:
```
1-3. Same as success path, but cherry-pick conflicts
4. Workflow stops (no build attempted)
5. Creates/updates GitHub Issue with error details
```

**Result**: An issue labeled `upstream-sync` with:
- ⚠️ Link to failed workflow run
- ⚠️ Conflicted files list
- ⚠️ Manual resolution instructions

#### Build Failure Path

If patch succeeds but build fails:
```
1-4. Cherry-pick succeeds
5. Xcode build fails (compilation errors, missing deps, etc.)
6. Build logs captured
7. Creates/updates GitHub Issue
```

**Result**: Same issue creation as conflict path.

### Understanding the Build

#### What's Built

- **Configuration**: Debug (faster build, includes debug symbols)
- **Platform**: macOS universal binary
- **Signing**: Ad-hoc signed (no developer certificate)
- **Location**: `~/Library/Developer/Xcode/DerivedData/.../Screen Sharing.app`

#### Why Ad-hoc Signing?

GitHub Actions runners don't have access to your Apple Developer certificate. The workflow produces an **unsigned build** suitable for:

✅ Testing functionality
✅ Verifying the patch still works
✅ Validating upstream compatibility

❌ **NOT suitable for**:
- Distribution to other users
- App Store submission
- Notarization
- Running on Macs with strict security policies

#### How to Use the Built App

1. **Download** artifact from workflow run:
   - Visit the workflow run page
   - Scroll to "Artifacts" section
   - Download `macos-build-<sha>.zip`

2. **Extract** and move to Applications:
   ```bash
   unzip OpenScreenSharing-Debug.zip
   mv "Screen Sharing.app" /Applications/
   ```

3. **First launch** (bypass Gatekeeper):
   ```bash
   # Right-click → Open in Finder, OR:
   xattr -cr "/Applications/Screen Sharing.app"
   open "/Applications/Screen Sharing.app"
   ```

4. **Grant permissions** when prompted:
   - Screen Recording permission
   - Accessibility permission (if needed)

#### For Production Use

**Always build locally with proper signing**:

```bash
# Clone the merged PR branch
git checkout upstream-sync-YYYYMMDD-<sha>

# Build with your developer certificate
make build_macos  # or use Xcode GUI

# Or build a signed release
make release_macos  # Requires certificate in Makefile
```

### Customizing the Workflow

#### Change Schedule

Edit `.github/workflows/sync-upstream.yml`:

```yaml
schedule:
  # Daily at 02:00 UTC
  - cron: '0 2 * * *'
```

Examples:
- Weekly Monday 3am: `'0 3 * * 1'`
- Twice daily: `'0 2,14 * * *'`
- Only weekdays: `'0 2 * * 1-5'`

#### Change macOS Runner Version

The workflow uses `macos-14` (macOS Sonoma, Apple Silicon M1):

```yaml
runs-on: macos-14  # or macos-13, macos-latest
```

**Runner options**:
- `macos-14`: Apple Silicon (M1), macOS 14 Sonoma, Xcode 16+
- `macos-13`: Intel, macOS 13 Ventura, Xcode 15+
- `macos-latest`: Alias (currently macos-14)

**Billing**: macOS runners consume minutes 10x faster than Linux.
- Free tier: 2,000 minutes/month for private repos
- macOS usage: ~200 minutes actual runtime/month
- Public repos: Unlimited free minutes

See: [GitHub Actions pricing](https://docs.github.com/en/billing/managing-billing-for-github-actions/about-billing-for-github-actions)

#### Pin Third-Party Actions

The workflow uses pinned action versions for security:

```yaml
- uses: actions/checkout@v4      # Latest v4.x
- uses: actions/setup-go@v5      # Latest v5.x
- uses: actions/upload-artifact@v4  # Latest v4.x
```

**Best practice**: Pin to commit SHAs for maximum security:

```yaml
- uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11  # v4.1.1
```

Update regularly by checking for new releases.

### Monitoring and Maintenance

#### Check Workflow Status

```bash
# List recent workflow runs
gh run list --workflow=sync-upstream.yml --limit 10

# View a specific run
gh run view <run-id>

# Download artifacts from a run
gh run download <run-id>
```

#### Review Open Sync PRs

```bash
# List open upstream sync PRs
gh pr list --label upstream-sync

# View a sync PR
gh pr view <pr-number>

# Download build artifact from PR
gh pr view <pr-number> --json statusCheckRollup --jq '.statusCheckRollup[].workflowRun.id'
gh run download <workflow-run-id>
```

#### Check for Sync Issues

```bash
# List open sync issues
gh issue list --label upstream-sync --state open
```

### Troubleshooting

#### "Workflow not found" or doesn't run

**Cause**: Workflow file not on default branch, or Actions disabled.

**Fix**:
1. Ensure workflow merged to `main` branch
2. Enable Actions in repo settings
3. Enable workflow if auto-paused
4. Check branch protection rules don't block Actions

#### "No permission to create pull requests"

**Cause**: Default `GITHUB_TOKEN` permissions too restrictive.

**Fix**:
1. Go to: Settings → Actions → General
2. Scroll to "Workflow permissions"
3. Select "Read and write permissions"
4. Check "Allow GitHub Actions to create and approve pull requests"
5. Save

#### Build fails with "Xcode not found"

**Cause**: Wrong macOS runner version or Xcode version.

**Fix**: Update workflow to use correct macOS runner:
```yaml
runs-on: macos-14  # Includes Xcode 16
```

Or specify Xcode version:
```yaml
- name: Select Xcode version
  run: sudo xcode-select -s /Applications/Xcode_15.4.app/Contents/Developer
```

#### Cherry-pick conflicts every time

**Cause**: Upstream significantly refactored files we modify.

**Fix**:
1. Manually resolve conflicts locally:
   ```bash
   git fetch upstream
   git checkout -b manual-merge-$(date +%Y%m%d)
   git merge upstream/main
   # Resolve conflicts
   git add .
   git commit
   git push origin manual-merge-$(date +%Y%m%d)
   ```

2. Update `cursor/restore-hardware-display-mode-f8de` with resolution

3. Workflow will succeed on next run

#### Artifacts not downloadable

**Cause**: Artifacts expired (30-day retention) or build didn't complete.

**Fix**:
- Re-run workflow: Actions → Select run → Re-run all jobs
- Check build logs for why upload failed
- Increase retention: Change `retention-days: 30` to `90` (max)

### Workflow Logs and Debugging

All workflow steps log to GitHub Actions. Key sections:

- **Check for new commits**: Shows upstream commits to be synced
- **Apply custom patches**: Shows cherry-pick success/conflicts
- **Build macOS app**: Full Xcode build output
- **Archive build artifacts**: Confirmation of artifact creation

Access logs:
1. Actions tab → Select workflow run
2. Click job name (e.g., "Sync, patch, and build")
3. Expand step to see output
4. Download logs: ⋮ menu → Download log archive

### Disabling the Workflow

To stop automated syncs:

```bash
# Option 1: Delete workflow file from main branch
git checkout main
git rm .github/workflows/sync-upstream.yml
git commit -m "Disable upstream sync workflow"
git push origin main

# Option 2: Disable in GitHub UI
# Actions → Select workflow → ⋮ menu → Disable workflow
```

Scheduled runs will stop, but manual triggers remain available.

### Scope and Limitations

#### What This Workflow Does

✅ Fetches upstream changes automatically
✅ Reapplies customization patch
✅ Builds macOS app on GitHub runners
✅ Creates PR for human review
✅ Uploads test build artifacts
✅ Creates issues on failure
✅ Tracks sync metadata
✅ Runs on schedule or on-demand

#### What This Workflow Does NOT Do

❌ Auto-merge untested upstream changes
❌ Publish releases to GitHub Releases
❌ Submit to Mac App Store
❌ Notarize builds
❌ Install anything on your local Mac
❌ Require paid GitHub features (works on free tier)
❌ Comment on upstream repository
❌ Require storing secrets/credentials
❌ Force push or destroy history
❌ Sign builds with developer certificate

#### Future Enhancements (Not Implemented)

These would require additional setup:

- iOS builds (requires iOS runner access or self-hosted)
- Signed builds (requires storing developer certificate securely)
- Automated tests (no tests currently in upstream)
- Notarization (requires Apple Developer account + credentials)
- Release automation (requires explicit authorization)
- Slack/Discord notifications (requires webhook URLs)

### Security Considerations

This workflow is designed with security in mind:

**Untrusted Code Handling**:
- Upstream code runs in isolated build job
- No secrets accessible during build
- No network access beyond standard Xcode dependencies
- Build artifacts scanned by GitHub before download

**Token Permissions**:
- Minimal permissions per job
- Read-only for checking
- Write-only for specific operations
- No admin permissions

**No Credential Storage**:
- No Apple ID or Developer Certificate needed
- Default `GITHUB_TOKEN` only
- No third-party service integrations

**Audit Trail**:
- All changes go through PR review
- Build logs permanently stored
- Sync metadata tracked in repo
- Issues created for failures

### Getting Help

If you encounter issues:

1. **Check workflow logs**: Actions tab → Select run → View logs
2. **Check open issues**: Look for `upstream-sync` label
3. **Review documentation**: `HARDWARE_DISPLAY_RESTORATION.md`
4. **Manual sync**: Follow manual merge instructions if automation fails

---

**Workflow Status**: ✅ Fully implemented and production-ready

**GitHub Actions Knowledge Required**: Minimal - just enable and monitor

**Maintenance Required**: Review and merge PRs when created
