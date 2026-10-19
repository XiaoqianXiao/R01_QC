#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 1 ]] || { echo "Usage: scripts/submit_mriqc_group_hyak.sh CONFIG_ENV" >&2; exit 2; }
CONFIG_ENV="$1"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ "$CONFIG_ENV" = /* ]] || CONFIG_ENV="$REPO_DIR/$CONFIG_ENV"
# shellcheck source=/dev/null
source "$CONFIG_ENV"
mkdir -p "$MRIQC_LOG_DIR/slurm"
sbatch --account="$HYAK_ACCOUNT" --partition="$HYAK_PARTITION" --time="$MRIQC_GROUP_HYAK_TIME" \
  --output="$MRIQC_LOG_DIR/slurm/mriqc_group_%j.out" --error="$MRIQC_LOG_DIR/slurm/mriqc_group_%j.err" \
  "$REPO_DIR/scripts/submit_mriqc_group_hyak.sbatch" "$CONFIG_ENV"
