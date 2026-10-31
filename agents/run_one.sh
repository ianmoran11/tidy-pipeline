#!/usr/bin/env bash
# Run one recipe agent on one workbook. Usage: agents/run_one.sh <xlsx_file>
# Model and thinking level: RECIPE_MODEL, RECIPE_THINKING.
# Fast mode (priority tier, ChatGPT/openai-codex models only): RECIPE_FAST=1.
set -uo pipefail
cd "$(dirname "$0")/.."

model="${RECIPE_MODEL:-openai-codex/gpt-6.1-sol}"
if [ "${RECIPE_FAST:-}" = 1 ] && [[ "$model" != openai-codex/* ]]; then
  echo "warning: RECIPE_FAST=1 only applies to openai-codex models; $model runs at the normal tier" >&2
fi

xlsx="$1"
id="${xlsx%%--*}"
run_id="$(date -u +%Y%m%dT%H%M%SZ)-${id:0:12}"
log="agents/logs/$run_id.jsonl"
mkdir -p agents/logs

# Only the codemode built-in and the recipe tools are loaded; the write gate
# limits the agent to this workbook's recipe files.
pi_args=(--print --mode json --no-session --approve
  --no-extensions -e builtin:codemode -e agents/extension/recipe-tools.ts
  --no-skills --skill agents/skills/tidy-recipe-authoring
  --no-context-files --no-prompt-templates
  --model "$model"
  --thinking "${RECIPE_THINKING:-medium}"
  --tools read,write,edit,codemode,list_workbook_sheets,sheet_grid,find_template_recipes,validate_recipe,run_recipe,submit_recipe)

shas=$(Rscript agents/queue.R shas "$xlsx" | tr -d ' \n') || exit 1
# Writes agents/runs/<run_id>.json (settings, skill hashes, prompt) and prints the prompt
prompt=$(Rscript agents/queue.R manifest "$xlsx" "$run_id" "$log" "${pi_args[@]}") || exit 1
start=$(date +%s)

RECIPE_ALLOWED_SHAS="$shas" RECIPE_RUN_MANIFEST="agents/runs/$run_id.json" \
  pi "${pi_args[@]}" "$prompt" > "$log" 2> "${log%.jsonl}.stderr"
code=$?

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ),$xlsx,$code,$(( $(date +%s) - start )),$run_id" >> agents/runs.csv
echo "$(date +%H:%M:%S) exit=$code $(( $(date +%s) - start ))s $xlsx"
