use crate::{errors::log, state_manager::STATE_MANAGER};
use alloy::{
    json_abi::{Constructor, JsonAbi},
    primitives::Address,
};

#[derive(Clone, PartialEq, Eq, Default)]
pub enum SupportedExplorerType {
    #[default]
    Unknown,     // Ambiguous - requires user selection
    EtherscanV2,
    Blockscout,
    Sourcify,
    Oklink,
}

#[derive(Default, Clone)]
pub struct Explorer {
    pub name: String,
    pub url: String,
    pub standard: String,
    pub explorer_type: SupportedExplorerType,
    pub sourcify_api_url: Option<String>,
    pub oklink_api_url: Option<String>,
}

#[derive(Default, Clone)]
pub struct ExplorerApiLib {
    pub explorer: Explorer,
    pub api_key: String,
    pub api_url: String,
}

impl ExplorerApiLib {
    pub fn new(explorer: Explorer, api_key: String) -> Result<Self, Box<dyn std::error::Error>> {
        let api_url = match explorer.explorer_type {
            SupportedExplorerType::EtherscanV2 => {
                let chain_id = STATE_MANAGER
                    .workflow_state
                    .lock()
                    .unwrap()
                    .chain_id
                    .clone()
                    .ok_or("Chain ID not found")?;
                format!("https://api.etherscan.io/v2/api?chainid={}", chain_id)
            }
            SupportedExplorerType::Blockscout => {
                format!("{}/api?", explorer.url)
            }
            SupportedExplorerType::Sourcify => {
                explorer
                    .sourcify_api_url
                    .clone()
                    .ok_or("Sourcify API URL required")?
            }
            SupportedExplorerType::Oklink => {
                explorer
                    .oklink_api_url
                    .clone()
                    .ok_or("OKLink API URL required")?
            }
            SupportedExplorerType::Unknown => {
                return Err(format!(
                    "Explorer type must be selected before creating API lib: {} ({})",
                    explorer.name, explorer.url
                ).into());
            }
        };

        Ok(ExplorerApiLib {
            explorer,
            api_key,
            api_url,
        })
    }

    pub async fn get_contract_data(
        &self,
        contract_address: Address,
    ) -> Result<(String, String, Option<Constructor>), Box<dyn std::error::Error>> {
        if self.explorer.explorer_type == SupportedExplorerType::EtherscanV2
            || self.explorer.explorer_type == SupportedExplorerType::Blockscout
        {
            let url = format!(
                "{}&module=contract&action=getsourcecode&address={}&apikey={}",
                self.api_url, contract_address, self.api_key
            );
            match get_etherscan_result(&url).await {
                Ok(result) => {
                    if let (Some(contract_name), Some(abi)) =
                        (result["ContractName"].as_str(), result["ABI"].as_str())
                    {
                        let constructor_arguments = result["ConstructorArguments"]
                            .as_str()
                            .unwrap_or("")
                            .to_string();
                        return Ok((
                            contract_name.to_string(),
                            constructor_arguments,
                            get_constructor_inputs(abi)?,
                        ));
                    } else {
                        return Err("Explorer Error: ContractName not found in the response from the explorer api.".to_string()
                        .into());
                    }
                }
                Err(e) => {
                    return Err(e);
                }
            }
        }
        Err(format!(
            "Unsupported explorer: {} ({})",
            self.explorer.name, self.explorer.url,
        )
        .into())
    }

    pub async fn get_creation_transaction_hash(
        &self,
        contract_address: Address,
    ) -> Result<String, Box<dyn std::error::Error>> {
        if self.explorer.explorer_type == SupportedExplorerType::EtherscanV2
            || self.explorer.explorer_type == SupportedExplorerType::Blockscout
        {
            let url = format!(
                "{}&module=contract&action=getcontractcreation&contractaddresses={}&apikey={}",
                self.api_url, contract_address, self.api_key
            );
            let tx_hash = get_etherscan_result(&url).await?["txHash"]
                .as_str()
                .unwrap()
                .to_string();
            return Ok(tx_hash);
        }
        Err(format!(
            "Unsupported explorer: {} ({})",
            self.explorer.name, self.explorer.url,
        )
        .into())
    }
}

impl SupportedExplorerType {
    pub fn to_env_var_name(&self, chain_id: &str) -> String {
        match self {
            SupportedExplorerType::Unknown => {
                // Unknown type - fallback to generic key
                format!("VERIFIER_API_KEY_{}", chain_id)
            }
            SupportedExplorerType::EtherscanV2 => {
                // Etherscan v2 API key is shared across all chains
                "ETHERSCAN_API_KEY".to_string()
            }
            SupportedExplorerType::Blockscout => {
                // Chain-specific Blockscout keys to avoid cross-chain reuse
                format!("BLOCKSCOUT_API_KEY_{}", chain_id)
            }
            SupportedExplorerType::Sourcify => {
                // Chain-specific Sourcify keys to avoid cross-chain reuse
                format!("SOURCIFY_API_KEY_{}", chain_id)
            }
            SupportedExplorerType::Oklink => {
                // Chain-specific OKLink keys to avoid cross-chain reuse
                format!("OKLINK_API_KEY_{}", chain_id)
            }
        }
    }

    pub fn name(&self) -> String {
        match self {
            SupportedExplorerType::Unknown => "Unknown".to_string(),
            SupportedExplorerType::EtherscanV2 => "Etherscan v2".to_string(),
            SupportedExplorerType::Blockscout => "Blockscout".to_string(),
            SupportedExplorerType::Sourcify => "Sourcify".to_string(),
            SupportedExplorerType::Oklink => "OKLink".to_string(),
        }
    }
}

async fn get_etherscan_result(url: &str) -> Result<serde_json::Value, Box<dyn std::error::Error>> {
    match reqwest::get(url).await {
        Ok(response) => {
            let response_text = response.text().await?;
            let json_response: serde_json::Value = match serde_json::from_str(&response_text) {
                Ok(json) => json,
                Err(e) => {
                    log(format!(
                        "Failed to parse JSON response. Raw response: {}",
                        response_text
                    ));
                    return Err(format!(
                        "Explorer Response Error: Failed to parse JSON response from explorer API. The response may be empty or invalid. Error: {}",
                        e
                    ).into());
                }
            };
            if let Some(message) = json_response["message"].as_str() {
                if message == "OK" {
                    if let Some(result) = json_response["result"].as_array() {
                        return Ok(result.first().unwrap().clone());
                    }
                }
            }
            log(format!(
                "Invalid response from etherscan: {:?}",
                json_response
            ));
            Err("Invalid response from etherscan".into())
        }
        Err(e) => Err(format!("Explorer Request Error: {}", e).into()),
    }
}

fn get_constructor_inputs(abi: &str) -> Result<Option<Constructor>, Box<dyn std::error::Error>> {
    if abi == "Contract source code not verified" {
        return Err("Contract source code not verified".into());
    }
    let parsed_abi: JsonAbi = serde_json::from_str(abi)?;
    Ok(parsed_abi.constructor)
}
