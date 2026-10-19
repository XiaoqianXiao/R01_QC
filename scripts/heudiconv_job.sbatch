#!/usr/bin/env bash
#SBATCH --job-name=qc-heudiconv
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=02:00:00

set -euo pipefail
[[ $# -eq 1 ]] || { echo "Usage: sbatch heudiconv_job.sbatch CONFIG_ENV" >&2; exit 2; }
CONFIG_ENV="$1"
REPO_DIR="${SLURM_SUBMIT_DIR:-$(pwd)}"
[[ "$CONFIG_ENV" = /* ]] || CONFIG_ENV="$REPO_DIR/$CONFIG_ENV"
# shellcheck source=/dev/null
source "$CONFIG_ENV"

mkdir -p "$LOG_DIR/heudiconv" "$BIDS_DIR"
module load apptainer 2>/dev/null || true
mapfile -t subjects < <(find "$DICOM_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -V)
task_id="${SLURM_ARRAY_TASK_ID:?SLURM array index is required}"
(( task_id >= 0 && task_id < ${#subjects[@]} )) || { echo "ERROR: invalid array index $task_id" >&2; exit 2; }
subject="${subjects[$task_id]#sub-}"
subject_dir="$DICOM_DIR/${subjects[$task_id]}"

for session_dir in "$subject_dir"/ses-*; do
  [[ -d "$session_dir" ]] || continue
  session="${session_dir##*/}"; session="${session#ses-}"
  dicoms=()
  for series_dir in "$session_dir"/*; do
    [[ -d "$series_dir" ]] || continue
    case "${series_dir##*/}" in
      anat-T1w_acq-MEMPRvNav_RMS|fmap-epi_acq-opphase_dir-AP|fmap-epi_acq-opphase_dir-PA|func-bold_task-*) ;;
      *) continue ;;
    esac
    [[ "${series_dir##*/}" != *_PhysioLog ]] || continue
    while IFS= read -r -d '' dicom; do
      dicoms+=("/input/${dicom#"$DICOM_DIR"/}")
    done < <(find -L "$series_dir" -type f \( -iname '*.dcm' -o -iname '*.dicom' \) -print0 | sort -z)
  done
  (( ${#dicoms[@]} > 0 )) || { echo "ERROR: no selected DICOMs in $session_dir" >&2; exit 1; }
  apptainer exec -B "$DICOM_DIR:/input:ro" -B "$BIDS_DIR:/bids" \
    -B "$REPO_DIR/scripts/heuristic_reproin_like.py:/heuristic.py:ro" "$HEUDICONV_IMAGE" \
    heudiconv --files "${dicoms[@]}" -s "$subject" -ss "$session" -f /heuristic.py -c dcm2niix -b -o /bids --overwrite
  apptainer exec -B "$BIDS_DIR:/bids" -B "$REPO_DIR/scripts/link_bold_to_fieldmaps.py:/link.py:ro" \
    "$HEUDICONV_IMAGE" python3 /link.py /bids --participant-label "$subject" --session-label "$session"
done
