use crate::errors::log;
use crate::libs::explorer::ExplorerApiLib;
use crate::libs::web3::Web3Lib;
use crate::state_manager::STATE_MANAGER;
use crate::util::chain_config::Explorer;
use alloy::{
    dyn_abi::JsonAbiExt,
    eips::BlockNumberOrTag,
    hex::FromHex,
    json_abi::{Constructor, JsonAbi},
    primitives::{hex, utils::keccak256, Address, Bytes, FixedBytes},
    providers::{ext::DebugApi, Provider, ProviderBuilder, RootProvider},
    rpc::types::trace::geth::{
        GethDebugBuiltInTracerType, GethDebugTracerType, GethDebugTracingOptions,
        GethDefaultTracingOptions,
    },
    rpc::types::{trace::geth::CallFrame, Filter},
    transports::http::Http,
};
use reqwest;
use reqwest::Client;
use serde::Serialize;
use serde_json::json;

// this allows to run test code during development so it's not necessary to click through a bunch of screens over and over again. Return false to continue with the normal program flow and show the main menu. Return true to abort the program after the code from this function has been executed. On errors this function will also automatically exit the program. By default this function should be empty and just return false.
pub async fn run() -> Result<bool, Box<dyn std::error::Error>> {
    // return Ok(false);
    let infura_api_key = std::env::var("INFURA_API_KEY").unwrap();
    let alchemy_api_key = std::env::var("ALCHEMY_API_KEY").unwrap();
    let etherscan_api_key = std::env::var("ETHERSCAN_API_KEY").unwrap();

    STATE_MANAGER.workflow_state.lock()?.chain_id = Some("1".to_string());
    // STATE_MANAGER.workflow_state.lock()?.rpc_url = Some(format!(
    //     "https://eth-mainnet.g.alchemy.com/v2/{}",
    //     alchemy_api_key
    // ));
    // STATE_MANAGER.workflow_state.lock()?.rpc_url =
    //     Some(format!("https://mainnet.infura.io/v3/{}", infura_api_key));
    STATE_MANAGER.workflow_state.lock()?.web3 =
        Some(Web3Lib::new(std::env::var("RPC_URL").unwrap())?);
    STATE_MANAGER.workflow_state.lock()?.block_explorer = Some(Explorer {
        name: "etherscan".to_string(),
        url: "https://etherscan.io".to_string(),
        standard: "EIP3091".to_string(),
    });

    let chain_id = STATE_MANAGER
        .workflow_state
        .lock()?
        .chain_id
        .clone()
        .unwrap();

    let working_dir = STATE_MANAGER.working_directory.clone();

    // check if deployments/chainid.json exists, if yes load it
    let deployments_file = working_dir
        .join("deployments")
        .join(format!("{}.json", chain_id));
    let deployments_json;
    let mut deployments = if deployments_file.exists() {
        let contents = std::fs::read_to_string(&deployments_file)
            .expect("Should have been able to read the file");
        deployments_json = serde_json::from_str(&contents).expect("JSON was not well-formatted");
    } else {
        deployments_json = serde_json::json!({
            "chainId": chain_id,
            "latest": {},
            "history": []
        });
    };

    println!("{:?}", deployments_json);

    let explorer = STATE_MANAGER
        .workflow_state
        .lock()?
        .block_explorer
        .clone()
        .unwrap();

    let explorer_api = ExplorerApiLib::new(explorer, etherscan_api_key)?;

    // let contract_address = "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f".parse::<Address>()?; // v2 factory

    // let contract_address = "0x1F98431c8aD98523631AE4a59f267346ea31F984".parse::<Address>()?; // v3 factory

    let contract_address = "0xEf1c6E67703c7BD7107eed8303Fbe6EC2554BF6B".parse::<Address>()?; // universal router

    // let mut contract_name = "UniswapV2Factory".to_string();
    // let mut constructor_arguments =
    //     "000000000000000000000000c0a4272bb5df52134178df25d77561cfb17ce407".to_string();
    // let mut constructor_inputs: Option<Constructor> = None;

    let (contract_name, constructor_arguments, constructor_inputs) =
        explorer_api.get_contract_data(contract_address).await?;

    println!("Contract name: {}", contract_name);
    println!("Constructor arguments: {}", constructor_arguments);
    println!("Constructor inputs: {:?}", constructor_inputs);

    let local_out_path = working_dir
        .join("out")
        .join(contract_name.to_string() + ".sol")
        .join(contract_name.to_string() + ".json");

    if local_out_path.exists() {
        println!("File exists: {}", local_out_path.display());

        let tx_hash = explorer_api
            .get_creation_transaction_hash(contract_address)
            .await?;

        println!("Transaction hash: {}", tx_hash);

        let mut web3 = STATE_MANAGER.workflow_state.lock()?.web3.clone().unwrap();

        let block_number = web3
            .get_block_number_by_transaction_hash(FixedBytes::<32>::from_hex(tx_hash.as_str())?)
            .await?;

        let timestamp = web3
            .get_block_timestamp_by_block_number(block_number)
            .await?;

        println!("Timestamp: {:?}", timestamp);
        let args = constructor_inputs
            .unwrap()
            .abi_decode_input(&hex::decode(constructor_arguments).unwrap(), true);

        println!("{:?}", args);

        if contract_name == "UniswapV2Factory" {
            web3.get_v2_pool_init_code_hash(contract_address, block_number)
                .await
                .unwrap();
            // let (first_pool_deploy_tx, first_pool) =
            //     get_v2_pool(provider.clone(), contract_address.to_string(), block_number).await;
            // get_init_code_hash(provider, first_pool, first_pool_deploy_tx).await;
        } else if contract_name == "UniswapV3Factory" {
            web3.get_v3_pool_init_code_hash(contract_address, block_number)
                .await
                .unwrap();
            // let (first_pool_deploy_tx, first_pool) =
            //     get_v3_pool(provider.clone(), contract_address.to_string(), block_number).await;
            // get_init_code_hash(provider, first_pool, first_pool_deploy_tx).await;
        }
    } else {
        println!("File does not exist: {}", local_out_path.display());
    }

    // let mut contract_data = json!({
    //     "contracts": {
    //         contract_name: {
    //             "address": contract_address,
    //             "proxy": false,
    //             "deploymentTxn": tx_hash,
    //             "input": {
    //                 "constructor": {}
    //             }
    //         }
    //     },
    //     "timestamp": timestamp
    // });

    // parse data into the following json:
    // {
    //    contracts: {
    //      [contract_name]: {
    //        address: contract_address,
    //        deploymentTxn: tx_hash,
    //        poolInitCodeHash: init_code_hash, // optional if v2 or v3 factory
    //        input: {
    //          constructor: {
    //            argument1: value1,
    //            argument2: value2,
    //            ...
    //          }
    //        }
    //      }
    //    },
    //    timestamp: timestamp,
    // }
    return Ok(true);
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
