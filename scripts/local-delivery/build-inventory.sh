#!/usr/bin/env bash
# Render the repository file listing the local model is shown, so a spec can be
# probed against the same context the workflow will give it.
#
#   ./build-inventory.sh /path/to/repo > inventory.txt
set -euo pipefail
cd "${1:?repo path}"
git ls-files | while read -r f; do
  printf '%s (%s bytes)\n' "$f" "$(wc -c < "$f" | tr -d ' ')"
done
