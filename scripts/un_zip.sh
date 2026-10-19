#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 1 ]] || { echo "Usage: scripts/un_zip.sh CONFIG_ENV" >&2; exit 2; }
# shellcheck source=/dev/null
source "$1"

found=0
while IFS= read -r -d '' archive; do
  found=1
  destination="$(dirname "$archive")"
  echo "Extracting $archive -> $destination"
  unzip -n "$archive" -d "$destination"
done < <(find "$DICOM_DIR" -type f -name '*.dicom.zip' -print0)

[[ "$found" -eq 1 ]] || echo "No .dicom.zip archives found; direct DICOM downloads need no extraction."
