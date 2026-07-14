/**
 * Shared utilities for polling and historical discovery scripts.
 * Centralizes rate limiting, concurrency control, and file I/O helpers.
 */
import fs from 'node:fs';
import path from 'node:path';

/** Global RPC rate limiter: token-bucket style, strictly serialized. */
export function pRateLimit(rps: number): () => Promise<void> {
  if (rps <= 0) return async () => {};
  const minGapMs = 1000 / rps;
  let nextAllowed = 0;
  return async function acquire(): Promise<void> {
    const now = Date.now();
    if (now < nextAllowed)
      await new Promise<void>((r) => setTimeout(r, nextAllowed - now));
    nextAllowed = Math.max(now, nextAllowed) + minGapMs;
  };
}

/** Concurrency limiter: at most `concurrency` async tasks in flight at once. */
export function pLimit(concurrency: number) {
  let active = 0;
  const queue: (() => void)[] = [];
  return async function limit<T>(fn: () => Promise<T>): Promise<T> {
    if (active >= concurrency) await new Promise<void>((r) => queue.push(r));
    active++;
    try {
      return await fn();
    } finally {
      active--;
      queue.shift()?.();
    }
  };
}

/** Ensure the parent directory of a file path exists. */
export function ensureDirForFile(filePath: string): void {
  fs.mkdirSync(path.dirname(path.resolve(filePath)), { recursive: true });
}

/** Read and parse a JSON file; returns null on any error. */
export function safeReadJson<T>(filePath: string): T | null {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8')) as T;
  } catch {
    return null;
  }
}

/** Write a file atomically via a .tmp rename to prevent partial writes on crash. */
export function atomicWriteFile(filePath: string, contents: string): void {
  ensureDirForFile(filePath);
  const abs = path.resolve(filePath);
  fs.writeFileSync(abs + '.tmp', contents);
  fs.renameSync(abs + '.tmp', abs);
}
