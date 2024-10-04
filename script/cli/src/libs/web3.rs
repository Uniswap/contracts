use crate::state_manager::STATE_MANAGER;
use alloy::providers::{Provider, ProviderBuilder};
use eyre::Result;

pub struct Web3Lib {}

impl Web3Lib {
    pub fn new() -> Self {
        Web3Lib {}
    }

    pub async fn get_chain_id(&mut self) -> Result<String, Box<dyn std::error::Error + Send>> {
        let rpc_url = STATE_MANAGER.app_state.lock().unwrap().rpc_url.clone();

        if rpc_url.is_none() {
            return Err(Box::new(std::io::Error::new(
                std::io::ErrorKind::Other,
                "RPC URL not set",
            )) as Box<dyn std::error::Error + Send>);
        }

        // Create a provider with the HTTP transport using the `reqwest` crate.
        let provider = ProviderBuilder::new().on_http(rpc_url.unwrap().parse().unwrap());

        let chain_id = provider.get_chain_id().await;
        if chain_id.is_err() {
            return Err(Box::new(std::io::Error::new(
                std::io::ErrorKind::Other,
                "Failed to get chain id",
            )) as Box<dyn std::error::Error + Send>);
        }
        Ok(chain_id.unwrap().to_string())
    }
}
