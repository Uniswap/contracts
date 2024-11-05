use crate::libs::explorer::{ExplorerApiLib, SupportedExplorerType};
use crate::screens::screen_manager::{Screen, ScreenResult};
use crate::state_manager::STATE_MANAGER;
use crate::ui::{get_spinner_frame, Buffer};
use crossterm::event::Event;
use std::process::Command;
use std::sync::{Arc, Mutex};

pub struct ExecuteDeployScriptScreen {
    execution_status: Arc<Mutex<ExecutionStatus>>,
    execution_error_message: Arc<Mutex<String>>,
}

#[derive(PartialEq, Debug)]
enum ExecutionStatus {
    Pending,
    Success,
    Failed,
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
                .arg(format!("--private-key={}", private_key));
            if explorer.is_some() && explorer_api_key.is_some() {
                let explorer_api =
                    ExplorerApiLib::new(explorer.unwrap(), explorer_api_key.unwrap()).unwrap();
                command = command
                    .arg("--verify")
                    .arg(format!(
                        "--verifier={}",
                        if explorer_api.explorer_type == SupportedExplorerType::Blockscout {
                            "blockscout"
                        } else {
                            "etherscan"
                        }
                    ))
                    .arg(format!("--verifier-url={}", explorer_api.api_url))
                    .arg(format!("--api-key={}", explorer_api.api_key));
            }

            let output = command
                .arg("--broadcast")
                .arg("-vvv")
                .stdout(std::process::Stdio::piped())
                .output()
                .expect("Failed to execute forge script");
            crate::errors::log(format!(
                "Process finished with output:\n\n{}\n",
                String::from_utf8(output.stdout)
                    .unwrap()
                    .replace("\\n", "\n")
                    .replace("\\t", "\t")
                    .replace("\\\"", "\"")
            ));
        });

        Ok(screen)
    }
}

impl Screen for ExecuteDeployScriptScreen {
    fn render_content(&self, buffer: &mut Buffer) -> Result<(), Box<dyn std::error::Error>> {
        if *self.execution_status.lock().unwrap() == ExecutionStatus::Pending {
            buffer.append_row_text(&format!("{} Deploying contracts\n", get_spinner_frame()));
        } else if *self.execution_status.lock().unwrap() == ExecutionStatus::Success {
            buffer.append_row_text("Deployment data generated successfully\n");
            // self.select.render(buffer);
        }
        Ok(())
    }

    fn handle_input(&mut self, e: Event) -> Result<ScreenResult, Box<dyn std::error::Error>> {
        // if *self.execution_status.lock().unwrap() == ExecutionStatus::Success {
        // let result = self.select.handle_input(e);
        // if result.is_some() {
        //     if result.unwrap() == 0 {
        //         return Ok(ScreenResult::PreviousScreen);
        //     } else if result.unwrap() == 1 {
        //         return Ok(ScreenResult::NextScreen(None));
        //     }
        // }
        // }

        Ok(ScreenResult::Continue)
    }

    fn execute(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        // TODO: add option to return to the previous screen (address entry screen) on failure?
        // if *self.execution_status.lock().unwrap() == ExecutionStatus::Failed {
        //     return Err(self
        //         .execution_error_message
        //         .lock()
        //         .unwrap()
        //         .to_string()
        //         .into());
        // }
        Ok(())
    }
}
