# Dimension dictionary

`dimensions.csv` lists the names recipes use for dimensions (headers and table
`meta_data`) and for sheet-level `meta_data`. Recipe agents name dimensions from
it, so the same concept gets the same name in every recipe. The publisher's own
wording is kept separately in each header's `caption`.

Edit `dimensions.csv` directly; it is the source of truth. The recipe validator
reads it on every check.

## Columns

| Column | Meaning |
|---|---|
| `name` | snake_case name used in recipes |
| `kind` | `dimension` (headers and table `meta_data`) or `sheet_metadata` (sheet-level `meta_data`) |
| `status` | `use`, or `avoid` for names that are too vague; `notes` says what to use instead |
| `description` | What the labels are. Agents choose names by this |
| `aliases` | Other wordings that mean this name, separated by `\|`. The validator tells agents to use `name` instead |
| `example_labels` | Typical labels, separated by `\|` |
| `notes` | Distinctions and guidance |

Each alias may belong to only one row. Put ambiguous words (such as `duration`)
in an `avoid` row and list the specific names in its `notes`.

## New names from agents

When nothing fits, an agent declares a new name in its recipe:

```json
"new_dimensions": [
  { "name": "third_party_order_status",
    "description": "Whether a child in out-of-home care received a third-party parental responsibility order in the year",
    "example_labels": ["Received a third-party order in 2020–21", "Did not receive a third-party order in 2020–21"] }
]
```

Agents run in parallel and cannot edit this file. Review their names after a run:

```bash
Rscript agents/dictionary.R report
```

This writes two files (both generated; do not edit):

- `usage.csv`: every name used in recipes, whether it is in the dictionary, and where it is used.
- `proposed.csv`: names declared in `new_dimensions` and names not in the
  dictionary, with descriptions, captions, example labels and the closest
  dictionary names.

For each proposal, either add a row with status `use`, or add the proposed name
to an existing row's `aliases` so later agents are pointed to that row. Then check
the file:

```bash
Rscript agents/dictionary.R check
```

Recipes written before a name was added keep their names; `usage.csv` shows them.
Aliases map them to dictionary names during normalisation.
