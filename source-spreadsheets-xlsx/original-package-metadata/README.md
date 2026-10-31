# Source spreadsheets for the SQLite release

All spreadsheets are together in this folder. Filenames are
`<64-character SHA-256>--<retained-source-basename>.xls[x]`.
No workbook was edited, converted, repaired or re-pinned. Identical bytes are
stored once; the manifest preserves every database reference and path alias.

## Find a spreadsheet from a database row

Accepted rows: `observation.asset_id -> asset.asset_id`. Use `asset.source_digest`
and `asset.source_path`; the digest (without `sha256:`) is the filename prefix.
Source-only rows: `source_cell_observation.source_table_id -> source_table.source_table_id`.
Use `source_table.source_workbook_digest` and `source_workbook_path` similarly.
The source-cell row also retains `source_workbook_digest`, `source_sheet`, and
`source_cell`. `database-references.csv` is a filterable index of every direct
spreadsheet reference, including spreadsheet-valued provenance rows.

Example SQL (replace the digest with a filename's first 64 characters):

```sql
SELECT asset_id, publication_id, year, sheet, source_path, normalization
FROM asset WHERE source_digest = 'sha256:YOUR_64_HEX_CHARACTERS';

SELECT source_table_id, publication_id, source_release_id, source_sheet,
       source_workbook_path
FROM source_table
WHERE source_workbook_digest = 'sha256:YOUR_64_HEX_CHARACTERS';

SELECT provenance_ordinal, cohort_id, role, path
FROM provenance_file WHERE sha256 = 'sha256:YOUR_64_HEX_CHARACTERS';

SELECT provenance_ordinal, source_release_id, role, path
FROM source_release_file WHERE sha256 = 'sha256:YOUR_64_HEX_CHARACTERS';
```

## Publisher sources versus processing copies

The database inputs include retained source workbooks AND normalized/bounded
processing copies. Do not assume every file is an unmodified publisher original
or that a filename containing `source` proves original status. Normalization
labels are preserved per accepted asset. `manifest.json` additionally retains
exact recorded upstream/output relationships from three normalization registries;
those upstream spreadsheets are included, but are not misrepresented as direct
DB workbook references. Follow `normalizationRelationships` to the output digest
and then its `databaseReferences`. The CSV covers DIRECT references only.

Some recorded normalization/correction processes can change in-range values.
Original and processed files must not be treated as byte-, geometry-, value- or
semantic-equivalent. Source-cell addresses identify the exact digest recorded in
the DB, not an assumed upstream coordinate. No new equivalence or source repair
is certified by this bundle. The manifest intentionally does not invent missing
upstream relationships or original-publisher identity.

## Scope and verification

The manifest identifies the exact unchanged SQLite asset by expanded SHA-256,
size, schema and release tag. It includes every spreadsheet reference in `asset`,
`source_table`, `provenance_file`, and `source_release_file`, plus the linked
upstream normalization inputs described above. Other unpublished/excluded source
pools, source ZIP/HTML/PDF acquisitions, canonical CSVs and receipts are not
spreadsheets and are outside this companion bundle. This is not the entire
provenance repository or a new semantic acceptance/training approval.

`manifest.json` records per-file SHA-256/size, every database key/path/digest
column, role and sheet context. `CHECKSUMS.sha256` covers every other bundled file.
From inside this folder run `shasum -a 256 -c CHECKSUMS.sha256` (macOS), or
`sha256sum -c CHECKSUMS.sha256` (Linux). The released SQLite schema and bytes were
not changed to add this bundle. See `NOTICE.md` for rights, attribution and limits.
