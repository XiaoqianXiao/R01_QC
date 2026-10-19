# MRI intake and QC on Hyak

This repository is intentionally limited to MRI intake and raw-image quality control. It downloads Flywheel sessions selected from a configured start date, keeps the DICOM source and any extraction products, converts selected series to BIDS NIfTI, runs MRIQC, and writes a consolidated MRIQC CSV.

All persistent study files live under one configured root:

```text
/gscratch/scrubbed/fanglab/xiaoqian/QC/
├── sourcedata/dicom/       downloaded DICOM files and archives
├── bids/                   converted BIDS NIfTI dataset
├── work/heudiconv/         persistent DICOM conversion staging
├── work/mriqc/             persistent MRIQC working directory
├── mriqc/                  MRIQC participant reports, IQMs, and group tables
├── manifests/              Flywheel session manifests
├── summaries/              final BIDS and MRIQC CSVs
└── logs/                   Flywheel, conversion, and Slurm logs
```

## Configure

Copy and review the environment file on Hyak. Set `FLYWHEEL_START_DATE` to the earliest session date to include. Do not store `FW_KEY` in the file.

```bash
cp config/mri_preproc.env.example config/mri_preproc.env
export FW_KEY='uw-chn.flywheel.io:YOUR_API_KEY'
```

## Run order

First inspect exactly what the configured date filter will select across all subjects. This is the default intake path.

```bash
source config/mri_preproc.env
FLYWHEEL_START_DATE="$FLYWHEEL_START_DATE" scripts/download_data_from_flywheel_to_hyak.sh --list-only 1 \
  --output-dir "$DICOM_DIR" --manifest "$MANIFEST_DIR/flywheel_sessions.csv" \
  --project-path "$FLYWHEEL_PROJECT_PATH" --image "$FLYWHEEL_IMAGE"
```

After reviewing the manifest, download all selected sessions and then run the remaining stages in order:

```bash
FLYWHEEL_START_DATE="$FLYWHEEL_START_DATE" bash scripts/download_data_from_flywheel_to_hyak.sh --list-only 0 \
  --output-dir "$DICOM_DIR" --manifest "$MANIFEST_DIR/flywheel_sessions.csv" \
  --project-path "$FLYWHEEL_PROJECT_PATH" --image "$FLYWHEEL_IMAGE"
scripts/un_zip.sh config/mri_preproc.env
scripts/submit_dicom_to_nii.sh config/mri_preproc.env
scripts/submit_mriqc_array_hyak.sh config/mri_preproc.env
scripts/submit_mriqc_group_hyak.sh config/mri_preproc.env
scripts/run_qc_parser.sh config/mri_preproc.env
scripts/run_dataset_info_report_hyak.sh config/mri_preproc.env "$SUMMARY_DIR/bids_sessions.csv"
```

To download only one or more exact Flywheel subject labels instead, use the optional Hyak wrapper:

```bash
scripts/submit_flywheel_download_hyak.sh config/mri_preproc.env SUBJECT_LABEL [SUBJECT_LABEL ...]
```

Run the group step only after the participant array is complete. The final QC deliverables are `summaries/QC_anat.csv`, `summaries/QC_func.csv`, `summaries/QC_parse_manifest.csv`, and `summaries/sum.json`; companion BIDS inventory CSVs are written beside `bids_sessions.csv`. `Poor_Quality` is a threshold-based review flag, not an automatic exclusion.

No fMRIPrep, derivative processing, Kopah publishing, or automatic cleanup is part of this repository.
