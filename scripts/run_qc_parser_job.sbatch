#!/usr/bin/env bash
#SBATCH --job-name=qc-parser
set -euo pipefail

CONFIG_ENV="${QC_CONFIG_ENV:?QC_CONFIG_ENV must be provided by run_qc_parser.sh}"
REPO_DIR="${SLURM_SUBMIT_DIR:-$(pwd)}"
# shellcheck source=/dev/null
source "$CONFIG_ENV"
module load apptainer 2>/dev/null || true
runtime="${CONTAINER_RUNTIME:-apptainer}"
"$runtime" exec --no-mount "${APPTAINER_NO_MOUNT:-bind-paths}" \
  -B "$QC_ROOT:$QC_ROOT" -B "$REPO_DIR:$REPO_DIR:ro" \
  "$PYTHON_CONTAINER_IMAGE" "$PYTHON_CONTAINER_PYTHON" "$REPO_DIR/scripts/generate_QCsheets.py" \
  --mriqc-dir "$MRIQC_OUT" --output-dir "$SUMMARY_DIR"
