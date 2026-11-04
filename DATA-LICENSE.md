# Data licence and attribution

The source spreadsheets in `source-spreadsheets-xlsx/` and the integrated dataset
(`integrated/`, published as a release) contain or are derived from aggregate statistics
published by Australian, state and territory government agencies.

**Most of it is licensed under the [Creative Commons Attribution 4.0 International
licence](https://creativecommons.org/licenses/by/4.0/) (CC BY 4.0)** by its publishers:
the ABS, the AIHW, the Productivity Commission, NSW BOCSAR, Victoria's Crime Statistics
Agency, the Queensland Police Service and the Northern Territory Government. You may use
it for any purpose, including commercially, provided you give attribution and indicate
that it has been changed. (Some catalogue copies of the Victorian and Queensland datasets
carry CC BY 3.0 Australia instead, which has the same conditions.)

**Two publishers' material is not CC BY, and is for non-commercial use only:**

| Publisher | Publication | Terms |
|---|---|---|
| Western Australia Police Force | WA Police crime time series | © Government of Western Australia. Copying and non-commercial use with attribution are permitted; no commercial use without the State's prior written permission ([WA.gov.au copyright](https://www.wa.gov.au/copyright)) |
| ACT Policing | ACT Policing quarterly crime statistics | © Commonwealth of Australia (Australian Federal Police). The site's own terms couldn't be read; the AFP's terms permit non-commercial use with attribution ([AFP copyright](https://www.afp.gov.au/copyright)). Treat it as non-commercial unless ACT Policing says otherwise |

Their values are the rows of `observations.csv` whose `release_id` starts with
`wa-wa-police-crime-time-series` or `act-act-policing-quarterly-crime-statistics`, and
their series are in `series/wa-wa-police-crime-time-series.csv` and
`series/act-act-policing-quarterly-crime-statistics.csv`. Drop them for commercial use.

The project's own code and documentation are under the MIT licence (`LICENSE`); that
licence does not apply to the publishers' material.

Suggested attribution for the integrated dataset:

> Based on material from the Australian Bureau of Statistics, the Australian Institute
> of Health and Welfare, the Productivity Commission (CC BY 4.0), the NSW Bureau of Crime
> Statistics and Research, the Crime Statistics Agency Victoria, the Queensland Police
> Service, the Northern Territory Government (CC BY), the Western Australia Police Force
> and ACT Policing (non-commercial use), adapted by the tidy-pipeline project: extracted,
> relabelled, harmonised and combined across releases.

The publishers have not endorsed this project or the integrated dataset. For
definitions, footnotes, comparability notes and revisions, consult the source tables:
every value in `observations.csv` links to its workbook and cell (`sheet_sha256`,
`address`, `sources.csv`).

## Publications included

| Publisher | Publications | Releases included |
|---|---|---|
| Australian Bureau of Statistics | Criminal Courts, Australia (4513.0) | 2001–02 to 2024–25 (24 releases) |
| | Federal Defendants, Australia (4515.0) | 2008–09 to 2024–25 (17) |
| | Prisoners in Australia (4517.0) | 2001 to 2025 (25) |
| | Recorded Crime – Offenders (4519.0) | 2007–08 to 2024–25 (18) |
| | Recorded Crime – Victims (4510.0) | 2004 to 2025 (22) |
| | Crime Victimisation, Australia (4530.0) | 2008–09 to 2024–25 (17) |
| | Corrective Services, Australia (4512.0) | June quarter 2026 |
| | Personal Safety, Australia, and its topic releases (partner violence, sexual violence, stalking, childhood abuse) | 2021–22 |
| | Personal Fraud | 2024–25 |
| Australian Institute of Health and Welfare | Child protection Australia | 2020–21 to 2024–25 (5) |
| | Youth justice in Australia | 2024–25 |
| | Youth detention population in Australia | 2025 |
| | Young people returning to sentenced youth justice supervision | 2023–24 |
| | Young people under youth justice supervision and their interaction with the child protection system | 2022–23 |
| | The health of people in Australia's prisons | 2025 |
| Productivity Commission | Report on Government Services — Justice | 2020 to 2026 (7) |
| | Report on Government Services — Child protection services; Youth justice services | 2026 |
| NSW Bureau of Crime Statistics and Research | 25 series: recorded crime by LGA, trend data, court and sentencing, custody, re-offending, apprehended violence orders, domestic violence, sexual assault, alcohol-related violence, weapons, young people, Closing the Gap targets 10, 11 and 13, and others | Latest release, most recent year only |
| Crime Statistics Agency Victoria | 17 data tables, including recorded offences, criminal incidents, alleged offenders, victims, family incidents, Aboriginal victim and offender data, and the Aboriginal Justice Indicators dashboard | Latest release (year ending June 2026), most recent year only |
| Queensland Police Service | Victim numbers, Queensland and by police region, monthly | Latest file, most recent year only |
| Northern Territory Government | Northern Territory crime statistics | August 2026, most recent year only |
| Western Australia Police Force | WA Police crime time series | Latest file, most recent year only (non-commercial, above) |
| ACT Policing | ACT Policing quarterly crime statistics | Latest file, most recent year only (non-commercial, above) |

Employee Earnings and Hours, in the 2 November 2026 release, is no longer included.

Publisher URLs, file names, archive members, byte lengths and SHA-256 fingerprints for
every source file are in `sources/catalogues/` and `source_metadata.csv`. The original
package's notice, with the publishers' own attribution wording and exclusions (logos,
coats of arms, third-party material), is in
`source-spreadsheets-xlsx/original-package-metadata/NOTICE.md`.

Copyright in ABS and Productivity Commission material is owned by the Commonwealth of
Australia, in AIHW material by the Australian Institute of Health and Welfare, and in the
state and territory material by the respective states and territories (ACT Policing's by
the Commonwealth).
