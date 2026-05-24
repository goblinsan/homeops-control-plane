#!/usr/bin/env bash
# scripts/pack-inventory.sh
#
# Encrypt and upload the local HomeOps inventory bundle to S3.
#
# Required environment variables:
#   HOMEOPS_INVENTORY_URI        – S3 URI where the encrypted bundle is stored
#                                  e.g. s3://example-placeholder/homeops-inventory.tar.age
#   HOMEOPS_AGE_RECIPIENT_FILE   – Path to a file containing one or more age public keys
#                                  (one per line) used for encryption
#                                  e.g. ~/.config/homeops/recipient.txt
#
# Optional environment variables:
#   HOMEOPS_INVENTORY_DIR        – Local directory containing the inventory files
#                                  Defaults to: .inventory  (relative to repo root)
#
# Usage:
#   export HOMEOPS_INVENTORY_URI=s3://example-placeholder/homeops-inventory.tar.age
#   export HOMEOPS_AGE_RECIPIENT_FILE=~/.config/homeops/recipient.txt
#   ./scripts/pack-inventory.sh
#
# shellcheck shell=bash

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────

INVENTORY_URI="${HOMEOPS_INVENTORY_URI:-}"
RECIPIENT_FILE="${HOMEOPS_AGE_RECIPIENT_FILE:-}"
INVENTORY_DIR="${HOMEOPS_INVENTORY_DIR:-.inventory}"

# ── Helpers ───────────────────────────────────────────────────────────────────

log()  { printf '[pack-inventory] %s\n' "$*"; }
err()  { printf '[pack-inventory] ERROR: %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

# ── Validation ────────────────────────────────────────────────────────────────

[[ -z "${INVENTORY_URI}" ]]    && die "HOMEOPS_INVENTORY_URI is not set."
[[ -z "${RECIPIENT_FILE}" ]]   && die "HOMEOPS_AGE_RECIPIENT_FILE is not set."
[[ -f "${RECIPIENT_FILE}" ]]   || die "Age recipient file not found: ${RECIPIENT_FILE}"
[[ -d "${INVENTORY_DIR}" ]]    || die "Inventory directory not found: ${INVENTORY_DIR}. Run fetch-inventory.sh first or create the directory."

require_cmd aws
require_cmd age
require_cmd tar

# ── Temporary workspace ───────────────────────────────────────────────────────

WORK_DIR="$(mktemp -d)"
# shellcheck disable=SC2064
trap "rm -rf '${WORK_DIR}'" EXIT

PLAIN_TAR="${WORK_DIR}/homeops-inventory.tar"
ENCRYPTED_BUNDLE="${WORK_DIR}/homeops-inventory.tar.age"

# ── Build age recipient arguments ─────────────────────────────────────────────

RECIPIENT_ARGS=()
while IFS= read -r line || [[ -n "${line}" ]]; do
  # Skip blank lines and comments
  [[ -z "${line}" || "${line}" =~ ^# ]] && continue
  RECIPIENT_ARGS+=(--recipient "${line}")
done < "${RECIPIENT_FILE}"

[[ "${#RECIPIENT_ARGS[@]}" -eq 0 ]] && die "No age recipients found in ${RECIPIENT_FILE}."

# ── Pack ──────────────────────────────────────────────────────────────────────

log "Creating tar archive from ${INVENTORY_DIR}/ …"
tar cf "${PLAIN_TAR}" -C "${INVENTORY_DIR}" .
log "Archive created."

# ── Encrypt ───────────────────────────────────────────────────────────────────

log "Encrypting archive with age (${#RECIPIENT_ARGS[@]} recipient(s)) …"
age --encrypt \
    "${RECIPIENT_ARGS[@]}" \
    --output "${ENCRYPTED_BUNDLE}" \
    "${PLAIN_TAR}"
log "Encryption complete."

# ── Upload ────────────────────────────────────────────────────────────────────

log "Uploading encrypted bundle to ${INVENTORY_URI} …"
aws s3 cp "${ENCRYPTED_BUNDLE}" "${INVENTORY_URI}"
log "Upload complete."

log "Inventory bundle packed and stored at ${INVENTORY_URI}."
