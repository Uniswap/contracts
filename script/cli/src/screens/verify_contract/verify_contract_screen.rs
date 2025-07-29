use crate::libs::explorer::{ExplorerApiLib, SupportedExplorerType};
use crate::screens::screen_manager::{Screen, ScreenResult};
use crate::screens::types::select::SelectComponent;
use crate::state_manager::STATE_MANAGER;
use crate::ui::{get_spinner_frame, Buffer};
use alloy::primitives::Address;
use crossterm::event::Event;
use regex::Regex;
use std::io::BufRead;
use std::process::Command;
use std::sync::{Arc, Mutex};

pub struct VerifyContractData {
    pub address: Option<String>,
}

pub struct VerifyContractScreen {
    execution_status: Arc<Mutex<ExecutionStatus>>,
    execution_message: Arc<Mutex<String>>,
    select: SelectComponent,
}

#[derive(PartialEq, Debug)]
enum ExecutionStatus {
    Pending,
    Success,
    Failed,
}

impl VerifyContractScreen {
    pub fn new() -> Result<Self, Box<dyn std::error::Error>> {
        let screen = VerifyContractScreen {
            select: SelectComponent::new(vec![
                "Enter another address".to_string(),
                "Exit".to_string(),
            ]),
            execution_status: Arc::new(Mutex::new(ExecutionStatus::Pending)),
            execution_message: Arc::new(Mutex::new(String::new())),
        };

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

        let execution_status = Arc::clone(&screen.execution_status);
        let execution_message = Arc::clone(&screen.execution_message);

        let explorer = STATE_MANAGER
            .workflow_state
            .lock()?
            .block_explorer
            .clone()
            .unwrap();

        let explorer_api_key = STATE_MANAGER
            .workflow_state
            .lock()?
            .explorer_api_key
            .clone()
            .unwrap();

        let explorer_api = ExplorerApiLib::new(explorer, explorer_api_key)?;

        let contract_address = STATE_MANAGER
            .workflow_state
            .lock()?
            .verify_contract_data
            .address
            .clone()
            .unwrap()
            .parse::<Address>()?;

        tokio::spawn(async move {
            let mut command = &mut Command::new("forge");
            command = command
                .arg("verify-contract")
                .arg(format!("--chain={}", chain_id))
                .arg(format!("--rpc-url={}", rpc_url))
                .arg("-vvvv")
                .arg("--watch")
                .arg(format!(
                    "--verifier={}",
                    if explorer_api.explorer.explorer_type == SupportedExplorerType::Blockscout {
                        "blockscout"
                    } else if explorer_api.explorer.explorer_type == SupportedExplorerType::EtherscanV2 {
                        "etherscan"
                    } else {
                        // custom also works for etherscan
                        "custom"
                    }
                ))
                .arg(format!("--verifier-url={}", explorer_api.api_url))
                .arg(format!("--verifier-api-key={}", explorer_api.api_key))
                .arg("--guess-constructor-args")
                .arg(format!("{}", contract_address));

            match execute_command(&mut command) {
                Ok(_) => {
                    *execution_status.lock().unwrap() = ExecutionStatus::Success;
                    *execution_message.lock().unwrap() = "".to_string();
                }
                Err(e) => {
                    *execution_status.lock().unwrap() = ExecutionStatus::Failed;
                    *execution_message.lock().unwrap() = e.to_string();
                }
            }
        });

        Ok(screen)
    }
}

impl Screen for VerifyContractScreen {
    fn render_content(&self, buffer: &mut Buffer) -> Result<(), Box<dyn std::error::Error>> {
        if *self.execution_status.lock().unwrap() == ExecutionStatus::Pending {
            buffer.append_row_text(&format!("{} Verifying contract\n", get_spinner_frame()));
        } else if *self.execution_status.lock().unwrap() == ExecutionStatus::Success {
            buffer.append_row_text(&format!("Contract verified successfully\n"));
            self.select.render(buffer);
        } else if *self.execution_status.lock().unwrap() == ExecutionStatus::Failed {
            buffer.append_row_text(&format!(
                "Error verifying contract: {}\n",
                self.execution_message.lock().unwrap()
            ));
            self.select.render(buffer);
        }
        Ok(())
    }

    fn handle_input(&mut self, e: Event) -> Result<ScreenResult, Box<dyn std::error::Error>> {
        if *self.execution_status.lock().unwrap() != ExecutionStatus::Pending {
            let result = self.select.handle_input(e);
            if let Some(result) = result {
                if result == 0 {
                    return Ok(ScreenResult::PreviousScreen);
                } else if result == 1 {
                    return Ok(ScreenResult::NextScreen(None));
                }
            }
        }

        Ok(ScreenResult::Continue)
    }

    fn execute(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        Ok(())
    }
}

fn execute_command(command: &mut Command) -> Result<Option<String>, Box<dyn std::error::Error>> {
    let cmd_str = format!("{:?}", command);
    let re = Regex::new(r"--verifier-api-key=\S*").unwrap();
    let masked_cmd = re.replace_all(&cmd_str, "--verifier-api-key=***");
    let masked_cmd = masked_cmd.replace("\"", "");
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
                return Err(error_message.into());
            }
            Ok(None)
        }
        Err(e) => Err(e.to_string().into()),
    }
}
