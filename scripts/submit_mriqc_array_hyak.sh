#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/submit_mriqc_array_hyak.sh CONFIG_ENV

Checks BIDS_DIR against MRIQC_OUT and submits one Hyak SLURM array task per
subject/session with missing outputs. Each configured input image must have a
nonempty IQM JSON and HTML report to count as complete. Empty sessions are skipped.
Uses BIDS_DIR and MRIQC_OUT from CONFIG_ENV; no jobs are submitted if complete.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -ne 1 ]]; then
  usage
  exit 0
fi

CONFIG_ENV="$1"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

if [[ "$CONFIG_ENV" != /* ]]; then
  CONFIG_ENV="${REPO_DIR}/${CONFIG_ENV}"
fi

# shellcheck source=/dev/null
source "$CONFIG_ENV"

MRIQC_OUT="${MRIQC_OUT:-${DERIVATIVES_DIR}/qc/mriqc}"
MRIQC_WORK="${MRIQC_WORK:-${SCRUBBED_PROJECT_DIR}/scratch/mriqc_work}"
MRIQC_LOG_DIR="${MRIQC_LOG_DIR:-${SCRUBBED_PROJECT_DIR}/logs/mriqc}"

mkdir -p "$MRIQC_LOG_DIR/slurm" "$MRIQC_OUT" "$MRIQC_WORK"

if [[ ! -d "$BIDS_DIR" ]]; then
  echo "ERROR: BIDS_DIR does not exist: $BIDS_DIR" >&2
  exit 2
fi

if [[ ! -f "$MRIQC_IMAGE" ]]; then
  echo "ERROR: MRIQC_IMAGE does not exist: $MRIQC_IMAGE" >&2
  echo "Build it with scripts/build_mriqc.sbatch or copy a frozen image to this path." >&2
  exit 2
fi

timestamp="$(date +%Y%m%d_%H%M%S)_$$"
session_list="${MRIQC_LOG_DIR}/mriqc_pending_sessions_${timestamp}.tsv"
session_manifest="${MRIQC_LOG_DIR}/mriqc_session_status_${timestamp}.tsv"
: > "$session_list"
printf 'subject\tsession\tinput_images\tmissing_outputs\tstatus\n' > "$session_manifest"

shopt -s nullglob
read -r -a modalities <<< "${MRIQC_MODALITIES:-T1w T2w bold}"
subjects=("$BIDS_DIR"/sub-*)
subject_count=0
session_count=0
for subject_dir in "${subjects[@]}"; do
  [[ -d "$subject_dir" ]] || continue
  subject_count=$((subject_count + 1))
  subject="${subject_dir##*/}"
  sessions=()
  for candidate in "$subject_dir"/ses-*; do
    [[ -d "$candidate" ]] && sessions+=("$candidate")
  done
  if [[ "${#sessions[@]}" -eq 0 ]]; then
    sessions=("$subject_dir")
  fi
  for session_dir in "${sessions[@]}"; do
    session="${session_dir##*/}"
    [[ "$session_dir" != "$subject_dir" ]] || session="single-session"
    input_count=0
    missing_count=0
    for modality in "${modalities[@]}"; do
      case "$modality" in
        T1w|T2w) datatype=anat ;;
        bold) datatype=func ;;
        dwi) datatype=dwi ;;
        *) echo "ERROR: Unsupported MRIQC modality: $modality" >&2; exit 2 ;;
      esac
      for input in "$session_dir/$datatype/"*_${modality}.nii "$session_dir/$datatype/"*_${modality}.nii.gz; do
        [[ -f "$input" ]] || continue
        input_count=$((input_count + 1))
        relative="${input#"$BIDS_DIR"/}"
        stem="${relative%.gz}"
        stem="${stem%.nii}"
        # IQMs mirror the BIDS tree; individual reports live at the output root.
        if [[ ! -s "$MRIQC_OUT/$stem.json" || ! -s "$MRIQC_OUT/${stem##*/}.html" ]]; then
          missing_count=$((missing_count + 1))
        fi
      done
    done
    status=complete
    if [[ "$input_count" -eq 0 ]]; then
      status=no-inputs
    elif [[ "$missing_count" -gt 0 ]]; then
      status=pending
      printf '%s\t%s\n' "$subject" "$session" >> "$session_list"
      session_count=$((session_count + 1))
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$subject" "$session" "$input_count" "$missing_count" "$status" >> "$session_manifest"
  done
done

if [[ "$subject_count" -eq 0 ]]; then
  echo "ERROR: no sub-* directories found in BIDS_DIR: $BIDS_DIR" >&2
  exit 2
fi
echo "Session status manifest: $session_manifest"
if [[ "$session_count" -eq 0 ]]; then
  echo "No sessions with missing MRIQC outputs; nothing to submit."
  exit 0
fi

concurrency="${MRIQC_ARRAY_CONCURRENCY:-0}"
if ! [[ "$concurrency" =~ ^[0-9]+$ ]] || [[ "$concurrency" -lt 0 ]]; then
  echo "ERROR: MRIQC_ARRAY_CONCURRENCY must be a nonnegative integer (0 means no array concurrency limit)." >&2
  exit 2
fi

last_index="$((session_count - 1))"
array_range="0-${last_index}"
if [[ "$concurrency" -gt 0 ]]; then
  array_range+="%${concurrency}"
fi

echo "Pending session list: $session_list"
echo "Session manifest: $session_manifest"
echo "Pending session count: $session_count"
echo "Array range: $array_range"

sbatch \
  --array="$array_range" \
  --partition="${HYAK_PARTITION:-ckpt-all}" \
  --time="${MRIQC_HYAK_TIME:-24:00:00}" \
  --cpus-per-task="${MRIQC_NPROC:-${NTHREADS:-16}}" \
  --mem="${MRIQC_MEM_GB:-64}G" \
  --output="${MRIQC_LOG_DIR}/slurm/mriqc_%A_%a.out" \
  --error="${MRIQC_LOG_DIR}/slurm/mriqc_%A_%a.err" \
  "${REPO_DIR}/scripts/submit_mriqc_hyak.sbatch" \
  "$CONFIG_ENV" \
  "$session_list"
