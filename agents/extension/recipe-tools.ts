/**
 * Recipe agent tools.
 *
 * Registers the tidy-recipe tools for codemode scripts. Each tool runs
 * agents/tools/recipe_tools.R and returns its JSON as structuredContent.
 *
 * When RECIPE_ALLOWED_SHAS is set (comma-separated sheet_sha256 values), the
 * agent may only write tidy-recipes/<sha>.json for those sheets, and bash is
 * blocked. The driver sets it for each workbook run.
 *
 * When RECIPE_RUN_MANIFEST is set (agents/runs/<run_id>.json, written by the
 * driver), submit_recipe records it in the recipe as `generation`, with the
 * model, thinking level, and session actually used.
 *
 * When RECIPE_FAST=1, requests to ChatGPT models (openai-codex, ChatGPT
 * sign-in) ask for OpenAI's priority service tier ("Fast mode"), the same
 * request change @diegopetrucci/pi-fast makes. Fast mode uses more of the
 * ChatGPT plan's allowance.
 *
 * Load with: pi -e agents/extension/recipe-tools.ts
 */

import { readFileSync } from "node:fs";
import { resolve, relative } from "node:path";
import { defineTool, VERSION, type ExtensionAPI, type ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Type, type TSchema } from "typebox";

const SCRIPT = "agents/tools/recipe_tools.R";
const RECIPE_DIR = "tidy-recipes";
const TIMEOUT_MS = 180_000;

const fastMode = process.env.RECIPE_FAST === "1";
const FAST_PROVIDER = "openai-codex";
const FAST_SERVICE_TIER = "priority";
// service_tier of the latest provider request, recorded in `generation`
let sentServiceTier: string | null = null;

const allowedShas = new Set(
	(process.env.RECIPE_ALLOWED_SHAS ?? "")
		.split(",")
		.map((s) => s.trim())
		.filter(Boolean),
);
const gated = allowedShas.size > 0;

const Result = Type.Object({}, { additionalProperties: true });

function recipePathError(cwd: string, path: string): string | undefined {
	const rel = relative(cwd, resolve(cwd, path));
	const match = /^tidy-recipes\/([0-9a-f]{64})\.json$/.exec(rel);
	if (!match) return `Only tidy-recipes/<sheet_sha256>.json files may be written (got ${path})`;
	if (gated && !allowedShas.has(match[1])) return `Sheet ${match[1]} is not part of this run's workbook`;
	return undefined;
}

function generationRecord(ctx: ExtensionContext): Record<string, unknown> | undefined {
	const manifest = process.env.RECIPE_RUN_MANIFEST;
	if (!manifest) return undefined;
	const run = JSON.parse(readFileSync(resolve(ctx.cwd, manifest), "utf8"));
	return {
		...run,
		agent: {
			harness: "pi",
			pi_version: VERSION,
			provider: ctx.model?.provider ?? null,
			model: ctx.model?.id ?? null,
			thinking_level: pi.getThinkingLevel(),
			fast_mode: fastMode,
			service_tier: sentServiceTier,
			session_id: ctx.sessionManager.getSessionId(),
			...run.agent,
		},
	};
}

function recipeTool(spec: {
	name: string;
	label: string;
	description: string;
	parameters: TSchema;
	checkPath?: boolean;
	addGeneration?: boolean;
}) {
	return defineTool({
		name: spec.name,
		label: spec.label,
		description: spec.description,
		parameters: spec.parameters,
		outputSchema: Result,
		exposure: "codemode",
		executionMode: "parallel",
		async execute(_toolCallId, params, signal, _onUpdate, ctx) {
			const path = (params as { path?: string }).path;
			if (spec.checkPath && path) {
				const error = recipePathError(ctx.cwd, path);
				if (error) throw new Error(error);
			}
			let args = params as Record<string, unknown>;
			if (spec.addGeneration) {
				// Only the driver's run record is trusted; drop anything the agent passed
				const { generation: _fromAgent, ...rest } = args;
				const generation = generationRecord(ctx);
				args = generation ? { ...rest, generation } : rest;
			}
			const result = await pi.exec("Rscript", [SCRIPT, spec.name, JSON.stringify(args)], {
				cwd: ctx.cwd,
				timeout: TIMEOUT_MS,
				signal,
			});
			let parsed: Record<string, unknown>;
			try {
				parsed = JSON.parse(result.stdout.trim().split("\n").pop() ?? "");
			} catch {
				throw new Error(`${spec.name} failed (exit ${result.code}): ${result.stderr.slice(-2000)}`);
			}
			if (result.code !== 0 || "error" in parsed) {
				throw new Error(`${spec.name}: ${String(parsed.error ?? result.stderr.slice(-2000))}`);
			}
			return {
				content: [{ type: "text", text: JSON.stringify(parsed) }],
				structuredContent: parsed,
				details: undefined,
			};
		},
	});
}

let pi: ExtensionAPI;

const Sha = Type.String({ pattern: "^[0-9a-f]{64}$", description: "sheet_sha256 from source_metadata.csv" });
const RecipePath = Type.String({ description: "Recipe path, e.g. tidy-recipes/<sheet_sha256>.json" });

export default function (api: ExtensionAPI) {
	pi = api;

	pi.registerTool(
		recipeTool({
			name: "list_workbook_sheets",
			label: "List workbook sheets",
			description:
				"List every sheet in a workbook with its sheet_sha256, size, numeric cell count, first heading lines, and existing recipe status. Also returns publication and release metadata.",
			parameters: Type.Object({
				xlsx_file: Type.Optional(Type.String({ description: "File name in source-spreadsheets-xlsx/" })),
				sheet_sha256: Type.Optional(Sha),
			}),
		}),
	);

	pi.registerTool(
		recipeTool({
			name: "sheet_grid",
			label: "Sheet grid",
			description:
				"Show a sheet's non-blank cells as one line per row: ADDRESS[flags]=value. Text is JSON-quoted (leading spaces show indentation), numbers are bare, * marks bold, >n marks indent. Use range to page through large sheets.",
			parameters: Type.Object({
				sheet_sha256: Sha,
				range: Type.Optional(Type.String({ description: "A1 range to show, e.g. A1:K40" })),
				max_value_chars: Type.Optional(Type.Integer({ minimum: 10, description: "Truncate values (default 80)" })),
				max_lines: Type.Optional(Type.Integer({ minimum: 1, description: "Rows to return (default 250)" })),
			}),
		}),
	);

	pi.registerTool(
		recipeTool({
			name: "find_template_recipes",
			label: "Find template recipes",
			description:
				"Find existing recipes in the same publication whose sheet layout is similar. layout_similarity near 1 means the same labels sit in the same cells, so the recipe can be copied with few changes.",
			parameters: Type.Object({
				sheet_sha256: Sha,
				limit: Type.Optional(Type.Integer({ minimum: 1, maximum: 20 })),
			}),
		}),
	);

	pi.registerTool(
		recipeTool({
			name: "validate_recipe",
			label: "Validate recipe",
			description: "Check a recipe file against the v0.2 format and the sheet: JSON, required fields, sheet name, cell references, directions, overlaps.",
			parameters: Type.Object({ path: RecipePath }),
		}),
	);

	pi.registerTool(
		recipeTool({
			name: "run_recipe",
			label: "Run recipe",
			description:
				"Validate a recipe, run it through the pipeline, and report records per table, sample records, and coverage failures (blank values, unaccounted cells, missing labels, numeric cells outside tables). passed=true means submit_recipe will mark it validated.",
			parameters: Type.Object({ path: RecipePath }),
		}),
	);

	pi.registerTool(
		recipeTool({
			name: "submit_recipe",
			label: "Submit recipe",
			description:
				"Run all checks and record the result in the recipe: status validated if every check passes, otherwise needs_review with the failures. Optionally set agent_notes.",
			parameters: Type.Object({
				path: RecipePath,
				agent_notes: Type.Optional(Type.String({ description: "Hierarchies, subtotals, caveats a reviewer should know" })),
			}),
			checkPath: true,
			addGeneration: true,
		}),
	);

	pi.on("before_provider_request", (event, ctx) => {
		const model = ctx.model;
		const payload = event.payload;
		if (typeof payload !== "object" || payload === null || Array.isArray(payload)) return undefined;
		const body = payload as Record<string, unknown>;
		if ("service_tier" in body) {
			sentServiceTier = String(body.service_tier);
			return undefined;
		}
		if (!fastMode || !model || model.provider !== FAST_PROVIDER || body.model !== model.id) return undefined;
		if (!ctx.modelRegistry.isUsingOAuth(model)) return undefined;
		sentServiceTier = FAST_SERVICE_TIER;
		return { ...body, service_tier: FAST_SERVICE_TIER };
	});

	// Recipe agents may only write their own workbook's recipe files
	pi.on("tool_call", async (event, ctx) => {
		if (!gated) return undefined;
		if (event.toolName === "bash" || event.toolName === "powershell") {
			return { block: true, reason: "Shell commands are disabled for recipe agents; use the recipe tools." };
		}
		if (event.toolName === "write" || event.toolName === "edit") {
			const error = recipePathError(ctx.cwd, String((event.input as { path?: string }).path ?? ""));
			if (error) return { block: true, reason: error };
		}
		return undefined;
	});
}
