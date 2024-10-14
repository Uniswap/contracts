use crate::constants;
use crate::errors::ConnectionError;
use crate::libs::web3::Web3Lib;
use crate::screens::screen_manager::{Screen, ScreenResult};
use crate::state_manager::STATE_MANAGER;
use crate::ui::{get_spinner_frame, Buffer};
use crossterm::event::Event;
use std::sync::{Arc, Mutex};

// Tests the connection to the rpc url, fails if the connection is not successful or the chain id doesn't match the expected chain id
// chain id and rpc url MUST be set before this screen is rendered
pub struct GetContractInfoScreen {
    connection_status: Arc<Mutex<ConnectionStatus>>,
    connection_error_message: Arc<Mutex<String>>,
}

#[derive(PartialEq, Debug)]
enum ConnectionStatus {
    Pending,
    Success,
    Failed,
}

impl GetContractInfoScreen {
    pub fn new() -> Result<Self, Box<dyn std::error::Error>> {
        let test_connection_screen = GetContractInfoScreen {
            connection_status: Arc::new(Mutex::new(ConnectionStatus::Pending)),
            connection_error_message: Arc::new(Mutex::new("".to_string())),
        };

        let mut web3 = STATE_MANAGER.workflow_state.lock()?.web3.clone().unwrap();
        let connection_status = Arc::clone(&test_connection_screen.connection_status);
        let connection_error_message = Arc::clone(&test_connection_screen.connection_error_message);

        tokio::spawn(async move {
            let result = web3.get_chain_id().await;
            if result.is_ok() {
                *connection_status.lock().unwrap() = ConnectionStatus::Success;
            } else {
                *connection_status.lock().unwrap() = ConnectionStatus::Failed;
                *connection_error_message.lock().unwrap() = result.err().unwrap().to_string();
            }
        });

        Ok(test_connection_screen)
    }
}

impl Screen for GetContractInfoScreen {
    fn render_content(&self, buffer: &mut Buffer) -> Result<(), Box<dyn std::error::Error>> {
        if *self.connection_status.lock().unwrap() == ConnectionStatus::Pending {
            buffer.append_row_text(&format!(
                "{} Generating deployment data\n",
                get_spinner_frame()
            ));
        } else if *self.connection_status.lock().unwrap() == ConnectionStatus::Success {
            buffer.append_row_text("Deployment data generated successfully\n");
            buffer
                .append_row_text_color(&"> Press any key to continue", constants::SELECTION_COLOR);
        } else if *self.connection_status.lock().unwrap() == ConnectionStatus::Failed {
            buffer.append_row_text("An error occurred\n");
            buffer.append_row_text(&format!(
                "Error: {}\n",
                self.connection_error_message.lock().unwrap().clone()
            ));
            buffer
                .append_row_text_color(&"> Press any key to try again", constants::SELECTION_COLOR);
        }
        Ok(())
    }

    fn handle_input(&mut self, _: Event) -> Result<ScreenResult, Box<dyn std::error::Error>> {
        if *self.connection_status.lock().unwrap() == ConnectionStatus::Success {
            // continue to the next screen
            return Ok(ScreenResult::NextScreen(None));
        } else if *self.connection_status.lock().unwrap() == ConnectionStatus::Failed {
            // abort the workflow
            return Err(Box::new(ConnectionError(
                self.connection_error_message.lock().unwrap().clone(),
            )));
        }

        Ok(ScreenResult::Continue)
    }

    fn execute(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        Ok(())
    }
}
