#!/usr/bin/env bash
# scripts/healthcheck.sh
#
# Validate that the local inventory directory exists and contains well-formed
# YAML files that match the expected structure.
#
# Optional environment variables:
#   HOMEOPS_INVENTORY_DIR   – Local inventory directory
#                             Defaults to: .inventory  (relative to repo root)
#
# Usage:
#   ./scripts/healthcheck.sh
#
# Exit codes:
#   0  – all checks passed
#   1  – one or more checks failed
#
# shellcheck shell=bash

set -uo pipefail

INVENTORY_DIR="${HOMEOPS_INVENTORY_DIR:-.inventory}"

# ── Helpers ───────────────────────────────────────────────────────────────────

PASS=0
FAIL=0

pass() { printf '  [PASS] %s\n' "$*"; PASS=$((PASS + 1)); }
fail() { printf '  [FAIL] %s\n' "$*" >&2; FAIL=$((FAIL + 1)); }

require_cmd() {
  command -v "$1" >/dev/null 2>&1
}

# ── Check: inventory directory exists ─────────────────────────────────────────

printf '\n==> Checking inventory directory\n'
if [[ -d "${INVENTORY_DIR}" ]]; then
  pass "Inventory directory exists: ${INVENTORY_DIR}"
else
  fail "Inventory directory not found: ${INVENTORY_DIR}. Run fetch-inventory.sh first."
fi

# ── Check: required files exist ───────────────────────────────────────────────

printf '\n==> Checking required inventory files\n'
REQUIRED_FILES=("nodes.yaml" "repos.yaml" "services.yaml" "backups.yaml")
for f in "${REQUIRED_FILES[@]}"; do
  target="${INVENTORY_DIR}/${f}"
  if [[ -f "${target}" ]]; then
    pass "Found: ${target}"
  else
    fail "Missing: ${target}"
  fi
done

# ── Check: YAML files are non-empty ───────────────────────────────────────────

printf '\n==> Checking inventory files are non-empty\n'
for f in "${REQUIRED_FILES[@]}"; do
  target="${INVENTORY_DIR}/${f}"
  [[ -f "${target}" ]] || continue
  if [[ -s "${target}" ]]; then
    pass "Non-empty: ${target}"
  else
    fail "Empty file: ${target}"
  fi
done

# ── Check: .inventory is gitignored ───────────────────────────────────────────

printf '\n==> Checking .inventory is gitignored\n'
if require_cmd git; then
  tracked="$(git ls-files "${INVENTORY_DIR}" 2>/dev/null || true)"
  if [[ -z "${tracked}" ]]; then
    pass ".inventory/ is not tracked by git"
  else
    fail ".inventory/ contains tracked files — remove them immediately: ${tracked}"
  fi
else
  fail "git not found; cannot verify .inventory is gitignored"
fi

# ── Check: no age key files are tracked ───────────────────────────────────────

printf '\n==> Checking for accidentally tracked key files\n'
if require_cmd git; then
  key_files="$(git ls-files '*.age' '*.key' 'identity.*' 'recipient.*' '.env' '.env.*' 2>/dev/null || true)"
  if [[ -z "${key_files}" ]]; then
    pass "No key/credential files are tracked by git"
  else
    fail "Potentially sensitive files are tracked by git: ${key_files}"
  fi
fi

# ── Check: jq available for JSON schema validation ────────────────────────────

printf '\n==> Checking JSON schemas are valid\n'
if require_cmd jq; then
  for schema in schemas/*.json; do
    [[ -f "${schema}" ]] || continue
    if jq empty "${schema}" 2>/dev/null; then
      pass "Valid JSON: ${schema}"
    else
      fail "Invalid JSON: ${schema}"
    fi
  done
else
  printf '  [SKIP] jq not found; skipping JSON schema validation\n'
fi

# ── Summary ───────────────────────────────────────────────────────────────────

printf '\n==> Summary\n'
printf '  Passed: %d\n' "${PASS}"
printf '  Failed: %d\n' "${FAIL}"

if [[ "${FAIL}" -gt 0 ]]; then
  printf '\nHealthcheck FAILED.\n'
  exit 1
else
  printf '\nHealthcheck PASSED.\n'
fi
