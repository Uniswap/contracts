use crate::errors::log;
use crate::state_manager::STATE_MANAGER;
use crate::util::chain_config::Explorer;
use alloy::{
    dyn_abi::{DynSolType, DynSolValue, JsonAbiExt},
    eips::BlockNumberOrTag,
    hex::FromHex,
    json_abi::{Constructor, JsonAbi, Param},
    primitives::{hex, FixedBytes},
    providers::{Provider, ProviderBuilder},
};

use reqwest;

pub async fn run() -> bool {
    // return false;
    let infura_api_key = std::env::var("INFURA_API_KEY").unwrap();
    let etherscan_api_key = std::env::var("ETHERSCAN_API_KEY").unwrap();

    STATE_MANAGER.app_state.lock().unwrap().chain_id = Some("1".to_string());
    STATE_MANAGER.app_state.lock().unwrap().rpc_url =
        Some(format!("https://mainnet.infura.io/v3/{}", infura_api_key));
    STATE_MANAGER.app_state.lock().unwrap().block_explorer = Some(Explorer {
        name: "etherscan".to_string(),
        url: "https://etherscan.io".to_string(),
        standard: "EIP3091".to_string(),
        api_key: Some(etherscan_api_key),
    });

    let chain_id = STATE_MANAGER
        .app_state
        .lock()
        .unwrap()
        .chain_id
        .clone()
        .unwrap();

    let mut rpc_url = STATE_MANAGER.app_state.lock().unwrap().rpc_url.clone();

    let explorer = STATE_MANAGER
        .app_state
        .lock()
        .unwrap()
        .block_explorer
        .clone()
        .unwrap();

    let working_dir = STATE_MANAGER
        .app_state
        .lock()
        .unwrap()
        .working_directory
        .clone();

    let explorer_url = if explorer.name.contains("blockscout") {
        explorer.url + "/api"
    } else if explorer.name.contains("scan") {
        explorer.url.replace("https://", "https://api.")
    } else {
        explorer.url
    };

    let address = "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f";

    let mut url = format!(
        "{}/api?module=contract&action=getsourcecode&address={}&apikey={}",
        explorer_url,
        address,
        explorer.api_key.as_ref().unwrap()
    );

    let mut contract_name = "UniswapV2Factory".to_string();
    let mut constructor_arguments =
        "000000000000000000000000c0a4272bb5df52134178df25d77561cfb17ce407".to_string();
    let mut constructor_inputs: Option<Constructor> = None;

    match get_contract_data(&url).await {
        Ok((contract_name_, constructor_arguments_, constructor_inputs_)) => {
            contract_name = contract_name_;
            constructor_arguments = constructor_arguments_;
            constructor_inputs = constructor_inputs_;
        }
        Err(e) => {
            println!("Error: {:?}", e);
        }
    }

    println!("Contract name: {}", contract_name);
    println!("Constructor arguments: {}", constructor_arguments);
    println!("Constructor inputs: {:?}", constructor_inputs);

    let local_out_path = working_dir
        .join("out")
        .join(contract_name.to_string() + ".sol")
        .join(contract_name.to_string() + ".json");

    if local_out_path.exists() {
        println!("File exists: {}", local_out_path.display());

        let mut url = format!(
            "{}/api?module=contract&action=getcontractcreation&contractaddresses={}&apikey={}",
            explorer_url,
            address,
            explorer.api_key.as_ref().unwrap()
        );

        let tx_hash = get_creation_transaction_hash(&url).await.unwrap();
        println!("Transaction hash: {}", tx_hash);

        let provider = ProviderBuilder::new().on_http(rpc_url.unwrap().parse().unwrap());
        let block_number = provider
            .get_transaction_receipt(FixedBytes::<32>::from_hex(tx_hash).unwrap())
            .await
            .unwrap()
            .unwrap()
            .block_number
            .unwrap();
        let timestamp = provider
            .get_block_by_number(BlockNumberOrTag::Number(block_number), false)
            .await
            .unwrap()
            .unwrap()
            .header
            .timestamp;
        println!("Timestamp: {:?}", timestamp);
        let args = constructor_inputs
            .unwrap()
            .abi_decode_input(&hex::decode(constructor_arguments).unwrap(), false);

        println!("{:?}", args);
    } else {
        println!("File does not exist: {}", local_out_path.display());
    }

    return true;
}

async fn pretty_print_request(url: &str) -> Result<(), Box<dyn std::error::Error>> {
    let response: Result<reqwest::Response, reqwest::Error> = reqwest::get(url).await;
    match response {
        Ok(response) => {
            println!(
                "{}",
                serde_json::to_string_pretty(&response.json::<serde_json::Value>().await.unwrap())
                    .unwrap()
            );
            Ok(())
        }
        Err(e) => {
            println!("Error: {:?}", e);
            Err(e.into())
        }
    }
}

async fn get_creation_transaction_hash(url: &str) -> Result<String, Box<dyn std::error::Error>> {
    Ok(get_etherscan_result(url).await?["txHash"]
        .as_str()
        .unwrap()
        .to_string())
}

async fn get_contract_data(
    url: &str,
) -> Result<(String, String, Option<Constructor>), Box<dyn std::error::Error>> {
    match get_etherscan_result(url).await {
        Ok(result) => {
            if let (Some(constructor_arguments), Some(contract_name), Some(abi)) = (
                result["ConstructorArguments"].as_str(),
                result["ContractName"].as_str(),
                result["ABI"].as_str(),
            ) {
                Ok((
                    contract_name.to_string(),
                    constructor_arguments.to_string(),
                    get_constructor_inputs(abi),
                ))
            } else {
                return Err(
                    "ConstructorArguments or ContractName not found in the response".into(),
                );
            }
        }
        Err(e) => {
            return Err(e);
        }
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
            return Err("Invalid response from etherscan".into());
        }
        Err(e) => {
            log(format!("Error getting etherscan result: {:?}", e));
            return Err("An error occurred during the etherscan request".into());
        }
    }
}

fn get_constructor_inputs(abi: &str) -> Option<Constructor> {
    let parsed_abi: JsonAbi = serde_json::from_str(abi).unwrap();
    return parsed_abi.constructor;
    // if let Some(constructor) = parsed_abi.constructor {
    //     println!("\n>> Constructor:");
    //     println!("  Inputs: {:?}", constructor.clone().inputs);
    //     println!("  State mutability: {:?}", constructor.state_mutability);
    //     return constructor.inputs;
    // } else {
    //     return Vec::new();
    // }
    // if let Some(abi_array) = parsed_abi.as_array() {
    //     for item in abi_array {
    //         if let Some(item_type) = item["type"].as_str() {
    //             if item_type == "constructor" {
    //                 if let Some(inputs) = item["inputs"].as_array() {
    //                     let inputs_string = format!("{:?}", inputs);
    //                     log(format!("Constructor inputs: {}", inputs_string));
    //                     return inputs
    //                         .iter()
    //                         .map(|input| {
    //                             (
    //                                 input["name"].as_str().unwrap_or("").to_string(),
    //                                 input["type"].as_str().unwrap_or("").to_string(),
    //                             )
    //                         })
    //                         .collect::<Vec<(String, String)>>();
    //                 }
    //             }
    //         }
    //     }
    // }

    // Vec::new() // Return an empty vector if no constructor inputs are found
}
