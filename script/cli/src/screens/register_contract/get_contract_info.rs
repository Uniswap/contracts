use crate::libs::explorer::ExplorerApiLib;
use crate::screens::screen_manager::{Screen, ScreenResult};
use crate::screens::types::select::SelectComponent;
use crate::state_manager::STATE_MANAGER;
use crate::ui::{get_spinner_frame, Buffer};
use crate::util::deployment_log::generate_deployment_log;
use alloy::primitives::Address;
use crossterm::event::Event;
use std::sync::{Arc, Mutex};

// Tests the connection to the rpc url, fails if the connection is not successful or the chain id doesn't match the expected chain id
// chain id and rpc url MUST be set before this screen is rendered
pub struct GetContractInfoScreen {
    execution_status: Arc<Mutex<ExecutionStatus>>,
    execution_error_message: Arc<Mutex<String>>,
    select: SelectComponent,
}

#[derive(PartialEq, Debug)]
enum ExecutionStatus {
    Pending,
    Success,
    Failed,
}

impl GetContractInfoScreen {
    pub fn new() -> Result<Self, Box<dyn std::error::Error>> {
        let screen = GetContractInfoScreen {
            select: SelectComponent::new(vec![
                "Enter another address".to_string(),
                "Exit".to_string(),
            ]),
            execution_status: Arc::new(Mutex::new(ExecutionStatus::Pending)),
            execution_error_message: Arc::new(Mutex::new(String::new())),
        };

        let chain_id = STATE_MANAGER
            .workflow_state
            .lock()?
            .chain_id
            .clone()
            .unwrap();

        let working_dir = STATE_MANAGER.working_directory.clone();

        let web3 = STATE_MANAGER.workflow_state.lock()?.web3.clone().unwrap();
        let execution_status = Arc::clone(&screen.execution_status);
        let execution_error_message = Arc::clone(&screen.execution_error_message);

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
            .register_contract_data
            .address
            .clone()
            .unwrap()
            .parse::<Address>()?;

        tokio::spawn(async move {
            match generate_deployment_log(
                contract_address,
                chain_id,
                working_dir,
                explorer_api,
                web3,
            )
            .await
            {
                Ok(_) => *execution_status.lock().unwrap() = ExecutionStatus::Success,
                Err(e) => {
                    *execution_status.lock().unwrap() = ExecutionStatus::Failed;
                    *execution_error_message.lock().unwrap() = e.to_string();
                }
            }
        });

        Ok(screen)
    }
}

impl Screen for GetContractInfoScreen {
    fn render_content(&self, buffer: &mut Buffer) -> Result<(), Box<dyn std::error::Error>> {
        if *self.execution_status.lock().unwrap() == ExecutionStatus::Pending {
            buffer.append_row_text(&format!(
                "{} Generating deployment data\n",
                get_spinner_frame()
            ));
        } else if *self.execution_status.lock().unwrap() == ExecutionStatus::Success {
            buffer.append_row_text("Deployment data generated successfully\n");
            self.select.render(buffer);
        }
        Ok(())
    }

    fn handle_input(&mut self, e: Event) -> Result<ScreenResult, Box<dyn std::error::Error>> {
        if *self.execution_status.lock().unwrap() == ExecutionStatus::Success {
            let result = self.select.handle_input(e);
            if result.is_some() {
                if result.unwrap() == 0 {
                    return Ok(ScreenResult::PreviousScreen);
                } else if result.unwrap() == 1 {
                    return Ok(ScreenResult::NextScreen(None));
                }
            }
        }

        Ok(ScreenResult::Continue)
    }

    fn execute(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        // TODO: add option to return to the previous screen (address entry screen) on failure?
        if *self.execution_status.lock().unwrap() == ExecutionStatus::Failed {
            return Err(self
                .execution_error_message
                .lock()
                .unwrap()
                .to_string()
                .into());
        }
        Ok(())
    }
}
