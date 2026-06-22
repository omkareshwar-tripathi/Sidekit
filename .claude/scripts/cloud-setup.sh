#!/bin/bash
# One-time cloud-container setup for this repo (Claude Code on the web).
#
# The remote container is a fresh Ubuntu clone that cannot see your ~/.claude.
# This script installs anything the project needs that isn't already present and
# seeds the atlas board. It is idempotent (command -v guards) and safe to re-run.
#
# Use it as your environment's setup step, or run by hand:
#   bash .claude/scripts/cloud-setup.sh

set -euo pipefail

echo "[cloud-setup] starting"

# Node powers the atlas (and the rest of the tooling). The managed container
# ships Node already; only install if it is somehow missing.
if ! command -v node >/dev/null 2>&1; then
  echo "[cloud-setup] installing Node.js"
  apt-get update -qq && apt-get install -y -qq nodejs
fi
echo "[cloud-setup] node $(node --version 2>/dev/null || echo 'missing')"

# GitNexus is DELIBERATELY NOT installed here. It is a machine-bound local git
# query backend whose binary cannot install in a clean Ubuntu cloud container, so
# the atlas labels it "local-only · machine-bound" and never promotes it. This
# note is intentional — a future session should not "helpfully" try to add it.

# Refresh the atlas's environment view so the board is populated in the container
# (this also runs the preserve-don't-delete merge for your machine-local config).
if [ -f .atlas/sync.js ]; then
  node .atlas/sync.js --env-only >/dev/null 2>&1 || true
  echo "[cloud-setup] atlas environment refreshed"
fi

echo "[cloud-setup] done"
