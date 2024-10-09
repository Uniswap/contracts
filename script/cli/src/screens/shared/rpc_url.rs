use std::borrow::Borrow;

use crate::constants;
use crate::errors::ConnectionError;
use crate::libs::web3::Web3Lib;
use crate::screens::screen_manager::{Screen, ScreenResult};
use crate::screens::types::select::SelectScreen;
use crate::screens::types::text_input::TextInputScreen;
use crate::state_manager::STATE_MANAGER;
use crate::ui::{get_spinner_frame, Buffer};
use crossterm::event::Event;
use regex::Regex;
use std::io::Write;
use std::sync::{Arc, Mutex};

// Sets the rpc url for further operations
// If there are default options, show to the user to select one, user has an option to enter manually
// If there are no default options, user is prompted to enter the rpc url manually automatically
// After the rpc url is set, check whether the url contains a placeholder for an environment variable
// If it does, check a .env file for the variable first, if not found, check the system environment variables
// If the variable is found, prompt the user to confirm whether to use it
// If the user denies or the variable is not found, they are prompted to enter the variable manually
// After the variable is entered, offer the user to save the variable to the .env file
// After the rpc url + optional environment variable is set, test the connection by getting the chain id
// If the chain id matches the entered chain id from the previous step, the connection is successful, return to workflow
// If the chain id does not match or the connection fails, display an error and move to the home screen
pub struct RpcUrlScreen {
    rpc_input: TextInputScreen,
    env_var_input: TextInputScreen,
    rpc_list: SelectScreen,
    env_save: SelectScreen,
    env_confirm: SelectScreen,
    current_step: Step,
    selected_rpc: String,
    env_var_name: String,
    env_var: String,
    connection_status: Arc<Mutex<ConnectionStatus>>,
    connection_error_message: Arc<Mutex<String>>,
}

#[derive(PartialEq, Debug)]
enum Step {
    EnterManually,
    SelectFromList,
    EnterEnvVar,
    SaveEnvVar,
    ConfirmEnvVar,
    TestConnection,
}

#[derive(PartialEq, Debug)]
enum ConnectionStatus {
    New,
    Pending,
    Success,
    Failed,
}

impl RpcUrlScreen {
    pub fn new() -> Self {
        let mut current_step = Step::EnterManually;
        let chain_id = STATE_MANAGER.app_state.lock().unwrap().chain_id.clone();
        let mut pre_selected_rpcs = vec![];
        if chain_id.is_some()
            && STATE_MANAGER
                .chains
                .contains_key(&chain_id.clone().unwrap())
        {
            pre_selected_rpcs = STATE_MANAGER
                .chains
                .get(&chain_id.unwrap())
                .unwrap()
                .rpc_url
                .clone();
            pre_selected_rpcs.push("Enter manually".to_string());
            current_step = Step::SelectFromList;
        }
        RpcUrlScreen {
            rpc_input: TextInputScreen::new(false, |input| input),
            env_var_input: TextInputScreen::new(false, |input| input),
            rpc_list: SelectScreen::new(pre_selected_rpcs),
            env_save: SelectScreen::new(vec!["Yes".to_string(), "No".to_string()]),
            env_confirm: SelectScreen::new(vec!["Yes".to_string(), "No".to_string()]),
            current_step,
            selected_rpc: "".to_string(),
            env_var: "".to_string(),
            env_var_name: "".to_string(),
            connection_status: Arc::new(Mutex::new(ConnectionStatus::New)),
            connection_error_message: Arc::new(Mutex::new("".to_string())),
        }
    }

    fn set_rpc_url(&mut self, rpc_url: String) {
        self.selected_rpc = rpc_url;
        // if the rpc url is set and contains an environment variable, first attempt to read it from the system environment, if it is not set, check the .env file next. If it is not found, prompt the user to enter it manually.
        if let Some(captures) = Regex::new(r"\$\{([^}]+)\}")
            .unwrap()
            .captures(&self.selected_rpc)
        {
            if let Some(env_var_name) = captures.get(1) {
                // found an environment variable in the rpc url
                // read from file first, if not found, read from system environment
                self.env_var_name = env_var_name.as_str().to_string();
                self.env_var = find_in_env_file(&self.env_var_name).unwrap_or("".to_string());

                if !self.env_var.is_empty() {
                    // found in .env file
                    self.current_step = Step::ConfirmEnvVar;
                } else {
                    // not found in file, check system environment
                    let env_var = std::env::var(&self.env_var_name);
                    if env_var.is_ok() && !env_var.clone().unwrap().is_empty() {
                        // found in .env file
                        self.env_var = env_var.unwrap();
                        self.current_step = Step::ConfirmEnvVar;
                    } else {
                        // not found in .env file, prompt user to enter it manually
                        self.current_step = Step::EnterEnvVar;
                    }
                }
            } else {
                // no environment variable found in the rpc url
                self.current_step = Step::TestConnection;
            }
        } else {
            // no environment variable found in the rpc url
            self.current_step = Step::TestConnection;
        }
    }
}

impl Screen for RpcUrlScreen {
    fn render_content(&self, buffer: &mut Buffer) {
        if self.current_step == Step::SelectFromList {
            buffer.append_row_text("Select RPC URL\n");
            self.rpc_list.render(buffer);
            self.rpc_list.render_default_instructions(buffer);
        } else if self.current_step == Step::EnterManually {
            buffer.append_row_text("Enter RPC URL\n");
            self.rpc_input.render(buffer);
            self.rpc_input.render_default_instructions(buffer);
        } else if self.current_step == Step::EnterEnvVar {
            buffer.append_row_text(&format!("Enter {} variable\n", self.env_var_name));
            self.env_var_input.render(buffer);
            self.env_var_input.render_default_instructions(buffer);
        } else if self.current_step == Step::SaveEnvVar {
            buffer.append_row_text(&format!(
                "Do you want to save this environment variable?\n\n{}: {}\n",
                self.env_var_name, self.env_var
            ));
            self.env_save.render(buffer);
            self.env_save.render_default_instructions(buffer);
        } else if self.current_step == Step::ConfirmEnvVar {
            buffer.append_row_text(&format!(
                "Environment variable found:\n\n{}: {}\n\nDo you want to use it?\n",
                self.env_var_name, self.env_var
            ));
            self.env_confirm.render(buffer);
            self.env_confirm.render_default_instructions(buffer);
        } else if self.current_step == Step::TestConnection {
            if *self.connection_status.lock().unwrap() == ConnectionStatus::Pending {
                buffer.append_row_text(&format!("{} Testing connection\n", get_spinner_frame()));
                buffer.append_row_text(&format!("RPC URL: {}\n", self.selected_rpc));
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
                buffer.append_row_text_color(
                    &"> Press any key to try again",
                    constants::SELECTION_COLOR,
                );
            }
        }
    }

    fn handle_input(&mut self, event: Event) -> Result<ScreenResult, Box<dyn std::error::Error>> {
        // if there are no default options or the user has selected to enter the rpc manually, render the rpc input
        if self.current_step == Step::EnterManually {
            let rpc_url = self.rpc_input.handle_input(event.clone());
            if rpc_url != None && !rpc_url.clone().unwrap().is_empty() {
                self.set_rpc_url(rpc_url.unwrap());
            }
        }
        // if there are default options, render the rpc selection
        else if self.current_step == Step::SelectFromList {
            let index = self.rpc_list.handle_input(event.clone());
            if index.borrow().is_some() {
                if index.unwrap() == self.rpc_list.options.len() - 1 {
                    self.current_step = Step::EnterManually;
                } else {
                    self.set_rpc_url(self.rpc_list.options[index.unwrap()].clone());
                }
            }
        } else if self.current_step == Step::EnterEnvVar {
            let env_var = self.env_var_input.handle_input(event.clone());
            if env_var != None && !env_var.clone().unwrap().is_empty() {
                self.env_var = env_var.unwrap();
                self.current_step = Step::SaveEnvVar;
            }
        } else if self.current_step == Step::SaveEnvVar {
            let index = self.env_save.handle_input(event.clone());
            if index.borrow().is_some() {
                self.selected_rpc =
                    replace_env_var(&self.selected_rpc, &self.env_var_name, &self.env_var);
                if index.unwrap() == 0 {
                    save_env_var(&self.env_var_name, &self.env_var);
                }
                self.current_step = Step::TestConnection;
            }
        } else if self.current_step == Step::ConfirmEnvVar {
            let index = self.env_confirm.handle_input(event.clone());
            if index.borrow().is_some() {
                if index.unwrap() == 0 {
                    self.selected_rpc =
                        replace_env_var(&self.selected_rpc, &self.env_var_name, &self.env_var);
                    self.current_step = Step::TestConnection;
                } else {
                    self.env_var = "".to_string();
                    self.current_step = Step::EnterEnvVar;
                }
            }
        } else if self.current_step == Step::TestConnection {
            if *self.connection_status.lock().unwrap() == ConnectionStatus::Success {
                // continue to the next screen
                return Ok(ScreenResult::NextScreen(None));
            } else if *self.connection_status.lock().unwrap() == ConnectionStatus::Failed {
                // abort the workflow
                return Err(Box::new(ConnectionError(
                    self.connection_error_message.lock().unwrap().clone(),
                )));
            }
        }

        Ok(ScreenResult::Continue)
    }

    fn execute(&mut self) {
        if self.current_step == Step::TestConnection
            && *self.connection_status.lock().unwrap() == ConnectionStatus::New
        {
            STATE_MANAGER
                .app_state
                .lock()
                .unwrap()
                .set_rpc_url(Some(self.selected_rpc.clone()));
            *self.connection_status.lock().unwrap() = ConnectionStatus::Pending;
            let mut web3_lib = Web3Lib::new();

            let connection_status = Arc::clone(&self.connection_status);
            let connection_error_message = Arc::clone(&self.connection_error_message);
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
        }
    }
}

fn replace_env_var(rpc_url: &str, env_var_name: &str, env_var: &str) -> String {
    // replace the ${env_var_name} in the rpc_url with the env_var
    let re = Regex::new(&format!(r"\$\{{{}}}", env_var_name)).unwrap();
    re.replace(rpc_url, env_var).to_string()
}

fn find_in_env_file(env_var_name: &str) -> Option<String> {
    if let Ok(env_content) = std::fs::read_to_string(".env") {
        for line in env_content.lines() {
            if let Some((key, value)) = line.split_once('=') {
                if key.trim() == env_var_name {
                    return Some(value.trim().to_string());
                }
            }
        }
    }
    None
}

fn save_env_var(env_var_name: &str, env_var: &str) {
    // if the env_var_name already exists, try replacing it with the new value
    if !std::path::Path::new(".env").exists() {
        // Create .env file if it doesn't exist
        std::fs::File::create(".env").unwrap();
    } else {
        // file does not exist, search for the env_var_name
        let env_content = std::fs::read_to_string(".env").unwrap();
        let pattern = format!(r"(?m)^{}=.*$", regex::escape(env_var_name));
        let replaced_env_content = Regex::new(&pattern)
            .unwrap()
            .replace_all(&env_content, format!("{}={}", env_var_name, env_var))
            .to_string();
        // the strings are different so the env_var was replaced, write file and return
        if replaced_env_content != env_content {
            std::fs::write(".env", replaced_env_content).unwrap();
            return;
        }
    }
    // if env_var_name does not exist, add it to the end of the file
    let env_content = format!("{}={}\n", env_var_name, env_var);
    std::fs::OpenOptions::new()
        .append(true)
        .open(".env")
        .unwrap()
        .write_all(env_content.as_bytes())
        .unwrap();
}
