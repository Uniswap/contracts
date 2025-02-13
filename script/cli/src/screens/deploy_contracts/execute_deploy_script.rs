use crate::constants;
use crate::libs::explorer::{ExplorerApiLib, SupportedExplorerType};
use crate::screens::screen_manager::{Screen, ScreenResult};
use crate::state_manager::STATE_MANAGER;
use crate::ui::{get_spinner_frame, Buffer};
use crate::util::deploy_config_lib::get_config_dir;
use crossterm::event::Event;
use regex::Regex;
use std::io::BufRead;
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

            if explorer.is_some() && explorer_api_key.is_some() {
                let explorer_api =
                    ExplorerApiLib::new(explorer.clone().unwrap(), explorer_api_key.unwrap())
                        .unwrap();
                command = command
                    .arg("--verify")
                    .arg(format!(
                        "--verifier={}",
                        if explorer_api.explorer.explorer_type == SupportedExplorerType::Blockscout
                        {
                            "blockscout"
                        } else {
                            // custom also works for etherscan
                            "custom"
                        }
                    ))
                    .arg(format!("--verifier-url={}", explorer_api.api_url))
                    .arg(format!("--verifier-api-key={}", explorer_api.api_key));
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

            let _ =
                std::fs::remove_file(get_config_dir(chain_id.clone()).join("task-pending.json"));

            let mut command = &mut Command::new("node");
            command = command
                .arg(working_dir.join("lib").join("forge-chronicles"))
                .arg("Deploy-all.s.sol")
                .arg("-c")
                .arg(chain_id.clone())
                .arg("--force");

            if explorer.is_some() {
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
