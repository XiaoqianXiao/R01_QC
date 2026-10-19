# R01 MRI Preprocessing Runbook

This repository contains the operational scripts for the R01/IFOCUS MRI
preprocessing workflow. Cohort-scale processing is designed to run on Hyak with
SLURM and Apptainer/Singularity.

The workflow is managed as a gated release process: download DICOMs, convert
them to BIDS, configure the environment, inventory the dataset, build/cache
frozen software, validate raw data, run MRIQC, pilot fMRIPrep, run canonical
fMRIPrep production, freeze provenance, then run optional derivative branches
only after branch-specific prerequisites and QC gates are met.

The scientific specification is maintained in `plans/`. This README is the
short operational overview. Use `scripts/README_MRI_PREPROCESSING.md` as the
detailed runbook. MSMAll is not available for the current dataset because it
does not include T2w anatomy.

## Start Here: New User Workflow

This is the operational order for a first-time user. The later sections of
this README and the [MRI preprocessing guide](scripts/README_MRI_PREPROCESSING.md)
contain the detailed options and troubleshooting for each step.

### Choose your starting point

- **New data:** start at Step 1, then download and convert DICOMs in Step 2.
- **Existing BIDS dataset:** start at Step 1, confirm `BIDS_DIR`, then continue
  at Step 3.

Do not submit production jobs until the MRIQC and pilot approval gates are
complete. The merge/publish command verifies outputs in Kopah and can remove
their local Fang-scratch copies; use it only after both fMRIPrep stages pass.

```text
Configure -> BIDS inventory -> raw-data preflight -> resources -> MRIQC
-> review gate (review MRIQC results and approve data quality) -> pilot -> approval gate -> anatomy -> functional
-> merge/publish -> provenance closeout
```

### Step-by-step operations

#### 1. Configure the project

```bash
cp config/mri_preproc.env.example config/mri_preproc.env
```

Set and verify the Hyak paths, `FS_LICENSE`, container image paths, and
`TEMPLATEFLOW_HOME`. **Continue only when** `BIDS_DIR`, `DERIVATIVES_DIR`, and
the required image/license paths are correct.

#### 2. Obtain and convert DICOMs (new-data path only)

```bash
export FW_KEY='uw-chn.flywheel.io:YOUR_API_KEY'
./scripts/download_data_from_flywheel_to_hyak.sh --list-only 1
# Review the manifest, then replace SUBJECT_LABEL and download the approved cohort.
./scripts/download_data_from_flywheel_to_hyak.sh \
  --sub-id SUBJECT_LABEL --list-only 0 --jobs 4
# Extract downloaded archives before conversion; skip if DICOMs are already extracted.
./scripts/un_zip.sh
cd scripts && ./submit_dicom_to_nii.sh && cd ..
```

**Continue only when** the expected subject/session directories are in
`BIDS_DIR`. Resolve missing or ambiguous fieldmap mappings before continuing.

#### 3. Inventory and validate the BIDS dataset

```bash
scripts/run_dataset_info_report_hyak.sh config/mri_preproc.env
source config/mri_preproc.env
scripts/run_bids_validator.sh config/mri_preproc.env
scripts/run_python_hyak.sh config/mri_preproc.env \
  scripts/audit_sdc_metadata.py "${BIDS_DIR}" \
  --output "${LOG_DIR}/sdc_metadata_audit.csv"
```

**Continue only when** the inventory reflects the intended cohort and no
unresolved BIDS or AP/PA SDC metadata errors remain.

#### 4. Confirm frozen software and cached resources

```bash
# Run either build command only when its configured image is missing.
sbatch scripts/build_mriqc.sbatch
sbatch scripts/build_fmriprep.sbatch
scripts/prefetch_templateflow_hyak.sh config/mri_preproc.env
```

**Continue only when** the configured fMRIPrep/MRIQC images and TemplateFlow
cache exist. Build HippUnfold/HCP resources only for those optional branches.

#### 5. Run MRIQC

```bash
scripts/submit_mriqc_array_hyak.sh config/mri_preproc.env
# After participant jobs complete:
sbatch scripts/submit_mriqc_group_hyak.sbatch config/mri_preproc.env
```

**Continue only when** participant reports/IQMs and group tables are complete,
with no unexpected pending sessions in the MRIQC status manifest.

#### Review gate — Review MRIQC results and approve data quality

Review reports, record exclusions or corrections, and obtain the study's
required approval. If raw-data problems are found, return to Steps 2–3 and
rerun the affected checks.

#### 6. Run the fMRIPrep pilot

Set `PARTICIPANT_LABELS` to a representative approved subset, then run:

```bash
sbatch scripts/submit_preproduction_pilot_hyak.sbatch config/mri_preproc.env
```

**Continue only when** the pilot validation, SDC audit, output check, and
provenance manifest complete successfully.

#### Gate 2 — Approve the production configuration

Review pilot outputs, SDC behavior, output spaces, and resource use. Freeze the
approved configuration and container versions before production.

#### 7. Run fMRIPrep Stage A: anatomy

```bash
scripts/submit_fmriprep_anat_array_hyak.sh config/mri_preproc.env
```

**Continue only when** every intended subject finishes with the required
anatomical and FreeSurfer outputs. `FMRIPREP_ANAT_ARRAY_CONCURRENCY` caps
simultaneous Stage-A jobs.

#### 8. Run fMRIPrep Stage B: functional sessions

Run only after all intended Stage-A jobs finish:

```bash
scripts/submit_fmriprep_functional_array_hyak.sh config/mri_preproc.env
```

**Continue only when** all intended BOLD-bearing subject/sessions finish.
`FMRIPREP_SESSION_ARRAY_CONCURRENCY` caps simultaneous Stage-B jobs.

#### 9. Merge, verify, and publish

```bash
scripts/merge_and_publish_fmriprep_stages.sh config/mri_preproc.env
```

**Continue only when** eligible fMRIPrep/FreeSurfer outputs are verified in
Kopah and the final release tree is created.

#### 10. Freeze provenance and close out

```bash
source config/mri_preproc.env
scripts/run_python_hyak.sh config/mri_preproc.env \
  scripts/check_fmriprep_outputs.py \
  --fmriprep-dir "${FMRIPREP_OUT}" \
  --freesurfer-dir "${FS_SUBJECTS_DIR}" \
  --output "${LOG_DIR}/fmriprep_output_check.csv"
scripts/run_python_hyak.sh config/mri_preproc.env \
  scripts/freeze_release_manifest.py \
  --config config/mri_preproc.env \
  --output "${PROVENANCE_DIR}/release_manifest.json"
```

**Done when** the output check, manifest, logs, and frozen configuration are
archived together.

#### 11. Run optional derivative branches

Run HippUnfold or FIRST only after canonical-release and branch-specific
QC/eligibility approval. See [Optional Derivative
Branches](#optional-derivative-branches). MSMAll is unsupported because this
dataset lacks T2w anatomy.

### Monitoring, reruns, and concurrency

Review status manifests and logs before rerunning an array submitter. MRIQC
resubmits missing outputs. The split fMRIPrep arrays honor
`FMRIPREP_ANAT_ARRAY_CONCURRENCY` and
`FMRIPREP_SESSION_ARRAY_CONCURRENCY`; other current branch arrays are limited
by Hyak account and scheduler policies. For recovery details, use each script's
`--help` and the detailed runbook.

## Repository Layout

```text
R01/
├── config/
│   └── mri_preproc.env.example
├── containers/
│   └── flywheel.def
├── plans/
│   ├── MRI_Preprocessing_Plan.md
│   ├── MRI_Preprocessing_Plan_withMSMAll.md
│   ├── MRI_Preprocessing_QC_Plan.md
│   └── MRI_Preprocessing_QC_SOP.md
├── scripts/
│   ├── build_flywheel.sbatch
│   ├── build_fmriprep.sbatch
│   ├── build_mriqc.sbatch
│   ├── build_hcp_pipelines.sbatch
│   ├── build_hippunfold.sbatch
│   ├── prefetch_templateflow_hyak.sh
│   ├── prefetch_hippunfold_models_hyak.sh
│   ├── download_data_from_flywheel_to_hyak.sh
│   ├── submit_dicom_to_nii.sh
│   ├── heudiconv_job.sbatch
│   ├── heuristic_reproin_like.py
│   ├── link_bold_to_fieldmaps.py
│   ├── run_bids_validator.sh
│   ├── run_dataset_info_report_hyak.sh
│   ├── run_mriqc.sh
│   ├── run_fmriprep.sh
│   ├── run_hippunfold.sh
│   ├── run_first.sh
│   ├── run_hcp_structural.sh
│   ├── run_hcp_functional.sh
│   ├── run_msmall.sh
│   ├── submit_*_array_hyak.sh
│   ├── submit_*_hyak.sbatch
│   ├── audit_sdc_metadata.py
│   ├── check_fmriprep_outputs.py
│   ├── freeze_release_manifest.py
│   ├── make_multisession_manifest.py
│   ├── report_dataset_info.py
│   ├── README_MRI_PREPROCESSING.md
│   └── README_MSMALL_PIPELINE.md
└── README.md
```

## Workflow At A Glance

| Phase | Purpose | Main command(s) | Move on when |
|---|---|---|---|
| 0. Intake and conversion | Download DICOMs and convert them to BIDS. | `scripts/download_data_from_flywheel_to_hyak.sh`; `scripts/submit_dicom_to_nii.sh` | Expected BIDS subjects/sessions are present. |
| 1. Configure | Create the project env file and verify Hyak paths/resources. | `cp config/mri_preproc.env.example config/mri_preproc.env` | Paths, image locations, `FS_LICENSE`, resources, and concurrency are reviewed. |
| 2. Dataset inventory and build/cache | Record the BIDS inventory and prepare frozen containers/resources. | `scripts/run_dataset_info_report_hyak.sh config/mri_preproc.env`; image builds; TemplateFlow prefetch | Inventory, required images, checksums, TemplateFlow cache, and branch caches exist. |
| 3. Raw preflight | Validate BIDS and AP/PA SDC metadata. | `scripts/run_bids_validator.sh config/mri_preproc.env`; `scripts/run_python_hyak.sh ... audit_sdc_metadata.py` | No unresolved raw-data errors block preprocessing. |
| 4. MRIQC | Generate participant and group raw-image QC outputs. | `scripts/submit_mriqc_array_hyak.sh config/mri_preproc.env`; `sbatch scripts/submit_mriqc_group_hyak.sbatch config/mri_preproc.env` | MRIQC reports/IQM tables are ready for reviewer decisions. |
| 5. Pilot | Run a representative fMRIPrep pilot. | `sbatch scripts/submit_preproduction_pilot_hyak.sbatch config/mri_preproc.env` | Pilot QC accepts settings, SDC behavior, outputs, and resource profile. |
| 6. Canonical production | Run the frozen two-stage fMRIPrep release. | Anatomy array, then functional-session array, then merge/publish. | Every intended subject/session is complete or explicitly documented. |
| 7. Closeout | Check expected outputs and freeze provenance. | `scripts/run_python_hyak.sh ... check_fmriprep_outputs.py`; `scripts/run_python_hyak.sh ... freeze_release_manifest.py` | Logs, commands, config, checksums, and output checks are archived. |
| 8. Optional branches | Run branch derivatives after eligibility/QC gates. | HippUnfold and FIRST commands below. | Branch outputs and branch-specific QC statuses are recorded. |

## Hyak Setup

Log into Hyak and work from the repository root:

```bash
cd /path/to/R01
cp config/mri_preproc.env.example config/mri_preproc.env
```

Edit `config/mri_preproc.env` before running jobs. The default paths are set for the IFOCUS Hyak project:

```bash
SCRUBBED_PROJECT_DIR="/gscratch/scrubbed/fanglab/xiaoqian/IFOCUS"
BIDS_DIR="/gscratch/scrubbed/fanglab/xiaoqian/IFOCUS/sourcedata/nii"
DERIVATIVES_DIR="/gscratch/fang/xiaoqian/IFOCUS/derivatives"
FMRIPREP_OUT="/gscratch/fang/xiaoqian/IFOCUS/derivatives/fmriprep"
FS_LICENSE="/mmfs1/home/xxqian/files/fs_license.txt"
```

At minimum, verify:

- `SCRUBBED_PROJECT_DIR`
- `BIDS_DIR`
- `DERIVATIVES_DIR` and `FMRIPREP_OUT`
- `FS_LICENSE`, usually `/mmfs1/home/xxqian/files/fs_license.txt`
- `FMRIPREP_IMAGE`
- `MRIQC_IMAGE`
- `TEMPLATEFLOW_HOME`, usually `/gscratch/fang/resources/templateflow`
- `PYTHON_CONTAINER_IMAGE`, usually `/gscratch/fang/resources/images/jupyter.sif`
- `PARTICIPANT_LABELS`, only for manual/non-array runs
- `NTHREADS`, `OMP_NTHREADS`, and `MEM_MB`

The default example is set for Hyak-style execution with:

```bash
CONTAINER_RUNTIME="apptainer"
FMRIPREP_IMAGE="/gscratch/fang/resources/images/fmriprep-25.2.5.sif"
MRIQC_IMAGE="/gscratch/fang/resources/images/mriqc-24.0.2.sif"
TEMPLATEFLOW_HOME="/gscratch/fang/resources/templateflow"
PYTHON_CONTAINER_IMAGE="/gscratch/fang/resources/images/jupyter.sif"
PYTHON_CONTAINER_PYTHON="python3"
APPTAINER_NO_MOUNT="bind-paths"
FS_LICENSE="/mmfs1/home/xxqian/files/fs_license.txt"
HYAK_ACCOUNT="fang"
HYAK_PARTITION="ckpt-all"
```

## Download DICOMs From Flywheel

Use `scripts/download_data_from_flywheel_to_hyak.sh` to query Flywheel and
create a manifest. Set the Flywheel API key in the environment; all other
runtime settings are command-line options:

```bash
export FW_KEY='uw-chn.flywheel.io:YOUR_API_KEY'
./scripts/download_data_from_flywheel_to_hyak.sh --list-only 1
```

The default command queries all subjects and all session dates, then writes a
CSV manifest before downloading anything. A successful query always creates
the manifest, including one with only its header when no sessions match.

For downloads, submit compute-node jobs with
`scripts/submit_flywheel_download_hyak.sh`. The wrapper sources the supplied
configuration and explicitly uses `HYAK_ACCOUNT` plus the
`FLYWHEEL_DOWNLOAD_*` resource settings, rather than scheduler defaults. It
submits one job per exact Flywheel subject label:

```bash
export FW_KEY='uw-chn.flywheel.io:YOUR_API_KEY'
./scripts/submit_flywheel_download_hyak.sh \
  config/mri_preproc.env \
  102 105 106 108
```

The wrapper downloads all session dates for each subject. To restrict a
subject to an inclusive start date, run the underlying downloader directly
with its `--start-date` option from an appropriate compute-node allocation.
Unless overridden with `--manifest PATH`, manifests use these names:

```text
flywheel_IFOCUS_subject-all_dates-all.csv
flywheel_IFOCUS_subject-105_dates-all.csv
flywheel_IFOCUS_subject-all_dates-after20260102.csv
flywheel_IFOCUS_subject-105_dates-after20260102.csv
```

The downloader retrieves DICOM files directly, validates their expected sizes,
and skips files that are already complete.

Downloaded files and the default manifest are stored in `--output-dir`, which
defaults to:

```text
/gscratch/scrubbed/fanglab/xiaoqian/IFOCUS/sourcedata/dicom
```

Before BIDS conversion, extract any downloaded `.dicom.zip` archives in place:

```bash
scripts/un_zip.sh
```

The helper skips files that have already been extracted.

`--container-output-dir` is the corresponding Apptainer mount point and
normally remains `/DATA_DIR`. The script requires a compatible Flywheel Python
SDK in `/gscratch/fang/resources/images/flywheel.sif`; it does not install the SDK at run
time. Build that image from the repository definition:

```bash
sbatch scripts/build_flywheel.sbatch
```

The build uses `containers/flywheel.def`, verifies the Python SDK, and writes a
SHA256 checksum and Apptainer inspection record next to the image. It refuses
to replace an existing image unless `OVERWRITE=1` is set.

## Convert DICOMs To BIDS And Record The Dataset Inventory

After the required DICOM sessions are available under the configured Hyak
project, submit the HeuDiConv conversion array from the `scripts/` directory:

```bash
cd scripts
./submit_dicom_to_nii.sh
cd ..
```

`submit_dicom_to_nii.sh`, `heudiconv_job.sbatch`, and
`heuristic_reproin_like.py` currently use the IFOCUS Hyak DICOM root, BIDS
root, HeuDiConv image, and heuristic paths directly. Review those paths before
running the conversion for another project or storage location.

After each subject/session conversion, `heudiconv_job.sbatch` runs
`link_bold_to_fieldmaps.py`. It links every BOLD sidecar in the session to its
sole `acq-opphase` AP/PA fieldmap pair using BIDS `B0FieldSource` and
`B0FieldIdentifier` metadata. The helper stops on missing, ambiguous, or
conflicting fieldmap metadata rather than guessing a mapping.

Once conversion is complete, write a BIDS inventory before preflight and QC:

```bash
scripts/run_dataset_info_report_hyak.sh config/mri_preproc.env
```

By default this writes `${PROVENANCE_DIR}/dataset_info.csv` and summarizes
subjects, sessions, available modality folders, and functional run labels.

## Build Containers And Caches

If the frozen Apptainer images are not already available on Hyak, build them
before production:

```bash
sbatch scripts/build_mriqc.sbatch
sbatch scripts/build_fmriprep.sbatch
sbatch scripts/build_hippunfold.sbatch
sbatch scripts/build_hcp_pipelines.sbatch
```

Populate shared caches before compute-node array jobs:

```bash
scripts/prefetch_templateflow_hyak.sh config/mri_preproc.env
scripts/prefetch_hippunfold_models_hyak.sh config/mri_preproc.env
```

The TemplateFlow cache is required before fMRIPrep production. The HippUnfold
cache is required before the HippUnfold branch.

## Raw Data And MRIQC Gates

Run BIDS validation and the AP/PA fieldmap metadata audit before production:

```bash
source config/mri_preproc.env
scripts/run_bids_validator.sh config/mri_preproc.env
scripts/run_python_hyak.sh config/mri_preproc.env \
  scripts/audit_sdc_metadata.py "${BIDS_DIR}" \
  --output "${LOG_DIR}/sdc_metadata_audit.csv"
```

Run MRIQC participant level as one subject/session per array task, selecting
only sessions with missing outputs:

```bash
scripts/submit_mriqc_array_hyak.sh config/mri_preproc.env
```

The current config scans `BIDS_DIR=/gscratch/scrubbed/fanglab/xiaoqian/IFOCUS/sourcedata/nii`
and writes MRIQC output to `/gscratch/fang/xiaoqian/IFOCUS/derivatives/qc/mriqc`.
MRIQC remains local and is not published to Kopah.
A session is complete when every input image selected by `MRIQC_MODALITIES`
(default: `T1w T2w bold`) has a nonempty IQM JSON and HTML report. Sessions with
missing or empty outputs are submitted, including partially completed sessions;
completed sessions and sessions without matching images are skipped. If nothing
is pending, the script exits successfully without submitting jobs.

The supplied config sets `MRIQC_ARRAY_CONCURRENCY="0"`, so the array has no
script-imposed concurrency cap. SLURM limits and available resources still apply.
Set a positive integer to limit simultaneous tasks per array.

Each invocation writes a pending-session list and a session status TSV under
`MRIQC_LOG_DIR` (default: `${SCRUBBED_PROJECT_DIR}/logs/mriqc`). After jobs finish, rerun
the same command to select any sessions still missing outputs. See the
[MRI preprocessing guide](scripts/README_MRI_PREPROCESSING.md) for manifest details.

After participant-level jobs complete, generate group reports and IQM tables:

```bash
sbatch scripts/submit_mriqc_group_hyak.sbatch config/mri_preproc.env
```

## Run The fMRIPrep Pilot

For a pre-production pilot, set `PARTICIPANT_LABELS` in `config/mri_preproc.env` to a representative sample, then submit:

```bash
sbatch scripts/submit_preproduction_pilot_hyak.sbatch config/mri_preproc.env
```

The pilot wrapper runs:

- BIDS validation
- AP/PA SDC metadata audit
- canonical fMRIPrep pilot run
- expected-output checks
- provenance manifest generation

## Run Canonical fMRIPrep

After the pilot and manual QC are accepted, run the two-stage release. Stage A
uses cpu-g2 for the long all-session anatomical workflow; Stage B uses short
ckpt-all jobs for independent functional sessions:

```bash
scripts/submit_fmriprep_anat_array_hyak.sh config/mri_preproc.env
# After every Stage-A job succeeds:
scripts/submit_fmriprep_functional_array_hyak.sh config/mri_preproc.env

# Merge the completed stages, publish verified fMRIPrep/FreeSurfer outputs to
# Kopah, then remove their local Fang-scratch copies.
scripts/merge_and_publish_fmriprep_stages.sh config/mri_preproc.env
```

This creates a subject list from:

```bash
/gscratch/scrubbed/fanglab/xiaoqian/IFOCUS/sourcedata/nii/sub-*
```

and submits:

```bash
one SLURM array task = one subject
```

Stage A is deliberately **subject-level**, not session-level: each task keeps
all sessions visible so `--subject-anatomical-reference unbiased` can build
the shared within-subject anatomical reference. Stage B then runs one session
per task with `--derivatives anat=...` and never recomputes anatomy or
FreeSurfer. Each Stage-B task has an isolated work directory and writes its
standard `sub-<label>` tree directly under the shared Stage-B output root;
fMRIPrep's internal logs are redirected to scrubbed storage.

Control the maximum number of simultaneous subject jobs in
`config/mri_preproc.env`:

```bash
FMRIPREP_ANAT_ARRAY_CONCURRENCY="4"
FMRIPREP_SESSION_ARRAY_CONCURRENCY="20"
```

Adjust these site-specific values only after confirming available Hyak
allocation and filesystem capacity. The Stage-B default requests 3:45 so jobs
finish with margin before the ckpt-all four-hour interruption window.

These controls apply only to the split fMRIPrep Stage-A and Stage-B arrays.
The MRIQC, HCP, HippUnfold, FIRST, and MSMAll array wrappers currently submit
unconstrained arrays; their effective concurrency is governed by Hyak account
and scheduler limits.

To run one non-array fMRIPrep job manually:

```bash
sbatch scripts/submit_fmriprep_hyak.sbatch config/mri_preproc.env
```

## Canonical fMRIPrep Settings

The launcher runs the frozen baseline from the preprocessing plan:

```bash
--subject-anatomical-reference unbiased
--track-sessions
--output-spaces func T1w MNI152NLin2009cAsym:res-native fsnative
--cifti-output 91k
--msm
--slice-time-ref 0.5
--random-seed 20260904
```

The scripts also archive a multi-session manifest recording the subject/session rows found under `BIDS_DIR`. This documents the sessions available for the common-reference workflow.

On Hyak, `APPTAINER_NO_MOUNT="bind-paths"` prevents Apptainer from trying to
auto-mount unavailable site paths such as `/var/run/slurm`; the scripts provide
the needed project mounts explicitly.

Use a real shared TemplateFlow cache for production, normally:

```bash
TEMPLATEFLOW_HOME="/gscratch/fang/resources/templateflow"
```

The FreeSurfer subjects directory is stored separately at:

```bash
${DERIVATIVES_DIR}/freesurfer
```

## Manual Helper Commands

Run only the SDC metadata audit:

```bash
source config/mri_preproc.env
scripts/run_python_hyak.sh config/mri_preproc.env \
  scripts/audit_sdc_metadata.py "${BIDS_DIR}" \
  --output "${LOG_DIR}/sdc_metadata_audit.csv"
```

Run only output checks after fMRIPrep:

```bash
source config/mri_preproc.env
scripts/run_python_hyak.sh config/mri_preproc.env \
  scripts/check_fmriprep_outputs.py \
  --fmriprep-dir "${FMRIPREP_OUT}" \
  --freesurfer-dir "${FS_SUBJECTS_DIR}" \
  --output "${LOG_DIR}/fmriprep_output_check.csv"
```

Generate a release manifest:

```bash
source config/mri_preproc.env
scripts/run_python_hyak.sh config/mri_preproc.env \
  scripts/freeze_release_manifest.py \
  --config config/mri_preproc.env \
  --output "${PROVENANCE_DIR}/release_manifest.json"
```

## Optional Derivative Branches

Run optional branches only after the canonical inputs and branch-specific QC
plans are ready.

HippUnfold reads raw BIDS and requires the HippUnfold model/resource cache:

```bash
scripts/prefetch_hippunfold_models_hyak.sh config/mri_preproc.env
scripts/submit_hippunfold_array_hyak.sh config/mri_preproc.env
```

FIRST reads completed fMRIPrep anatomical outputs:

```bash
scripts/submit_first_array_hyak.sh config/mri_preproc.env
```

Each eligible branch publishes and verifies its subject output in Kopah before
removing the local Fang-scratch copy. MSMAll and its HCP prerequisite workflow
are out of scope for this dataset because no T2w anatomy is available.

## Outputs

The canonical preprocessing release preserves:

- corrected native functional-grid BOLD
- T1w-space BOLD
- MNI152NLin2009cAsym `res-native` BOLD
- fsnative cortical outputs
- CIFTI 91k
- confounds, masks, transforms, logs, HTML reports
- full FreeSurfer reconstruction
- provenance records and QC reports

Denoising, atlas extraction, connectivity, task GLM, MVPA, HippUnfold, and
FIRST production are separate derivative branches and are not run by the
canonical fMRIPrep scripts.

More detailed operational notes are in `scripts/README_MRI_PREPROCESSING.md`.
# R01_QC
