# CI Slack notifications from `CHANGELOG.md`

A small shell script that turns a release-tag deploy into a Slack message
**built from the project's own `CHANGELOG.md`**. CI invokes it once after a
successful deploy; the script writes a `notification.json` file that any
Slack-webhook step in any CI system can then send unchanged.

The point: *don't* re-write the release notes inside the CI pipeline.
Your changelog is already the source of truth - read from it.

## What it produces

For a deploy of tag `2026.05.001` to `prod / us-east-1`, the Slack message
looks like:

```
🚀 Orbit: release 2026.05.001 deployed to prod us-east-1

Added
- New SSO provider for enterprise customers
- Mobile push notifications

Fixed
- Off-by-one in invoice line totals

Diff: https://github.com/acme/orbit/compare/2026.04.003...2026.05.001
```

If the changelog has no entry for that version, you get a `⚠️ No changelog
entries were found for this release.` line - useful, not silent.

## Assumptions

1. Your repo follows [Keep a Changelog]: a top-level `CHANGELOG.md` whose
   per-version sections begin with `## [<version>]` and which keeps reference
   links at the bottom (`[<version>]: https://...`).
2. The CI step that calls this script has these env vars exported:
   - `VERSION`       — the release tag (e.g. `2026.05.001`)
   - `ENVIRONMENT`   — e.g. `dev` / `qa` / `prod`
   - `REGION`        — e.g. `ca-central-1`
3. `jq` is available in the CI image (Bitbucket / GH Actions runners both
   have it; if not, `apt-get install -y jq` first).
4. **The CHANGELOG entry might land after the QA tag was cut.** This is the
   subtle one: the script fetches the *latest* `CHANGELOG.md` from `origin/main`
   before extracting, so prod deploys see updates that were appended between
   QA tagging and prod cut.

## The script: `create-notification.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

# Pull the latest CHANGELOG.md from main. This handles the very common case
# where the changelog is amended AFTER QA tagging but BEFORE the prod deploy:
# without this fetch, prod would notify with stale notes.
git fetch origin main:refs/remotes/origin/main 2>/dev/null || true
CHANGELOG_CONTENT=$(git show origin/main:CHANGELOG.md 2>/dev/null || cat CHANGELOG.md)

# Extract the section for $VERSION. Stops at the next "## [" header OR at the
# reference-links block ("[version]: https://...") - whichever comes first.
SECTION=$(echo "$CHANGELOG_CONTENT" | awk -v tag="$VERSION" '
  $0 ~ ("^## \\[" tag "\\]") { in_section=1; next }
  in_section && /^## \[/      { exit }
  in_section && /^\[.*\]:/    { exit }
  in_section                  { print }
')

# Also pull the reference link for $VERSION, if one exists.
LINK=$(echo "$CHANGELOG_CONTENT" | awk -v tag="$VERSION" -F': ' '
  tolower($0) ~ ("^\\[" tolower(tag) "\\]:") { print $2; exit }
')

# Convert markdown ### subheadings to Slack-flavored bold (*Added*, *Fixed*, …)
SECTION=$(echo "$SECTION" | sed -E 's/^### (.*)$/*\1*/')

HEADER="🚀 *${APP_NAME:-App}*: release *$VERSION* deployed to *$ENVIRONMENT* *$REGION*"

if [ -z "$SECTION" ]; then
  BODY="⚠️  No changelog entries were found for this release."
  PAYLOAD="$(printf "%s\n\n%s\n" "$HEADER" "$BODY")"
else
  PAYLOAD="$(printf "%s\n\n%s" "$HEADER" "$SECTION")"
  if [ -n "$LINK" ]; then
    PAYLOAD="$(printf "%s\n\nDiff: %s\n" "$PAYLOAD" "$LINK")"
  fi
fi

# Slack's webhook accepts { "text": "..." }. jq -R reads raw lines and -s
# slurps them into a single string, escaping newlines/quotes for us.
printf '%s' "$PAYLOAD" | jq -Rs '{text: .}' > notification.json
```

Save as `create-notification.sh` at the repo root and `chmod +x` it.

## A matching CHANGELOG snippet

```markdown
## [2026.05.001] - 2026-05-15
### Added
- New SSO provider for enterprise customers
- Mobile push notifications

### Fixed
- Off-by-one in invoice line totals

[2026.05.001]: https://github.com/acme/orbit/compare/2026.04.003...2026.05.001
[2026.04.003]: https://github.com/acme/orbit/compare/2026.04.002...2026.04.003
```

## Wiring into Bitbucket Pipelines

```yaml
- step:
    name: "Deploy to prod (us-east-1)"
    deployment: prod-us-east-1
    script:
      - export VERSION=$BITBUCKET_TAG
      - export ENVIRONMENT=prod
      - export REGION=us-east-1
      - export APP_NAME=Orbit
      # ... deploy steps here (ansible-playbook, etc.) ...
      - ./create-notification.sh
      - pipe: atlassian/slack-notify:2.3.1
        variables:
          WEBHOOK_URL: $WEBHOOK_URL
          PAYLOAD_FILE: notification.json
```

## Wiring into GitHub Actions

```yaml
- name: Build Slack payload from CHANGELOG
  env:
    VERSION:     ${{ github.ref_name }}
    ENVIRONMENT: prod
    REGION:      us-east-1
    APP_NAME:    Orbit
  run: ./create-notification.sh

- name: Send Slack notification
  uses: slackapi/slack-github-action@v1.27.0
  with:
    payload-file-path: ./notification.json
  env:
    SLACK_WEBHOOK_URL:  ${{ secrets.SLACK_WEBHOOK_URL }}
    SLACK_WEBHOOK_TYPE: INCOMING_WEBHOOK
```

## Why I keep coming back to this pattern

- **Single source of truth.** The CHANGELOG already exists; nobody has to
  remember to update a second place.
- **Survives the rebase.** Pulling from `origin/main` at notify-time means
  changelog amendments made after QA-tagging still surface in prod's message.
- **Provider-agnostic.** The script produces a plain JSON file. Bitbucket
  pipes, GitHub Actions, GitLab CI, Buildkite, plain `curl` - all consume it.
- **Zero deps beyond `git` + `jq` + `awk`/`sed`.** Already in every CI image.

## Caveats

- The `awk` block is intentionally permissive about the changelog format. If
  your changelog ends a section with a horizontal rule (`---`) or an inline
  link rather than the next `## [` header, double-check the section actually
  parses by piping through `awk` locally.
- If your `$VERSION` contains regex meta-characters (it shouldn't for
  semver-style tags), the `awk` `~` match will misbehave - escape them or
  switch to literal matching.
- The script assumes `set -euo pipefail`. The `git fetch` and `git show` are
  intentionally `|| true` / `|| cat` so a CI runner without network access
  still falls back to the file on disk.

[Keep a Changelog]: https://keepachangelog.com/
