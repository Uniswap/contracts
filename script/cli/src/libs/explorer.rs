use crate::errors::{
    log, EtherscanRequestError, EtherscanResponseError, InvalidEtherscanUrlError,
    UnsupportedExplorerError,
};
use crate::util::chain_config::Explorer;
use alloy::{
    json_abi::{Constructor, JsonAbi},
    primitives::{Address, FixedBytes},
};

#[derive(Clone, PartialEq, Eq, Default)]
pub enum SupportedExplorerType {
    #[default]
    Etherscan,
    Blockscout,
}

#[derive(Default, Clone)]
pub struct ExplorerApiLib {
    pub name: String,
    pub url: String,
    pub standard: String,
    pub api_key: String,
    pub api_url: String,
    pub explorer_type: SupportedExplorerType,
}

impl ExplorerApiLib {
    pub fn new(explorer: Explorer, api_key: String) -> Result<Self, Box<dyn std::error::Error>> {
        if explorer.name.to_lowercase().contains("blockscout") {
            // blockscout just appends /api to their explorer url
            return Ok(ExplorerApiLib {
                name: explorer.name.to_string(),
                url: explorer.url.to_string(),
                standard: explorer.standard.to_string(),
                api_key: api_key.to_string(),
                api_url: format!("{}/api", explorer.url),
                explorer_type: SupportedExplorerType::Blockscout,
            });
        } else if explorer.name.to_lowercase().contains("scan") {
            // etherscan prepends their api url with the api.* subdomain. So for mainnet this would be https://etherscan.io => https://api.etherscan.io. However testnets are also their own subdomain, their subdomains are then prefixed with api- and the explorer url is then used as the suffix, e.g., https://sepolia.etherscan.io => https://api-sepolia.etherscan.io. Some chains are also using a subdomain of etherscan, e.g., Optimism uses https://optimistic.etherscan.io. Here also the dash api- prefix is used. The testnet of optimism doesn't use an additional subdomain: https://sepolia-optimistic.etherscan.io => https://api-sepolia-optimistic.etherscan.io. Some explorers are using their own subdomain, e.g., arbiscan for Arbitrum: https://arbiscan.io => https://api.arbiscan.io.
            // TODO: this is kinda error prone, this would catch correct etherscan instances like arbiscan for Arbitrum but there are a lot of other explorers named *something*scan that are not using an etherscan instance and thus don't share the same api endpoints. Maybe get a list of known etherscan-like explorers and their api urls and check if the explorer_url matches any of them?
            let slices = explorer.url.split(".").collect::<Vec<&str>>().len();
            if slices == 2 {
                // we are dealing with https://somethingscan.io
                return Ok(ExplorerApiLib {
                    name: explorer.name.to_string(),
                    url: explorer.url.to_string(),
                    standard: explorer.standard.to_string(),
                    api_key: api_key.to_string(),
                    api_url: format!("{}", explorer.url.replace("https://", "https://api.")),
                    explorer_type: SupportedExplorerType::Etherscan,
                });
            } else if slices == 3 {
                // we are dealing with https://subdomain.somethingscan.io
                return Ok(ExplorerApiLib {
                    name: explorer.name.to_string(),
                    url: explorer.url.to_string(),
                    standard: explorer.standard.to_string(),
                    api_key: api_key.to_string(),
                    api_url: format!("{}", explorer.url.replace("https://", "https://api-")),
                    explorer_type: SupportedExplorerType::Etherscan,
                });
            } else {
                return Err(Box::new(InvalidEtherscanUrlError(
                    explorer.name.to_string(),
                    explorer.url.to_string(),
                )));
            }
        } else {
            return Err(Box::new(UnsupportedExplorerError(
                explorer.name.to_string(),
                explorer.url.to_string(),
            )));
        }
    }

    pub async fn get_contract_data(
        &self,
        contract_address: Address,
    ) -> Result<(String, String, Option<Constructor>), Box<dyn std::error::Error>> {
        if self.explorer_type == SupportedExplorerType::Etherscan
            || self.explorer_type == SupportedExplorerType::Blockscout
        {
            let url = format!(
                "{}/api?module=contract&action=getsourcecode&address={}&apikey={}",
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
                        println!("{:?}", result);
                        return Ok((
                            contract_name.to_string(),
                            constructor_arguments,
                            get_constructor_inputs(abi),
                        ));
                    } else {
                        println!("{:?}", result);
                        return Err(Box::new(EtherscanResponseError(
                            "ContractName not found in the response".to_string(),
                        )));
                    }
                }
                Err(e) => {
                    return Err(e);
                }
            }
        }
        return Err(Box::new(UnsupportedExplorerError(
            self.name.to_string(),
            self.url.to_string(),
        )));
    }

    pub async fn get_creation_transaction_hash(
        &self,
        contract_address: Address,
    ) -> Result<String, Box<dyn std::error::Error>> {
        if self.explorer_type == SupportedExplorerType::Etherscan
            || self.explorer_type == SupportedExplorerType::Blockscout
        {
            let url = format!(
                "{}/api?module=contract&action=getcontractcreation&contractaddresses={}&apikey={}",
                self.api_url, contract_address, self.api_key
            );
            let tx_hash = get_etherscan_result(&url).await?["txHash"]
                .as_str()
                .unwrap()
                .to_string();
            return Ok(tx_hash);
        }
        return Err(Box::new(UnsupportedExplorerError(
            self.name.to_string(),
            self.url.to_string(),
        )));
    }
}

async fn get_etherscan_result(url: &str) -> Result<serde_json::Value, Box<dyn std::error::Error>> {
    match reqwest::get(url).await {
        Ok(response) => {
            let json_response: serde_json::Value = response.json().await.unwrap();
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
            return Err(Box::new(EtherscanResponseError(
                "Invalid response from etherscan".to_string(),
            )));
        }
        Err(e) => {
            return Err(Box::new(EtherscanRequestError(Box::new(e))));
        }
    }
}

fn get_constructor_inputs(abi: &str) -> Option<Constructor> {
    let parsed_abi: JsonAbi = serde_json::from_str(abi).unwrap();
    return parsed_abi.constructor;
}
