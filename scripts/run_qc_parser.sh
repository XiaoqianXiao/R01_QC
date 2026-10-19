#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 1 ]] || { echo "Usage: scripts/run_qc_parser.sh CONFIG_ENV" >&2; exit 2; }
CONFIG_ENV="$1"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ "$CONFIG_ENV" = /* ]] || CONFIG_ENV="$REPO_DIR/$CONFIG_ENV"
# shellcheck source=/dev/null
source "$CONFIG_ENV"
mkdir -p "$LOG_DIR/qc_parser"
sbatch --job-name=qc-parser --account="$HYAK_ACCOUNT" --partition="$HYAK_PARTITION" \
  --cpus-per-task=1 --mem=32G --time=01:00:00 \
  --output="$LOG_DIR/qc_parser/qc_parser_%j.out" --error="$LOG_DIR/qc_parser/qc_parser_%j.err" \
  --export=ALL,QC_CONFIG_ENV="$CONFIG_ENV" "$REPO_DIR/scripts/run_qc_parser_job.sbatch"
