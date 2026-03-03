/**
 * Config passed to banner() for startup output.
 */
export interface BannerConfig {
  title: string;
  jsonFile: string;
  mode: string;
  factoryAddress?: string | null;
  rpcUrl: string;
  registryDir?: string;
  dryRun?: boolean;
  verbose?: boolean;
  startAt?: number;
  jobs?: number;
  priorityGasPrice?: string | null;
  signerAddress?: string;
}

/**
 * Lightweight logger for createPools CLI.
 * Centralizes output formatting and verbose-mode handling.
 */
export interface Logger {
  verboseEnabled: boolean;
  info: (msg: string) => void;
  success: (msg: string) => void;
  error: (msg: string, err?: unknown) => void;
  verbose: (msg: string) => void;
  section: (title: string) => void;
  banner: (config: BannerConfig) => void;
  dumpForgeOutput: (opts: { stdout?: string; stderr?: string; label?: string }) => void;
}

export function createLogger(opts: { verbose: boolean }): Logger {
  const { verbose } = opts;

  return {
    verboseEnabled: verbose,
    info: (msg: string) => console.log(msg),
    success: (msg: string) => console.log(`✓ ${msg}`),
    error: (msg: string, err?: unknown) => {
      console.error(msg);
      if (err instanceof Error) console.error(err.message);
      const e = err as { data?: unknown; reason?: string };
      if (e?.data) console.error("Error data:", e.data);
      if (e?.reason) console.error("Revert reason:", e.reason);
    },
    verbose: (msg: string) => {
      if (verbose) console.log(msg);
    },
    section: (title: string) => console.log(`\n--- ${title} ---`),
    banner: (config: BannerConfig) => {
      const lines: string[] = [
        `=== ${config.title} ===`,
        `JSON File: ${config.jsonFile}`,
        `Mode: ${config.mode}`,
        ...(config.factoryAddress ? [`Factory Address: ${config.factoryAddress}`] : []),
        `RPC URL: ${config.rpcUrl}`,
        ...(config.registryDir ? [`Registry dir: ${config.registryDir}`] : []),
        ...(config.dryRun ? ["DRY RUN: forge scripts will simulate without broadcasting"] : []),
        ...(config.verbose ? ["VERBOSE: forge scripts will run with -vvvv"] : []),
        ...(config.startAt && config.startAt > 1
          ? [`Starting at pool index: ${config.startAt} (skipping first ${config.startAt - 1} pool(s))`]
          : []),
        ...(config.jobs && config.jobs > 1 ? [`Salt mining: ${config.jobs} parallel workers`] : []),
        ...(config.priorityGasPrice ? [`Priority gas price: ${config.priorityGasPrice}`] : []),
        ...(config.signerAddress ? [`Using signer: ${config.signerAddress}`] : []),
      ];
      lines.forEach((line) => console.log(line));
      if (lines.length > 0) console.log("");
    },
    dumpForgeOutput: ({ stdout, stderr, label = "Forge" }) => {
      if (stdout != null && stdout !== "") console.error(`\n--- ${label} stdout ---\n`, stdout);
      if (stderr != null && stderr !== "") console.error(`\n--- ${label} stderr ---\n`, stderr);
    },
  };
}
