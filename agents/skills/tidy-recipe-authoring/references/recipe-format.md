# Recipe format v0.2

JSON Schema: `schema/recipe-v0.2.json` in the project root.

```json
{
  "version": "0.2",
  "sheet_sha256": "<64 hex, equals the file name>",
  "sheet": "Table 38",
  "kind": "data",
  "status": "draft",
  "template_from": "<sheet_sha256 of the recipe you copied, optional>",
  "agent_notes": "optional",
  "new_dimensions": [],
  "meta_data": [
    { "name": "table_title", "cells": "A3" },
    { "name": "table_subtitle", "cells": "A4" },
    { "name": "stub_heading", "cells": "A6" },
    { "name": "notes", "cells": "A74:A83" }
  ],
  "tables": [
    {
      "name": "males",
      "range": "A5:K28",
      "values_range": "B8:K11,B13:K16",
      "meta_data": [ { "name": "sex", "cells": "B7" } ],
      "headers": [
        { "name": "principal_offence", "caption": "Principal offence(c)", "direction": "W", "cells": "A8:A11,A13:A16" },
        { "name": "period", "direction": "N", "cells": "B6:K6" },
        { "name": "measure", "direction": "NNW", "cells": "B5,G5" }
      ]
    }
  ]
}
```

## Fields

| Field | Meaning |
|---|---|
| `sheet` | Exact sheet name, including trailing spaces (`"Table 1 "`) |
| `kind` | `data`, `contents`, `notes`, `empty`, `unsupported` |
| `reason` | Required when `kind` is not `data` |
| `status` | Write `"draft"`. `submit_recipe` sets `validated` or `needs_review` |
| `validation` | Written by `submit_recipe`. Do not write it |
| `generation` | Agent settings and prompt, written by `submit_recipe`. Do not write it |
| `new_dimensions` | Names not in `dictionary/dimensions.csv`, each with `name`, `description` and optional `example_labels`. See `naming.md` |
| `meta_data` (sheet) | Cells that describe the whole sheet. Each item becomes one named value (or vector) |
| `tables[].range` | The whole table block, including its headers and block label |
| `tables[].values_range` | The data cells only. Each cell becomes one record |
| `tables[].meta_data` | Labels that apply to every value in this table only (e.g. a block label "Males") |
| `tables[].headers` | Labels attached to each value by direction |
| `name` (headers and `meta_data`) | A dictionary name, or one declared in `new_dimensions`. See `naming.md` |
| `caption` (optional) | The publisher's caption for the dimension, exactly as printed |

Cell references: `A1`, `A1:B3`, or comma-separated lists of these with no
spaces. The same cell may be used by several tables' headers (e.g. a shared
year row), but each value cell belongs to exactly one table.

## Header directions

A header is attached to a value cell by looking from the value toward the
header cells. These are `unpivotr::enhead` directions:

| Direction | Header cells are | Use for |
|---|---|---|
| `N` | directly above, same column | one column label per value column |
| `NNW` | above, at or to the left | a label that spans several columns but is only written in the first (merged headings like `Number` over B:F) |
| `NNE` | above, at or to the right | spanning label written in the last column |
| `W` | directly left, same row | one row label per value row |
| `WNW` | left, at or above | a label that spans several rows but is only written in the first (grouping labels) |
| `WSW` | left, at or below | spanning label written in the last row |
| `E`, `S`, `ENE`, `ESE`, `SSE`, `SSW` | mirror images | rare |
| `ABOVE`, `BELOW`, `LEFT`, `RIGHT` | nearest header within the header cells' span | irregular layouts |

Each header's `cells` must be only the header cells for that dimension, never
value cells.

## Output

Each value cell produces a record with `row`, `col`, `address`, `.value`, and
one field per header. Sheet and table meta_data are returned alongside.
