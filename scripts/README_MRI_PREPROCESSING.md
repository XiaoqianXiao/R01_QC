# MRI QC script reference

The scripts implement one Hyak workflow: Flywheel DICOM intake, optional archive extraction, BIDS conversion, MRIQC, and CSV summaries. Persistent files must remain beneath `QC_ROOT` in `config/mri_preproc.env`.

| Script | Role |
|---|---|
| `download_data_from_flywheel_to_hyak.sh` | Queries Flywheel by subject/date, writes a CSV manifest, and downloads DICOM files. |
| `submit_flywheel_download_hyak.sh` | Submits one download job per explicitly supplied Flywheel subject label. |
| `un_zip.sh` | Extracts `.dicom.zip` files in place; it is harmless when downloads are already DICOM files. |
| `submit_dicom_to_nii.sh` / `heudiconv_job.sbatch` | Convert source DICOM sessions to BIDS NIfTI with persistent staging. |
| `submit_mriqc_array_hyak.sh` | Finds BIDS sessions lacking MRIQC outputs and submits only those tasks. |
| `submit_mriqc_group_hyak.sh` | Submits MRIQC group-level table generation with logs under `QC_ROOT/logs`. |
| `run_qc_parser.sh` | Submits the adapted QC-sheet parser; writes anatomical and functional sheets, parse manifest, and summary JSON under `summaries/`. |
| `run_dataset_info_report_hyak.sh` | Writes BIDS session, subject, group, and run-inventory CSVs. |

The Flywheel manifest is the intake audit trail. Review it before a download. The date filter compares Flywheel session timestamps and excludes undated sessions when a start date is configured. MRIQC output completeness requires a nonempty IQM JSON and HTML report for each configured input image. The parser retains the study's existing threshold rules and marks `Poor_Quality` for review; it does not exclude data automatically.
