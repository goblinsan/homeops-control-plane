#!/usr/bin/env bash
# scripts/init-inventory.sh
#
# Create a local placeholder inventory directory for first-time setup.
#
# Optional environment variables:
#   HOMEOPS_INVENTORY_DIR   - Local inventory directory
#                             Defaults to: .inventory  (relative to repo root)
#   HOMEOPS_FORCE_INIT      - Set to 1 to overwrite existing files
#
# Usage:
#   ./scripts/init-inventory.sh
#
# shellcheck shell=bash

set -euo pipefail

INVENTORY_DIR="${HOMEOPS_INVENTORY_DIR:-.inventory}"
FORCE_INIT="${HOMEOPS_FORCE_INIT:-0}"

log()  { printf '[init-inventory] %s\n' "$*"; }
err()  { printf '[init-inventory] ERROR: %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }

write_file() {
  local target="$1"
  local content="$2"

  if [[ -e "${target}" && "${FORCE_INIT}" != "1" ]]; then
    die "Refusing to overwrite existing file: ${target}. Set HOMEOPS_FORCE_INIT=1 to replace placeholders."
  fi

  printf '%s\n' "${content}" > "${target}"
}

mkdir -p "${INVENTORY_DIR}"

write_file "${INVENTORY_DIR}/nodes.yaml" 'nodes:
  - name: "<node-name>"
    role: other
    os: "debian-12"
    arch: x86_64
    management_ip: "<LAN_IP>"
    ssh_user: "<SSH_USER>"
    ssh_port: 22
    tags:
      - "replace-me"
    notes: "Replace placeholder values with real inventory data before packing."'

write_file "${INVENTORY_DIR}/repos.yaml" 'repos:
  - name: "homeops-control-plane"
    url: "https://github.com/example-org/example-repo"
    description: "Replace with the real repo inventory."
    deploy_host: "<node-name>"
    deploy_path: "/opt/homeops/<repo-name>"
    local_checkout_path: "/Users/<user>/code/<repo-name>"
    deploy_strategy: "other"
    deployed_services:
      - "<service-name>"
    update_trigger:
      auto_deploy: false
      source: "manual"
      branch: "main"
      workflow: "<workflow-name>"
      runner_node: "<node-name>"
      notes: "Describe how commits become deployed changes."
    depends_on_repos:
      - "<repo-name>"
    auto_pull: false
    branch: "main"
    tags:
      - "replace-me"
    notes: "Add each managed repository that matters operationally."'

write_file "${INVENTORY_DIR}/services.yaml" 'services:
  - name: "<service-name>"
    type: systemd
    node: "<node-name>"
    repo: "homeops-control-plane"
    service_unit: "<service-unit>"
    exposure: lan
    depends_on:
      - "<dependency-service>"
    notes: "Document the real service mapping here after bootstrap."'

write_file "${INVENTORY_DIR}/backups.yaml" 'backups:
  - name: "<backup-job-name>"
    source_node: "<node-name>"
    source_path: "/srv/<dataset-name>"
    destination_uri: "s3://<bucket>/<prefix>/"
    schedule: "daily 02:00"
    retention: "30 days"
    encryption: "age + sse-kms"
    notes: "Replace placeholder values with the real backup job configuration."'

log "Initialized placeholder inventory in ${INVENTORY_DIR}/"
find "${INVENTORY_DIR}" -maxdepth 1 -type f | sort | sed 's/^/  /'
