#!/usr/bin/env bash
#SBATCH --job-name=r01-mriqc-group
#SBATCH --account=fang
#SBATCH --partition=ckpt-all
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=08:00:00
#SBATCH --output=logs/slurm/mriqc_group_%j.out
#SBATCH --error=logs/slurm/mriqc_group_%j.err

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  sbatch [SLURM_OPTIONS] scripts/submit_mriqc_group_hyak.sbatch CONFIG_ENV

Runs MRIQC group level on Hyak after participant-level outputs are complete.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -ne 1 ]]; then
  usage
  exit 0
fi

CONFIG_ENV="$1"
REPO_DIR="${SLURM_SUBMIT_DIR:-$(pwd)}"
cd "$REPO_DIR"

if [[ "$CONFIG_ENV" != /* ]]; then
  CONFIG_ENV="${REPO_DIR}/${CONFIG_ENV}"
fi

# shellcheck source=/dev/null
source "$CONFIG_ENV"

MRIQC_OUT="${MRIQC_OUT:-${DERIVATIVES_DIR}/qc/mriqc}"
MRIQC_WORK="${MRIQC_WORK:-${SCRUBBED_PROJECT_DIR}/scratch/mriqc_work}"
MRIQC_LOG_DIR="${MRIQC_LOG_DIR:-${SCRUBBED_PROJECT_DIR}/logs/mriqc}"
mkdir -p logs/slurm "$MRIQC_LOG_DIR" "$MRIQC_WORK" "$MRIQC_OUT"

export OMP_NUM_THREADS="${MRIQC_OMP_NTHREADS:-${OMP_NTHREADS:-4}}"
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS="${MRIQC_OMP_NTHREADS:-${OMP_NTHREADS:-4}}"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}"
export LD_PRELOAD="${LD_PRELOAD:-}"

if command -v module >/dev/null 2>&1; then
  module purge || true
  module load apptainer || module load singularity || true
fi

if ! command -v apptainer >/dev/null 2>&1 && ! command -v singularity >/dev/null 2>&1; then
  echo "ERROR: Apptainer/Singularity is not available on this Hyak node." >&2
  exit 127
fi

if [[ "$CONTAINER_RUNTIME" == "docker" ]]; then
  echo "ERROR: Docker is not appropriate for Hyak jobs. Set CONTAINER_RUNTIME=apptainer or singularity." >&2
  exit 2
fi

echo "Running on host: $(hostname)"
echo "SLURM_JOB_ID=${SLURM_JOB_ID:-NA}"
echo "CONFIG_ENV=$CONFIG_ENV"

"${REPO_DIR}/scripts/run_mriqc.sh" "$CONFIG_ENV" group
