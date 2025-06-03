use std::collections::HashMap;

use crate::libs::explorer::{Explorer, SupportedExplorerType};

#[derive(Default, Clone)]
pub struct Currency {
    pub name: String,
    pub symbol: String,
    pub decimals: u8,
}

#[derive(Default, Clone)]
pub struct Chain {
    pub name: String,
    pub rpc_url: Vec<String>,
    pub explorers: Vec<Explorer>,
    pub currency: Currency,
}

// The chains.json file is downloaded from here: https://chainid.network/chains.json
// The build.sh script automatically downloads the latest file and includes it in the binary.
// this json in the file is automatically parsed and populated into the state manager to provide chain information such as rpcs, explorers, etc.
const CHAINS_DATA: &str = include_str!("../assets/chains.json");
const ETHERSCAN_CHAINLIST_DATA: &str = include_str!("../assets/etherscan_chainlist.json");

pub fn parse_chain_config() -> HashMap<String, Chain> {
    let mut chains = HashMap::new();
    let chains_data: serde_json::Value =
        serde_json::from_str(CHAINS_DATA).expect("Failed to parse JSON");

    if let serde_json::Value::Array(chains_arr) = chains_data {
        for chain_obj in chains_arr {
            if let serde_json::Value::Object(chain_data) = chain_obj {
                let chain_id = chain_data["chainId"]
                    .as_u64()
                    .map(|id| id.to_string())
                    .unwrap_or_default();
                let name = chain_data["name"].as_str().unwrap_or("").to_string();
                let rpc_url = chain_data["rpc"]
                    .as_array()
                    .map(|arr| {
                        arr.iter()
                            .filter_map(|v| v.as_str())
                            .filter(|url| url.starts_with("http"))
                            .map(String::from)
                            .collect()
                    })
                    .unwrap_or_default();

                let explorers: Vec<Explorer> = chain_data
                    .get("explorers")
                    .and_then(|explorers| explorers.as_array())
                    .map(|arr| {
                        arr.iter()
                            .filter_map(|v| {
                                if let serde_json::Value::Object(explorer) = v {
                                    let mut explorer = Explorer {
                                        name: explorer
                                            .get("name")
                                            .and_then(|n| n.as_str())
                                            .unwrap_or("")
                                            .to_string(),
                                        url: explorer
                                            .get("url")
                                            .and_then(|u| u.as_str())
                                            .unwrap_or("")
                                            .to_string(),
                                        standard: explorer
                                            .get("standard")
                                            .and_then(|s| s.as_str())
                                            .unwrap_or("")
                                            .to_string(),
                                        explorer_type: SupportedExplorerType::Manual,
                                    };
                                    guess_explorer_type(&mut explorer);
                                    Some(explorer)
                                } else {
                                    None
                                }
                            })
                            .collect()
                    })
                    .unwrap_or_default();

                let currency = Currency {
                    name: chain_data["nativeCurrency"]["name"]
                        .as_str()
                        .unwrap_or("")
                        .to_string(),
                    symbol: chain_data["nativeCurrency"]["symbol"]
                        .as_str()
                        .unwrap_or("")
                        .to_string(),
                    decimals: chain_data["nativeCurrency"]["decimals"]
                        .as_u64()
                        .unwrap_or(18) as u8,
                };

                chains.insert(
                    chain_id,
                    Chain {
                        name,
                        rpc_url,
                        explorers,
                        currency,
                    },
                );
            }
        }
    }

    let etherscan_chainlist: serde_json::Value =
        serde_json::from_str(ETHERSCAN_CHAINLIST_DATA).expect("Failed to parse JSON");

    if let Some(result_array) = etherscan_chainlist.get("result").and_then(|v| v.as_array()) {
        for entry in result_array {
            if let Some(entry_obj) = entry.as_object() {
                let chain_id = entry_obj
                    .get("chainid")
                    .and_then(|v| v.as_str())
                    .unwrap_or_default()
                    .to_string();
                if chains.contains_key(&chain_id) {
                    let mut explorers = chains.get_mut(&chain_id).unwrap().explorers.clone();
                    if let Some(etherscan_explorer) = explorers
                        .iter()
                        .find(|e| e.explorer_type == SupportedExplorerType::Etherscan)
                    {
                        let mut v2_explorer = etherscan_explorer.clone();
                        v2_explorer.explorer_type = SupportedExplorerType::EtherscanV2;
                        explorers.push(v2_explorer);
                        chains.get_mut(&chain_id).unwrap().explorers = explorers;
                    }
                }
            }
        }
    }

    chains
}

fn guess_explorer_type(explorer: &mut Explorer) {
    if explorer.url.contains("scan") || explorer.name.contains("scan") {
        explorer.explorer_type = SupportedExplorerType::Etherscan;
    } else if explorer.url.contains("blockscout") || explorer.name.contains("blockscout") {
        explorer.explorer_type = SupportedExplorerType::Blockscout;
    } else {
        explorer.explorer_type = SupportedExplorerType::Manual;
    }
}
