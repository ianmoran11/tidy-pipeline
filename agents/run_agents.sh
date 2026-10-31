#!/usr/bin/env bash
# Run recipe agents in parallel, one per workbook.
#
#   agents/run_agents.sh [-f] [-j jobs] [-n max_workbooks] [-p publication_id] [xlsx_file ...]
#
# -f turns on fast mode (priority tier) for ChatGPT models; same as RECIPE_FAST=1.
#
# With no xlsx files, takes unfinished workbooks from agents/queue.csv in queue
# order (publication, then earliest period). Safe to re-run: finished sheets
# are skipped by the prompt, finished workbooks by the queue.
set -euo pipefail
cd "$(dirname "$0")/.."

jobs=4
max=0
publication=""
while getopts "fj:n:p:" opt; do
  case $opt in
    f) export RECIPE_FAST=1 ;;
    j) jobs=$OPTARG ;;
    n) max=$OPTARG ;;
    p) publication=$OPTARG ;;
    *) echo "Usage: $0 [-f] [-j jobs] [-n max_workbooks] [-p publication_id] [xlsx_file ...]" >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))

Rscript agents/queue.R build

if [ $# -gt 0 ]; then
  workbooks=$(printf '%s\n' "$@")
else
  workbooks=$(Rscript -e '
    q <- readr::read_csv("agents/queue.csv", show_col_types = FALSE)
    p <- commandArgs(TRUE)[1]
    q <- q[!q$done & (p == "" | q$publication_id == p), ]
    writeLines(q$xlsx_file)' "$publication")
fi
if [ "$max" -gt 0 ]; then workbooks=$(echo "$workbooks" | head -n "$max"); fi
if [ -z "$workbooks" ]; then echo "Nothing to do"; exit 0; fi

echo "$(echo "$workbooks" | wc -l | tr -d ' ') workbooks, $jobs at a time$([ "${RECIPE_FAST:-}" = 1 ] && echo ', fast mode')"
echo "$workbooks" | xargs -P "$jobs" -I{} agents/run_one.sh {}

Rscript agents/queue.R build
Rscript agents/queue.R costs
