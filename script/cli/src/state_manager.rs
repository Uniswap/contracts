use crate::util::chain_config::{parse_chain_config, Chain, Explorer};
use crate::util::register_contract::RegisterContractData;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Mutex;

// The state manager is responsible for managing the state of the application. All screens and workflows share the same state and use the singleton instance to read and write to the state.
pub struct AppState {
    pub chain_id: Option<String>,
    pub rpc_url: Option<String>,
    pub block_explorer: Option<Explorer>,
    pub working_directory: PathBuf,
    pub register_contract_data: RegisterContractData,
    // pub deployment_history: HashMap<String, String>,
}

impl AppState {
    pub fn new() -> Self {
        AppState {
            chain_id: None,
            rpc_url: None,
            working_directory: PathBuf::from(""),
            // deployment_history: HashMap::new(),
            block_explorer: None,
            register_contract_data: RegisterContractData { address: None },
        }
    }

    pub fn set_chain_id(&mut self, chain_id: String) {
        self.chain_id = Some(chain_id);
    }

    pub fn set_rpc_url(&mut self, rpc_url: Option<String>) {
        self.rpc_url = rpc_url;
    }

    pub fn reset(&mut self) {
        *self = AppState::new();
    }
}

pub struct StateManager {
    pub app_state: Mutex<AppState>,
    pub chains: HashMap<String, Chain>,
}

impl StateManager {
    pub fn new() -> Self {
        StateManager {
            app_state: Mutex::new(AppState::new()),
            chains: parse_chain_config(),
        }
    }

    pub fn get_chain(&self, chain_id: String) -> Option<&Chain> {
        self.chains.get(&chain_id)
    }
}

// Create a global instance of StateManager
lazy_static::lazy_static! {
    pub static ref STATE_MANAGER: StateManager = StateManager::new();
}
