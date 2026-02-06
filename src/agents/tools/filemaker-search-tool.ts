import { Type } from "@sinclair/typebox";
import type { OpenClawConfig } from "../../config/config.js";
import type { AnyAgentTool } from "./common.js";
import { jsonResult, readNumberParam, readStringParam } from "./common.js";

const FilemakerSearchSchema = Type.Object({
  query: Type.String({ description: "Natural language or semantic search query." }),
  maxResults: Type.Optional(
    Type.Number({
      description: "Max results to return (default from config).",
      minimum: 1,
      maximum: 50,
    }),
  ),
});

type FilemakerConfig = NonNullable<OpenClawConfig["tools"]>["filemaker"];

function resolveFilemakerConfig(cfg?: OpenClawConfig): FilemakerConfig | undefined {
  const filemaker = cfg?.tools?.filemaker;
  if (!filemaker || typeof filemaker !== "object") {
    return undefined;
  }
  return filemaker as FilemakerConfig;
}

function isFilemakerSearchEnabled(cfg?: OpenClawConfig): boolean {
  const filemaker = resolveFilemakerConfig(cfg);
  if (!filemaker?.baseUrl?.trim()) {
    return false;
  }
  return filemaker.enabled === true;
}

/** Response shape from FileMaker (or Laravel proxy): same semantics as memory_search for agent consistency. */
type FilemakerSearchResultItem = {
  path?: string;
  snippet: string;
  score?: number;
  recordId?: string;
};

type FilemakerSearchResponse = {
  results: FilemakerSearchResultItem[];
};

const DEFAULT_TIMEOUT_SECONDS = 15;
const DEFAULT_MAX_RESULTS = 10;

export function createFilemakerSearchTool(options: {
  config?: OpenClawConfig;
}): AnyAgentTool | null {
  const cfg = options.config;
  if (!isFilemakerSearchEnabled(cfg)) {
    return null;
  }
  const filemaker = resolveFilemakerConfig(cfg);
  const baseUrl = filemaker?.baseUrl?.trim().replace(/\/+$/, "");
  if (!baseUrl) {
    return null;
  }
  const timeoutMs =
    (typeof filemaker?.timeoutSeconds === "number"
      ? filemaker.timeoutSeconds
      : DEFAULT_TIMEOUT_SECONDS) * 1000;
  const defaultMaxResults =
    typeof filemaker?.maxResults === "number" ? filemaker.maxResults : DEFAULT_MAX_RESULTS;

  return {
    label: "FileMaker Search",
    name: "filemaker_search",
    description:
      "Semantic search over FileMaker-backed data (client notes, claims, policies, SOPs). Use when the user asks about clients, claims, EDI, runbooks, or data that lives in FileMaker. Returns top snippets; leverage FileMaker security and indexing.",
    parameters: FilemakerSearchSchema,
    execute: async (_toolCallId, params) => {
      const query = readStringParam(params, "query", { required: true });
      const maxResults = readNumberParam(params, "maxResults", { integer: true });
      const limit = Math.min(50, Math.max(1, maxResults ?? defaultMaxResults));
      const url = `${baseUrl}`.replace(/\?$/, "");
      const headers: Record<string, string> = {
        "Content-Type": "application/json",
        ...(filemaker?.headers ?? {}),
      };
      if (filemaker?.apiKey?.trim()) {
        headers.Authorization = `Bearer ${filemaker.apiKey.trim()}`;
      }
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), timeoutMs);
      try {
        const res = await fetch(url, {
          method: "POST",
          headers,
          body: JSON.stringify({ query: query.trim(), maxResults: limit }),
          signal: controller.signal,
        });
        clearTimeout(timeoutId);
        if (!res.ok) {
          const text = await res.text().catch(() => "");
          return jsonResult({
            results: [],
            disabled: true,
            error: `FileMaker search failed: ${res.status} ${res.statusText}${text ? ` — ${text.slice(0, 200)}` : ""}`,
          });
        }
        const data = (await res.json().catch(() => null)) as FilemakerSearchResponse | null;
        const results = Array.isArray(data?.results)
          ? data.results
              .filter((r) => r && typeof r.snippet === "string")
              .map((r) => ({
                path: typeof r.path === "string" ? r.path : undefined,
                snippet: String(r.snippet).slice(0, 4000),
                score: typeof r.score === "number" ? r.score : undefined,
                recordId: typeof r.recordId === "string" ? r.recordId : undefined,
              }))
          : [];
        return jsonResult({ results });
      } catch (err) {
        clearTimeout(timeoutId);
        const message = err instanceof Error ? err.message : String(err);
        const isAbort =
          String(err).includes("abort") || (err instanceof Error && err.name === "AbortError");
        return jsonResult({
          results: [],
          disabled: true,
          error: isAbort
            ? `FileMaker search timed out after ${timeoutMs / 1000}s`
            : `FileMaker search failed: ${message}`,
        });
      }
    },
  };
}
