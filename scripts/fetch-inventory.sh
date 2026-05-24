#!/usr/bin/env bash
# scripts/fetch-inventory.sh
#
# Download and decrypt the HomeOps inventory bundle from S3.
#
# Required environment variables:
#   HOMEOPS_INVENTORY_URI   – S3 URI of the encrypted bundle
#                             e.g. s3://example-placeholder/homeops-inventory.tar.age
#
# Optional environment variables:
#   HOMEOPS_AGE_KEY_FILE    – Path to the age identity (private key) file
#                             Defaults to: ~/.config/homeops/identity.age
#   HOMEOPS_INVENTORY_DIR   – Local directory where inventory files are written
#                             Defaults to: .inventory  (relative to repo root)
#
# Usage:
#   export HOMEOPS_INVENTORY_URI=s3://example-placeholder/homeops-inventory.tar.age
#   ./scripts/fetch-inventory.sh
#
# shellcheck shell=bash

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────

INVENTORY_URI="${HOMEOPS_INVENTORY_URI:-}"
AGE_KEY_FILE="${HOMEOPS_AGE_KEY_FILE:-${HOME}/.config/homeops/identity.age}"
INVENTORY_DIR="${HOMEOPS_INVENTORY_DIR:-.inventory}"

# ── Helpers ───────────────────────────────────────────────────────────────────

log()  { printf '[fetch-inventory] %s\n' "$*"; }
err()  { printf '[fetch-inventory] ERROR: %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

# ── Validation ────────────────────────────────────────────────────────────────

[[ -z "${INVENTORY_URI}" ]] && die "HOMEOPS_INVENTORY_URI is not set. Example: s3://example-placeholder/homeops-inventory.tar.age"
[[ -f "${AGE_KEY_FILE}" ]] || die "Age identity file not found: ${AGE_KEY_FILE}. Set HOMEOPS_AGE_KEY_FILE or place your identity at the default path."

require_cmd aws
require_cmd age
require_cmd tar

# ── Temporary workspace ───────────────────────────────────────────────────────

WORK_DIR="$(mktemp -d)"
# shellcheck disable=SC2064
trap "rm -rf '${WORK_DIR}'" EXIT

ENCRYPTED_BUNDLE="${WORK_DIR}/homeops-inventory.tar.age"
DECRYPTED_TAR="${WORK_DIR}/homeops-inventory.tar"

# ── Download ──────────────────────────────────────────────────────────────────

log "Downloading inventory bundle from ${INVENTORY_URI} …"
aws s3 cp "${INVENTORY_URI}" "${ENCRYPTED_BUNDLE}"
log "Download complete."

# ── Decrypt ───────────────────────────────────────────────────────────────────

log "Decrypting bundle with age …"
age --decrypt \
    --identity "${AGE_KEY_FILE}" \
    --output   "${DECRYPTED_TAR}" \
    "${ENCRYPTED_BUNDLE}"
log "Decryption complete."

# ── Extract ───────────────────────────────────────────────────────────────────

log "Extracting inventory into ${INVENTORY_DIR}/ …"
mkdir -p "${INVENTORY_DIR}"
tar xf "${DECRYPTED_TAR}" -C "${INVENTORY_DIR}"
log "Extraction complete."

# ── Summary ───────────────────────────────────────────────────────────────────

log "Inventory ready:"
find "${INVENTORY_DIR}" -type f | sort | sed 's/^/  /'
