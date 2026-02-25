/**
 * Shared CLI and env utilities for discovery scripts.
 * All scripts use chain-ID-suffixed env vars and consistent CLI args.
 */
import path from "node:path";

/** Parse generic --key value args. Keys with no value get true. */
export function parseArgs(argv: string[]): Record<string, string | boolean> {
  const out: Record<string, string | boolean> = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith("--")) continue;
    const key = a.slice(2);
    const next = argv[i + 1];
    if (!next || next.startsWith("--")) {
      out[key] = true;
    } else {
      out[key] = next;
      i++;
    }
  }
  return out;
}

/** Get env var: VAR_${chainId} first, fallback to VAR for single-chain usage. */
export function getEnvForChain(name: string, chainId: number): string | undefined {
  const v = process.env[`${name}_${chainId}`];
  if (v != null && String(v).trim()) return String(v).trim();
  const fallback = process.env[name];
  if (fallback != null && String(fallback).trim()) return String(fallback).trim();
  return undefined;
}

/** Require env var; throws if missing. */
export function mustEnvForChain(name: string, chainId: number): string {
  const v = getEnvForChain(name, chainId);
  if (!v) throw new Error(`Missing required env var: ${name}_${chainId} or ${name}`);
  return v;
}

/** Parse int from string or number; return default if invalid. */
export function toInt(v: unknown, def: number): number {
  if (typeof v === "number") return Number.isFinite(v) ? Math.floor(v) : def;
  if (typeof v === "string") {
    const n = Number(v);
    return Number.isFinite(n) ? Math.floor(n) : def;
  }
  return def;
}

/** Resolve output path: outputDir/chainId/filename */
export function resolveOutputPath(outputDir: string, chainId: number, filename: string): string {
  return path.resolve(outputDir, String(chainId), filename);
}

/** Resolve checkpoint path: checkpointDir/chainId/filename */
export function resolveCheckpointPath(checkpointDir: string, chainId: number, filename: string): string {
  return path.resolve(checkpointDir, String(chainId), filename);
}

/** Common args for all scripts */
export interface CommonArgs {
  chainId: number;
  outputDir: string;
  chunkBlocks: number;
}

/** Common args for polling scripts (add checkpoint dir) */
export interface PollingArgs extends CommonArgs {
  checkpointDir: string;
}

/** Common args for historical scripts */
export interface HistoricalArgs extends CommonArgs {
  startBlock: number;
  endBlock: number | null;
}
