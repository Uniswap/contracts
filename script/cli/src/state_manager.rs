use crate::libs::explorer::{Explorer, SupportedExplorerType};
use crate::libs::web3::Web3Lib;
use crate::util::chain_config::{parse_chain_config, Chain, Explorer};
use crate::util::deployment_log::RegisterContractData;
use crossterm::{
    cursor::Show,
    execute,
    terminal::{disable_raw_mode, is_raw_mode_enabled, LeaveAlternateScreen},
    Result,
};
use serde_json::Value;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Mutex;
use std::{
    env,
    io::{stdout, Write},
    process,
};

// The state manager is responsible for managing the state of the application. All screens and workflows share the same state and use the singleton instance to read and write to the state.
pub struct WorkflowState {
    pub debug_mode: bool,
    pub chain_id: Option<String>,
    pub web3: Option<Web3Lib>,
    pub explorer_api_key: Option<String>,
    pub block_explorer: Option<Explorer>,
    pub register_contract_data: RegisterContractData,
    pub verify_contract_data: VerifyContractData,
    pub task: Value,
    pub private_key: Option<String>,
}

impl WorkflowState {
    pub fn new() -> Self {
        WorkflowState {
            debug_mode: false,
            chain_id: None,
            web3: None,
            explorer_api_key: None,
            block_explorer: None,
            register_contract_data: RegisterContractData { address: None },
            verify_contract_data: VerifyContractData { address: None },
            task: serde_json::json!({}),
            private_key: None,
        }
    }

    pub fn reset(&mut self) {
        *self = WorkflowState::new();
    }
}

pub struct StateManager {
    pub chains: HashMap<String, Chain>,
    pub working_directory: PathBuf,
    pub workflow_state: Mutex<WorkflowState>,
}

impl StateManager {
    pub fn new() -> Self {
        StateManager {
            chains: parse_chain_config(),
            working_directory: check_for_foundry_toml(),
            workflow_state: Mutex::new(WorkflowState::new()),
        }
    }

    pub fn get_chain(&self, chain_id: String) -> Option<Chain> {
        let mut chain = self.chains.get(&chain_id).cloned();

        // Manual override for Zora and Ink due to incorrect config
        if chain_id == "7777777" || chain_id == "57073" {
            if let Some(ref mut chain_data) = chain {
                if chain_data.explorers.len() == 1 {
                    chain_data.explorers[0].explorer_type = SupportedExplorerType::Blockscout;
                }
            }
        }
        chain
    }
}

// Create a global instance of StateManager
lazy_static::lazy_static! {
    pub static ref STATE_MANAGER: StateManager = StateManager::new();
}

pub fn clean_terminal() -> Result<()> {
    let mut stdout = stdout();
    if is_raw_mode_enabled().unwrap() {
        stdout.flush()?;
        let result = disable_raw_mode();
        execute!(stdout, LeaveAlternateScreen, Show,)?;
        result
    } else {
        Ok(())
    }
}

fn check_for_foundry_toml() -> PathBuf {
    // check if foundry.toml file exists in the current directory
    let mut current_dir = env::current_dir().unwrap();
    let default_dir = current_dir.clone();
    if !default_dir.join("foundry.toml").exists() {
        // check for constructor argument: --dir <directory>
        let args: Vec<String> = env::args().collect();
        if args.len() > 2 && args[1] == "--dir" {
            let dir = &args[2];
            current_dir = current_dir.join(dir);
            if !current_dir.join("foundry.toml").exists() {
                let _ = clean_terminal();
                println!("{} does not exist.", current_dir.to_str().unwrap());
                process::exit(1);
            }
        } else {
            let _ = clean_terminal();
            println!("No foundry.toml file found in the current directory. Use the --dir <directory> argument to provide a relative path to your foundry directory containing the foundry.toml file. Example: ./deploy-cli --dir ../path/to/your/foundry_project");
            process::exit(1);
        }
    } else {
        current_dir = default_dir;
    }

    current_dir
}
