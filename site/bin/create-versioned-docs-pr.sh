#!/usr/bin/env bash
#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#
# Usage:
#   prepare-versioned-docs.sh [--dry-run] [--create-pr] <release-version>
#
# Options:
#   --dry-run     Print what would be done without making any changes
#   --create-pr   After committing, push the branch and open a PR via `gh`
#
# Environment variables (used when --create-pr is set):
#   GH_TOKEN      GitHub token with repo + PR permissions (required in CI)
#   PR_BASE       Base branch for the versioned-docs PR (default: versioned-docs)
#   MAIN_BASE     Base branch for the main docs PR      (default: main)

set -euo pipefail

# ── helpers ────────────────────────────────────────────────────────────────────

log()  { echo "[INFO]  $*"; }
warn() { echo "[WARN]  $*" >&2; }
die()  { echo "[ERROR] $*" >&2; exit 1; }

step() {
  echo ""
  echo "──────────────────────────────────────────"
  echo "  $*"
  echo "──────────────────────────────────────────"
}

# Run a command, or just print it in dry-run mode
run() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[DRY-RUN] $*"
  else
    "$@"
  fi
}

# ── argument parsing ───────────────────────────────────────────────────────────

DRY_RUN="false"
CREATE_PR="false"
VERSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)   DRY_RUN="true";   shift ;;
    --create-pr) CREATE_PR="true"; shift ;;
    -*)          die "Unknown option: $1" ;;
    *)
      [[ -n "${VERSION}" ]] && die "Unexpected argument: $1"
      VERSION="$1"
      shift
      ;;
  esac
done

[[ -z "${VERSION}" ]] && { echo "Usage: $0 [--dry-run] [--create-pr] <release-version>"; exit 1; }

# ── prerequisite checks ────────────────────────────────────────────────────────

step "Checking prerequisites"

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"
log "Repository root: ${REPO_ROOT}"

if [[ "${CREATE_PR}" == "true" ]]; then
  command -v gh >/dev/null 2>&1 || die "'gh' CLI is required for --create-pr. Install from https://cli.github.com"
  gh auth status >/dev/null 2>&1   || die "'gh' is not authenticated. Set GH_TOKEN or run 'gh auth login'."
fi

if [[ ! -d content/releases ]]; then
  die "content/releases worktree is missing. Run site/bin/checkout-releases.sh first."
fi

# ── version & branch setup ────────────────────────────────────────────────────

BRANCH_NAME="versioned-docs-${VERSION}"
PR_BASE="${PR_BASE:-versioned-docs}"
MAIN_BASE="${MAIN_BASE:-main}"
RELEASE_DIR="content/releases/${VERSION}"
LATEST_INDEX="content/releases/latest/index.md"
RELEASE_INDEX="${RELEASE_DIR}/_index.md"

log "Version:        ${VERSION}"
log "Branch:         ${BRANCH_NAME}"
log "Release dir:    ${RELEASE_DIR}"
log "PR base:        ${PR_BASE}"
log "Main base:      ${MAIN_BASE}"
[[ "${DRY_RUN}" == "true" ]] && warn "DRY-RUN mode — no files or commits will be changed."

# ── guard against double-run ───────────────────────────────────────────────────

step "Validating release directory"

if [[ -d "${RELEASE_DIR}" ]]; then
  die "Release directory already exists: ${RELEASE_DIR}. Refusing to overwrite."
fi

if [[ ! -d content/in-dev/unreleased ]]; then
  die "Source directory content/in-dev/unreleased does not exist."
fi

if [[ ! -f "${LATEST_INDEX}" ]]; then
  die "latest/index.md not found at: ${LATEST_INDEX}"
fi

# ── copy docs ──────────────────────────────────────────────────────────────────

step "Copying unreleased documentation → ${RELEASE_DIR}"

run mkdir -p "${RELEASE_DIR}"
run cp -r content/in-dev/unreleased/. "${RELEASE_DIR}/"
log "Copied unreleased documentation"

# ── patch files ───────────────────────────────────────────────────────────────

step "Patching metadata files"

# Update latest redirect
if grep -q "redirect_to:" "${LATEST_INDEX}"; then
  run sed -i "s|redirect_to: '/releases/.*/'|redirect_to: '/releases/${VERSION}/'|" "${LATEST_INDEX}"
  log "Updated latest release redirect → /releases/${VERSION}/"
else
  warn "${LATEST_INDEX} does not contain a redirect_to field — skipping."
fi

# Update release index title
if grep -q "Apache Polaris Documentation (Unreleased)" "${RELEASE_INDEX}"; then
  run sed -i \
    "s|Apache Polaris Documentation (Unreleased)|Apache Polaris ${VERSION} Documentation|" \
    "${RELEASE_INDEX}"
  log "Updated release title"
else
  warn "${RELEASE_INDEX} title pattern not found — skipping title update."
fi

# Update linkTitle
if grep -q "linkTitle: 'Developer Docs'" "${RELEASE_INDEX}"; then
  run sed -i "s|linkTitle: 'Developer Docs'|linkTitle: '${VERSION}'|" "${RELEASE_INDEX}"
  log "Updated release linkTitle → ${VERSION}"
else
  warn "${RELEASE_INDEX} linkTitle pattern not found — skipping linkTitle update."
fi

# ── commit in the releases worktree ───────────────────────────────────────────

step "Committing changes in releases worktree"

run git -C content/releases add .

# Only commit if there are staged changes (avoids empty-commit errors)
if ! git -C content/releases diff --cached --quiet; then
  run git -C content/releases commit \
    -m "docs: add versioned documentation for ${VERSION}"
  log "Committed release docs"
else
  warn "No staged changes in content/releases — nothing to commit."
fi

# ── commit latest/index.md change in main worktree ────────────────────────────

step "Committing latest redirect update in main worktree"

run git add "${LATEST_INDEX}"

if ! git diff --cached --quiet; then
  run git commit \
    -m "docs: update latest release redirect to ${VERSION}"
  log "Committed latest redirect update"
else
  warn "No staged changes in main worktree — nothing to commit."
fi

# ── push & open PRs ───────────────────────────────────────────────────────────

if [[ "${CREATE_PR}" == "true" ]]; then

  step "Pushing branches and creating PRs"

  REPO_NAME=$(gh repo view --json nameWithOwner -q .nameWithOwner)

  # -- versioned-docs PR --
  RELEASES_REMOTE=$(git -C content/releases remote get-url origin 2>/dev/null || echo "origin")
  log "Pushing ${BRANCH_NAME} to releases remote (${RELEASES_REMOTE})"
  run git -C content/releases push "${RELEASES_REMOTE}" "HEAD:${BRANCH_NAME}"

  VERSIONED_PR_URL=$(run gh pr create \
    --repo "${REPO_NAME}" \
    --base "${PR_BASE}" \
    --head "${BRANCH_NAME}" \
    --title "docs: add versioned documentation for ${VERSION}" \
    --body "Automated PR created by \`prepare-versioned-docs.sh\`.

Adds versioned documentation snapshot for release \`${VERSION}\` and updates the \`latest\` redirect.

Closes #3746")
  log "Versioned-docs PR: ${VERSIONED_PR_URL}"

  # -- main PR (latest redirect) --
  MAIN_BRANCH="docs/update-latest-redirect-${VERSION}"
  log "Pushing ${MAIN_BRANCH} to main remote"
  run git push origin "HEAD:${MAIN_BRANCH}"

  MAIN_PR_URL=$(run gh pr create \
    --repo "${REPO_NAME}" \
    --base "${MAIN_BASE}" \
    --head "${MAIN_BRANCH}" \
    --title "docs: update latest redirect to ${VERSION}" \
    --body "Automated PR created by \`prepare-versioned-docs.sh\`.

Updates \`content/releases/latest/index.md\` to redirect to \`/releases/${VERSION}/\`.")
  log "Main PR: ${MAIN_PR_URL}"

fi

# ── summary ───────────────────────────────────────────────────────────────────

step "Done"
log "Release directory:     ${RELEASE_DIR}"
log "Branch:                ${BRANCH_NAME}"
if [[ "${CREATE_PR}" == "true" ]]; then
  log "Versioned-docs PR:     ${VERSIONED_PR_URL:-<dry-run>}"
  log "Main PR:               ${MAIN_PR_URL:-<dry-run>}"
fi
[[ "${DRY_RUN}" == "true" ]] && warn "DRY-RUN — re-run without --dry-run to apply changes."