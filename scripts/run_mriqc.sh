#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 2 ]] || { echo "Usage: scripts/run_mriqc.sh CONFIG_ENV participant|group" >&2; exit 2; }
CONFIG_ENV="$1"
LEVEL="$2"
# shellcheck source=/dev/null
source "$CONFIG_ENV"

[[ "$LEVEL" == participant || "$LEVEL" == group ]] || { echo "ERROR: level must be participant or group" >&2; exit 2; }
[[ -d "$BIDS_DIR" ]] || { echo "ERROR: BIDS_DIR does not exist: $BIDS_DIR" >&2; exit 2; }
[[ -f "$MRIQC_IMAGE" ]] || { echo "ERROR: MRIQC_IMAGE does not exist: $MRIQC_IMAGE" >&2; exit 2; }
mkdir -p "$MRIQC_OUT" "$MRIQC_WORK" "$MRIQC_LOG_DIR"

runtime="${CONTAINER_RUNTIME:-apptainer}"
command -v "$runtime" >/dev/null 2>&1 || { echo "ERROR: container runtime unavailable: $runtime" >&2; exit 127; }
read -r -a modalities <<< "$MRIQC_MODALITIES"
args=(/data /out "$LEVEL" -w /work --nprocs "$MRIQC_NPROC" --omp-nthreads "$MRIQC_OMP_NTHREADS" --modalities "${modalities[@]}")
[[ "$MRIQC_NO_SUB" == "1" ]] && args+=(--no-sub)
[[ -n "${MRIQC_SINGLE_SUBJECT:-}" ]] && args+=(--participant-label "${MRIQC_SINGLE_SUBJECT#sub-}")
[[ -n "${MRIQC_SINGLE_SESSION:-}" && "${MRIQC_SINGLE_SESSION}" != "single-session" ]] && args+=(--session-id "${MRIQC_SINGLE_SESSION#ses-}")
[[ -n "$EXTRA_MRIQC_ARGS" ]] && read -r -a extra_args <<< "$EXTRA_MRIQC_ARGS" && args+=("${extra_args[@]}")

no_mount_args=()
[[ -n "${APPTAINER_NO_MOUNT:-}" ]] && no_mount_args=(--no-mount "$APPTAINER_NO_MOUNT")
"$runtime" run "${no_mount_args[@]}" -B "$BIDS_DIR:/data:ro" -B "$MRIQC_OUT:/out" -B "$MRIQC_WORK:/work" \
  "$MRIQC_IMAGE" "${args[@]}"
