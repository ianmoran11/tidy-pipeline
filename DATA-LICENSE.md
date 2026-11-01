# Data licence and attribution

The source spreadsheets in `source-spreadsheets-xlsx/` and the integrated dataset
(`integrated/*.csv`, published as a release) contain or are derived from aggregate
statistics published by Australian government agencies. The publishers license this
material under the [Creative Commons Attribution 4.0 International
licence](https://creativecommons.org/licenses/by/4.0/) (CC BY 4.0).

You may use it for any purpose, including commercially, provided you give attribution
and indicate that it has been changed. The project's own code and documentation are
under the MIT licence (`LICENSE`); that licence does not apply to the publishers'
material.

Suggested attribution for the integrated dataset:

> Based on Australian Bureau of Statistics, Australian Institute of Health and Welfare
> and Productivity Commission material (CC BY 4.0), adapted by the tidy-pipeline
> project: extracted, relabelled, harmonised and combined across releases.

The publishers have not endorsed this project or the integrated dataset. For
definitions, footnotes, comparability notes and revisions, consult the source tables:
every value in `observations.csv` links to its workbook and cell (`sheet_sha256`,
`address`, `sources.csv`).

## Publications included

| Publisher | Publication | Releases included |
|---|---|---|
| Australian Bureau of Statistics | Criminal Courts, Australia (4513.0) | 2001–02 to 2024–25 (24 releases) |
| Australian Bureau of Statistics | Federal Defendants, Australia (4515.0) | 2008–09 to 2024–25 (17) |
| Australian Bureau of Statistics | Prisoners in Australia (4517.0) | 2001 to 2025 (25) |
| Australian Bureau of Statistics | Recorded Crime – Offenders (4519.0) | 2007–08 to 2024–25 (18) |
| Australian Bureau of Statistics | Recorded Crime – Victims (4510.0) | 2004 to 2025 (22) |
| Australian Bureau of Statistics | Crime Victimisation, Australia (4530.0) | 2008–09 to 2024–25 (17) |
| Australian Bureau of Statistics | Employee Earnings and Hours, Australia (6306.0) | May 2021, May 2023, May 2025 (partial) |
| Australian Institute of Health and Welfare | Child protection Australia | 2020–21 |
| Australian Institute of Health and Welfare | Youth justice in Australia | 2024–25 (partial) |
| Productivity Commission | Report on Government Services — Justice | 2020 (partial) |

Publisher URLs, file names, archive members, byte lengths and SHA-256 fingerprints for
every source file are in `sources/catalogues/` and `source_metadata.csv`. The original
package's notice, with the publishers' own attribution wording and exclusions (logos,
coats of arms, third-party material), is in
`source-spreadsheets-xlsx/original-package-metadata/NOTICE.md`.

Copyright in ABS and Productivity Commission material is owned by the Commonwealth of
Australia, and in AIHW material by the Australian Institute of Health and Welfare.
