use crate::constants;
use crate::libs::explorer::{ExplorerApiLib, SupportedExplorerType};
use crate::screens::screen_manager::{Screen, ScreenResult};
use crate::state_manager::STATE_MANAGER;
use crate::ui::{get_spinner_frame, Buffer};
use crate::util::deploy_config_lib::get_config_dir;
use alloy::primitives::keccak256;
use crossterm::event::Event;
use regex::Regex;
use serde_json::Value;
use std::io::BufRead;
use std::path::PathBuf;
use std::process::Command;
use std::sync::{Arc, Mutex};

pub struct ExecuteDeployScriptScreen {
    execution_status: Arc<Mutex<ExecutionStatus>>,
    execution_error_message: Arc<Mutex<String>>,
}

#[derive(PartialEq, Debug, PartialOrd)]
enum ExecutionStatus {
    Failed = -1,
    Pending = 0,
    DryRunCompleted = 1,
    DeploymentCompleted = 2,
    Success = 3,
}

impl ExecuteDeployScriptScreen {
    pub fn new() -> Result<Self, Box<dyn std::error::Error>> {
        let screen = ExecuteDeployScriptScreen {
            execution_status: Arc::new(Mutex::new(ExecutionStatus::Pending)),
            execution_error_message: Arc::new(Mutex::new(String::new())),
        };

        let working_dir = STATE_MANAGER.working_directory.clone();

        let execution_status = Arc::clone(&screen.execution_status);
        let execution_error_message = Arc::clone(&screen.execution_error_message);

        let chain_id = STATE_MANAGER
            .workflow_state
            .lock()?
            .chain_id
            .clone()
            .unwrap();
        let rpc_url = STATE_MANAGER
            .workflow_state
            .lock()?
            .web3
            .clone()
            .unwrap()
            .rpc_url;
        let private_key = STATE_MANAGER
            .workflow_state
            .lock()?
            .private_key
            .clone()
            .unwrap();

        let explorer = STATE_MANAGER.workflow_state.lock()?.block_explorer.clone();

        let explorer_api_key = STATE_MANAGER
            .workflow_state
            .lock()?
            .explorer_api_key
            .clone();

        let skip_verification = STATE_MANAGER.workflow_state.lock()?.skip_verification;

        tokio::spawn(async move {
            let mut command = &mut Command::new("forge");
            command = command
                .arg("script")
                .arg(
                    working_dir
                        .join("script")
                        .join("deploy")
                        .join("Deploy-all.s.sol"),
                )
                .arg(format!("--rpc-url={}", rpc_url))
                .arg("-vvvv")
                .arg(format!("--private-key={}", private_key));

            match execute_command(command) {
                Ok(result) => {
                    *execution_status.lock().unwrap() = ExecutionStatus::DryRunCompleted;
                    if let Some(error_message) = result {
                        *execution_error_message.lock().unwrap() = error_message;
                    }
                }
                Err(e) => {
                    *execution_status.lock().unwrap() = ExecutionStatus::Failed;
                    *execution_error_message.lock().unwrap() = e.to_string();
                    return;
                }
            }

            if !skip_verification && explorer.is_some() && explorer_api_key.is_some() {
                let explorer_api =
                    ExplorerApiLib::new(explorer.clone().unwrap(), explorer_api_key.clone().unwrap())
                        .unwrap();

                let verifier = match explorer_api.explorer.explorer_type {
                    SupportedExplorerType::EtherscanV2 => "etherscan",
                    SupportedExplorerType::Blockscout => "blockscout",
                    SupportedExplorerType::Sourcify => "sourcify",
                    SupportedExplorerType::Oklink => "oklink",
                    SupportedExplorerType::Unknown => {
                        // This should never happen if the workflow is correct
                        panic!("Unknown explorer type should have been resolved by workflow");
                    }
                };

                command = command
                    .arg("--verify")
                    .arg(format!("--verifier={}", verifier))
                    .arg(format!("--verifier-url={}", explorer_api.api_url));

                // Only add API key if it's not empty
                if !explorer_api.api_key.is_empty() {
                    command = command.arg(format!("--verifier-api-key={}", explorer_api.api_key));
                }
            }

            match execute_command(command.arg("--broadcast").arg("--skip-simulation")) {
                Ok(result) => {
                    *execution_status.lock().unwrap() = ExecutionStatus::DeploymentCompleted;
                    if let Some(error_message) = result {
                        *execution_error_message.lock().unwrap() = error_message;
                    }
                }
                Err(e) => {
                    *execution_status.lock().unwrap() = ExecutionStatus::Failed;
                    *execution_error_message.lock().unwrap() = e.to_string();
                    return;
                }
            }

            // Read the task from pending file before deleting (STATE_MANAGER task may be empty)
            let task_file_path = get_config_dir(chain_id.clone()).join("task-pending.json");
            let task = match std::fs::read_to_string(&task_file_path) {
                Ok(contents) => serde_json::from_str(&contents).unwrap_or(Value::Null),
                Err(_) => Value::Null,
            };

            let _ = std::fs::remove_file(&task_file_path);

            // Build tag arguments for forge-chronicles by matching bytecode
            // Only processes protocols that have a "tag" field in the task JSON
            let artifacts = collect_tagged_artifacts(&working_dir, &task);
            let tag_args = if artifacts.is_empty() {
                Vec::new()
            } else {
                let transactions = get_broadcast_transactions(&working_dir, &chain_id);
                build_tag_args(&transactions, &artifacts)
            };

            let mut command = &mut Command::new("node");
            command = command
                .arg(working_dir.join("lib").join("forge-chronicles"))
                .arg("Deploy-all.s.sol")
                .arg("-c")
                .arg(chain_id.clone())
                .arg("--force");

            // Add tag arguments
            for tag in &tag_args {
                command = command.arg("--tag").arg(tag);
            }

            if !skip_verification && explorer.is_some() {
                command = command.arg("-e").arg(explorer.unwrap().url);
            }

            match execute_command(command) {
                Ok(result) => {
                    *execution_status.lock().unwrap() = ExecutionStatus::Success;
                    if let Some(error_message) = result {
                        *execution_error_message.lock().unwrap() = error_message;
                    }
                }
                Err(e) => {
                    *execution_status.lock().unwrap() = ExecutionStatus::Failed;
                    *execution_error_message.lock().unwrap() = e.to_string();
                }
            }
        });

        Ok(screen)
    }

    fn get_status_mark(&self, target_status: ExecutionStatus) -> char {
        if *self.execution_status.lock().unwrap() == target_status {
            get_spinner_frame()
        } else if *self.execution_status.lock().unwrap() < target_status {
            ' '
        } else {
            '✓'
        }
    }
}

fn execute_command(command: &mut Command) -> Result<Option<String>, Box<dyn std::error::Error>> {
    let cmd_str = format!("{:?}", command);
    let re = Regex::new(r"--private-key=0x[a-fA-F0-9]+").unwrap();
    let masked_cmd = re.replace_all(&cmd_str, "--private-key=***");
    crate::errors::log(format!("Executing command: {}", masked_cmd));
    let mut result = command
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()?;

    // Handle stdout
    let stdout = result.stdout.take().expect("Failed to capture stdout");
    let stdout_reader = std::io::BufReader::new(stdout);
    for line in stdout_reader.lines() {
        let line = line?;
        crate::errors::log(line);
    }

    // Handle stderr
    let stderr = result.stderr.take().expect("Failed to capture stderr");
    let stderr_reader = std::io::BufReader::new(stderr);
    let mut error_message = String::new();
    for line in stderr_reader.lines() {
        let line = line?;
        crate::errors::log(line.clone());
        error_message.push_str(&line);
        error_message.push('\n');
    }
    match result.wait() {
        Ok(status) => {
            if !status.success() {
                if error_message.contains("verify") || error_message.contains("verification") {
                    return Ok(Some("Verification of one or more contracts failed. Check the debug screen for more information".to_string()));
                } else {
                    return Err(error_message.into());
                }
            }
            Ok(None)
        }
        Err(e) => Err(e.to_string().into()),
    }
}

/// Transaction data from broadcast JSON
struct BroadcastTransaction {
    initcode: String,
    initcode_hash_stub: String,
}

/// Parse broadcast JSON and extract all transactions with their initcode hashes
fn get_broadcast_transactions(working_dir: &PathBuf, chain_id: &str) -> Vec<BroadcastTransaction> {
    let broadcast_path = working_dir
        .join("broadcast")
        .join("Deploy-all.s.sol")
        .join(chain_id)
        .join("run-latest.json");

    let contents = match std::fs::read_to_string(&broadcast_path) {
        Ok(c) => c,
        Err(e) => {
            crate::errors::log(format!(
                "Warning: Could not read broadcast JSON for tags: {}",
                e
            ));
            return Vec::new();
        }
    };

    let broadcast: Value = match serde_json::from_str(&contents) {
        Ok(v) => v,
        Err(e) => {
            crate::errors::log(format!(
                "Warning: Could not parse broadcast JSON for tags: {}",
                e
            ));
            return Vec::new();
        }
    };

    let mut transactions = Vec::new();
    if let Some(txs) = broadcast["transactions"].as_array() {
        for tx in txs {
            if let Some(input) = tx["transaction"]["input"].as_str() {
                let hash_stub = compute_initcode_hash_stub(input);
                if !hash_stub.is_empty() {
                    transactions.push(BroadcastTransaction {
                        initcode: input.to_string(),
                        initcode_hash_stub: hash_stub,
                    });
                }
            }
        }
    }
    transactions
}

/// Compute keccak256 of initcode and return first 8 hex chars (4 bytes)
fn compute_initcode_hash_stub(initcode: &str) -> String {
    let hex_str = initcode.strip_prefix("0x").unwrap_or(initcode);
    let bytes = match alloy::hex::decode(hex_str) {
        Ok(b) => b,
        Err(_) => return String::new(),
    };
    let hash = keccak256(&bytes);
    format!("{:x}", hash)[..8].to_string()
}

/// Artifact data: bytecode and associated tag
struct ArtifactInfo {
    bytecode: String, // without 0x prefix, lowercase
    tag: String,
}

/// Build list of artifact bytecodes with their tags
fn collect_tagged_artifacts(working_dir: &PathBuf, task: &Value) -> Vec<ArtifactInfo> {
    let mut artifacts = Vec::new();

    if let Some(protocols) = task["protocols"].as_object() {
        for (protocol_key, protocol) in protocols {
            let tag = match protocol["tag"].as_str() {
                Some(t) => t,
                None => continue,
            };

            if let Some(contracts) = protocol["contracts"].as_object() {
                for (contract_name, contract) in contracts {
                    if !contract["deploy"].as_bool().unwrap_or(false) {
                        continue;
                    }

                    // Find all artifacts for this contract name
                    for artifact_path in find_contract_artifacts(working_dir, contract_name) {
                        if let Ok(contents) = std::fs::read_to_string(&artifact_path) {
                            if let Ok(artifact) = serde_json::from_str::<Value>(&contents) {
                                // Check if artifact's source path matches this protocol
                                // The compilationTarget contains the source path like:
                                // "src/pkgs/universal-router/contracts/UniversalRouter.sol": "UniversalRouter"
                                // We need to match with path delimiters to avoid "universal-router" matching "universal-router-2_0"
                                let compilation_target = &artifact["metadata"]["settings"]["compilationTarget"];
                                let pattern = format!("/{}/", protocol_key);
                                let source_matches = compilation_target
                                    .as_object()
                                    .map(|obj| obj.keys().any(|k| k.contains(&pattern)))
                                    .unwrap_or(false);

                                if !source_matches {
                                    continue;
                                }

                                if let Some(bytecode) = artifact["bytecode"]["object"].as_str() {
                                    let bytecode = bytecode
                                        .strip_prefix("0x")
                                        .unwrap_or(bytecode)
                                        .to_lowercase();

                                    if !bytecode.is_empty() {
                                        artifacts.push(ArtifactInfo {
                                            bytecode,
                                            tag: tag.to_string(),
                                        });
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    artifacts
}

/// Find matching tag for a transaction by checking if its initcode contains any known bytecode
fn find_tag_for_transaction(initcode: &str, artifacts: &[ArtifactInfo]) -> Option<String> {
    let initcode = initcode
        .strip_prefix("0x")
        .unwrap_or(initcode)
        .to_lowercase();

    for artifact in artifacts {
        if initcode.contains(&artifact.bytecode) {
            return Some(artifact.tag.clone());
        }
    }
    None
}

/// Read the 'out' directory from foundry.toml, defaulting to "out"
fn get_foundry_out_dir(working_dir: &PathBuf) -> String {
    let foundry_toml = working_dir.join("foundry.toml");
    if let Ok(contents) = std::fs::read_to_string(&foundry_toml) {
        for line in contents.lines() {
            let line = line.trim();
            if line.starts_with("out") {
                if let Some(value) = line.split('=').nth(1) {
                    let value = value.trim().trim_matches('"').trim_matches('\'');
                    if !value.is_empty() {
                        return value.to_string();
                    }
                }
            }
        }
    }
    "out".to_string()
}

/// Recursively find all artifact files for a contract name in the out directory
fn find_contract_artifacts(working_dir: &PathBuf, contract_name: &str) -> Vec<PathBuf> {
    let out_dir = working_dir.join(get_foundry_out_dir(working_dir));
    let target_filename = format!("{}.json", contract_name);
    let mut artifacts = Vec::new();

    fn search_dir(dir: &PathBuf, target: &str, results: &mut Vec<PathBuf>) {
        if let Ok(entries) = std::fs::read_dir(dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.is_dir() {
                    search_dir(&path, target, results);
                } else if path.file_name().map(|n| n.to_string_lossy()) == Some(target.into()) {
                    results.push(path);
                }
            }
        }
    }

    search_dir(&out_dir, &target_filename, &mut artifacts);
    artifacts
}

/// Build tag arguments by checking if transaction initcode contains artifact bytecode
fn build_tag_args(transactions: &[BroadcastTransaction], artifacts: &[ArtifactInfo]) -> Vec<String> {
    let mut tag_args = Vec::new();
    let mut seen_hashes: std::collections::HashSet<String> = std::collections::HashSet::new();

    for tx in transactions {
        if let Some(tag) = find_tag_for_transaction(&tx.initcode, artifacts) {
            if seen_hashes.insert(tx.initcode_hash_stub.clone()) {
                tag_args.push(format!("{}:{}", tx.initcode_hash_stub, tag));
            }
        }
    }
    tag_args
}

impl Screen for ExecuteDeployScriptScreen {
    fn render_content(&self, buffer: &mut Buffer) -> Result<(), Box<dyn std::error::Error>> {
        if *self.execution_status.lock().unwrap() == ExecutionStatus::Failed {
            buffer.append_row_text(&format!(
                "Deployment failed: {}\n",
                self.execution_error_message.lock().unwrap()
            ));
            buffer.append_row_text_color("> Press any key to continue", constants::SELECTION_COLOR);
        } else {
            buffer.append_row_text(&format!(
                "{} Executing dry run\n",
                self.get_status_mark(ExecutionStatus::Pending)
            ));
            buffer.append_row_text(&format!(
                "{} Deploying contracts\n",
                self.get_status_mark(ExecutionStatus::DryRunCompleted)
            ));
            buffer.append_row_text(&format!(
                "{} Generating deployment logs\n",
                self.get_status_mark(ExecutionStatus::DeploymentCompleted)
            ));
            if *self.execution_status.lock().unwrap() == ExecutionStatus::Success {
                buffer.append_row_text("Deployment successful\n");
                let error_message = self.execution_error_message.lock().unwrap();
                if !error_message.is_empty() {
                    buffer.append_row_text(&error_message);
                }
                buffer.append_row_text_color(
                    "\n> Press any key to continue",
                    constants::SELECTION_COLOR,
                );
            }
            buffer.append_row_text_color(
                "\nUse CTRL+D to toggle debug mode and view console output.",
                constants::INSTRUCTIONS_COLOR,
            );
        }
        Ok(())
    }

    fn handle_input(&mut self, _: Event) -> Result<ScreenResult, Box<dyn std::error::Error>> {
        if *self.execution_status.lock().unwrap() == ExecutionStatus::Success {
            return Ok(ScreenResult::NextScreen(None));
        } else if *self.execution_status.lock().unwrap() == ExecutionStatus::Failed {
            return Ok(ScreenResult::Reset);
        }
        Ok(ScreenResult::Continue)
    }

    fn execute(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        Ok(())
    }
}
