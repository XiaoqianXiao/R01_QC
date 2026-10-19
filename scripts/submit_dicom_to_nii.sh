#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 1 ]] || { echo "Usage: scripts/submit_dicom_to_nii.sh CONFIG_ENV" >&2; exit 2; }
CONFIG_ENV="$1"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ "$CONFIG_ENV" = /* ]] || CONFIG_ENV="$REPO_DIR/$CONFIG_ENV"
# shellcheck source=/dev/null
source "$CONFIG_ENV"

mkdir -p "$BIDS_DIR" "$HEUDICONV_WORK_DIR" "$LOG_DIR/heudiconv"
mapfile -t subjects < <(find "$DICOM_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -V)
[[ "${#subjects[@]}" -gt 0 ]] || { echo "ERROR: no subject directories in $DICOM_DIR" >&2; exit 2; }

echo "Submitting ${#subjects[@]} DICOM-to-BIDS tasks."
sbatch --array="0-$(( ${#subjects[@]} - 1 ))" --partition="$HYAK_PARTITION" --account="$HYAK_ACCOUNT" \
  --output="$LOG_DIR/heudiconv/heudiconv_%A_%a.out" --error="$LOG_DIR/heudiconv/heudiconv_%A_%a.err" \
  "$REPO_DIR/scripts/heudiconv_job.sbatch" "$CONFIG_ENV"
