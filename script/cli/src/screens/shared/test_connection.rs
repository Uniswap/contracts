use std::borrow::Borrow;

use crate::constants;
use crate::errors::ConnectionError;
use crate::libs::web3::Web3Lib;
use crate::screens::screen_manager::{Screen, ScreenResult};
use crate::screens::types::select::SelectComponent;
use crate::screens::types::text_input::TextInputComponent;
use crate::state_manager::STATE_MANAGER;
use crate::ui::{get_spinner_frame, Buffer};
use crossterm::event::Event;
use regex::Regex;
use std::io::Write;
use std::sync::{Arc, Mutex};

// Tests the connection to the rpc url, fails if the connection is not successful or the chain id doesn't match the expected chain id
// chain id and rpc url MUST be set before this screen is rendered
pub struct TestConnectionScreen {
    connection_status: Arc<Mutex<ConnectionStatus>>,
    connection_error_message: Arc<Mutex<String>>,
    rpc_url: String,
}

#[derive(PartialEq, Debug)]
enum ConnectionStatus {
    Pending,
    Success,
    Failed,
}

impl TestConnectionScreen {
    pub fn new() -> Self {
        let rpc_url = STATE_MANAGER
            .app_state
            .lock()
            .unwrap()
            .rpc_url
            .clone()
            .unwrap_or("".to_string());

        let test_connection_screen = TestConnectionScreen {
            connection_status: Arc::new(Mutex::new(ConnectionStatus::Pending)),
            connection_error_message: Arc::new(Mutex::new("".to_string())),
            rpc_url,
        };

        let mut web3_lib = Web3Lib::new();
        let connection_status = Arc::clone(&test_connection_screen.connection_status);
        let connection_error_message = Arc::clone(&test_connection_screen.connection_error_message);
        let expected_chain_id = STATE_MANAGER
            .app_state
            .lock()
            .unwrap()
            .chain_id
            .clone()
            .unwrap();

        // get chain id call in a new thread
        tokio::spawn(async move {
            let chain_id_result = web3_lib.get_chain_id().await;
            if chain_id_result.is_ok() {
                if chain_id_result.unwrap() == expected_chain_id {
                    *connection_status.lock().unwrap() = ConnectionStatus::Success;
                } else {
                    *connection_status.lock().unwrap() = ConnectionStatus::Failed;
                    *connection_error_message.lock().unwrap() = "Chain id mismatch".to_string();
                }
            } else {
                *connection_status.lock().unwrap() = ConnectionStatus::Failed;
                *connection_error_message.lock().unwrap() = "Connection failed".to_string();
            }
        });

        test_connection_screen
    }
}

impl Screen for TestConnectionScreen {
    fn render_content(&self, buffer: &mut Buffer) {
        if *self.connection_status.lock().unwrap() == ConnectionStatus::Pending {
            buffer.append_row_text(&format!("{} Testing connection\n", get_spinner_frame()));
            buffer.append_row_text(&format!("RPC URL: {}\n", self.rpc_url));
        } else if *self.connection_status.lock().unwrap() == ConnectionStatus::Success {
            buffer.append_row_text("Connection successful\n");
            buffer.append_row_text_color(
                &"> Press any key to continue\n",
                constants::SELECTION_COLOR,
            );
        } else if *self.connection_status.lock().unwrap() == ConnectionStatus::Failed {
            buffer.append_row_text("Connection failed\n");
            buffer.append_row_text(&format!(
                "Error: {}\n",
                self.connection_error_message.lock().unwrap().clone()
            ));
            buffer
                .append_row_text_color(&"> Press any key to try again", constants::SELECTION_COLOR);
        }
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

    fn execute(&mut self) {
        // nothing to execute
    }
}
