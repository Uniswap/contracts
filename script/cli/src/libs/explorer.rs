use crate::{errors::log, state_manager::STATE_MANAGER};
use alloy::{
    json_abi::{Constructor, JsonAbi},
    primitives::Address,
};

#[derive(Clone, PartialEq, Eq, Default)]
pub enum SupportedExplorerType {
    #[default]
    Manual,
    EtherscanV2,
    Etherscan,
    Blockscout,
}

#[derive(Default, Clone)]
pub struct Explorer {
    pub name: String,
    pub url: String,
    pub standard: String,
    pub explorer_type: SupportedExplorerType,
}

#[derive(Default, Clone)]
pub struct ExplorerApiLib {
    pub explorer: Explorer,
    pub api_key: String,
    pub api_url: String,
}

impl ExplorerApiLib {
    pub fn new(explorer: Explorer, api_key: String) -> Result<Self, Box<dyn std::error::Error>> {
        if explorer.explorer_type == SupportedExplorerType::Blockscout {
            // blockscout just appends /api to their explorer url
            let api_url = format!("{}/api?", explorer.url);
            Ok(ExplorerApiLib {
                explorer,
                api_key: api_key.to_string(),
                api_url,
            })
        } else if explorer.explorer_type == SupportedExplorerType::EtherscanV2 {
            let chain_id = STATE_MANAGER
                .workflow_state
                .lock()
                .unwrap()
                .chain_id
                .clone();
            if let Some(chain_id) = chain_id {
                return Ok(ExplorerApiLib {
                    explorer,
                    api_key: api_key.to_string(),
                    api_url: format!("https://api.etherscan.io/v2/api?chainid={}", chain_id),
                });
            } else {
                return Err(format!(
                    "Chain id not found for explorer: {} ({})",
                    explorer.name, explorer.url,
                )
                .into());
            }
        } else if explorer.explorer_type == SupportedExplorerType::Etherscan {
            // etherscan prepends their api url with the api.* subdomain. So for mainnet this would be https://etherscan.io => https://api.etherscan.io. However testnets are also their own subdomain, their subdomains are then prefixed with api- and the explorer url is then used as the suffix, e.g., https://sepolia.etherscan.io => https://api-sepolia.etherscan.io. Some chains are also using a subdomain of etherscan, e.g., Optimism uses https://optimistic.etherscan.io. Here also the dash api- prefix is used. The testnet of optimism doesn't use an additional subdomain: https://sepolia-optimistic.etherscan.io => https://api-sepolia-optimistic.etherscan.io. Some explorers are using their own subdomain, e.g., arbiscan for Arbitrum: https://arbiscan.io => https://api.arbiscan.io.
            // TODO: this is kinda error prone, this would catch correct etherscan instances like arbiscan for Arbitrum but there are a lot of other explorers named *something*scan that are not using an etherscan instance and thus don't share the same api endpoints. Maybe get a list of known etherscan-like explorers and their api urls and check if the explorer_url matches any of them?
            let slices = explorer.url.split(".").collect::<Vec<&str>>().len();
            if slices == 2 {
                // we are dealing with https://somethingscan.io
                let api_url = explorer.url.replace("https://", "https://api.");
                return Ok(ExplorerApiLib {
                    explorer,
                    api_key: api_key.to_string(),
                    api_url: format!("{}/api?", api_url),
                });
            } else if slices == 3 {
                // we are dealing with https://subdomain.somethingscan.io
                let api_url = explorer.url.replace("https://", "https://api-");
                return Ok(ExplorerApiLib {
                    explorer,
                    api_key: api_key.to_string(),
                    api_url: format!("{}/api?", api_url),
                });
            } else {
                return Err(format!(
                    "Invalid etherscan url: {} ({})",
                    explorer.name, explorer.url,
                )
                .into());
            }
        } else {
            return Err(
                format!("Unsupported explorer: {} ({})", explorer.name, explorer.url,).into(),
            );
        }
    }

    pub async fn get_contract_data(
        &self,
        contract_address: Address,
    ) -> Result<(String, String, Option<Constructor>), Box<dyn std::error::Error>> {
        if self.explorer.explorer_type == SupportedExplorerType::Etherscan
            || self.explorer.explorer_type == SupportedExplorerType::EtherscanV2
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
        if self.explorer.explorer_type == SupportedExplorerType::Etherscan
            || self.explorer.explorer_type == SupportedExplorerType::EtherscanV2
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
    pub fn to_env_var_name(&self) -> String {
        match self {
            SupportedExplorerType::Etherscan => "ETHERSCAN_API_KEY".to_string(),
            SupportedExplorerType::EtherscanV2 => "ETHERSCAN_API_KEY".to_string(),
            SupportedExplorerType::Blockscout => "BLOCKSCOUT_API_KEY".to_string(),
            SupportedExplorerType::Manual => "VERIFIER_API_KEY".to_string(),
        }
    }

    pub fn name(&self) -> String {
        match self {
            SupportedExplorerType::Etherscan => "Etherscan".to_string(),
            SupportedExplorerType::EtherscanV2 => "Etherscan v2".to_string(),
            SupportedExplorerType::Blockscout => "Blockscout".to_string(),
            SupportedExplorerType::Manual => "".to_string(),
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
