use crate::libs::explorer::ExplorerApiLib;
use crate::libs::web3::Web3Lib;
use crate::state_manager::STATE_MANAGER;
use crate::util::chain_config::Explorer;
use alloy::{
    dyn_abi::{DynSolValue, JsonAbiExt},
    hex::FromHex,
    json_abi::Param,
    primitives::{hex, Address, FixedBytes},
};
use reqwest;
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
    //     Some();
    // STATE_MANAGER.workflow_state.lock()?.web3 = Some(Web3Lib::new(format!(
    //     "https://mainnet.infura.io/v3/{}",
    //     infura_api_key
    // ))?);
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
        .join("json")
        .join(format!("{}.json", chain_id));
    let mut deployments_json = if deployments_file.exists() {
        let contents = std::fs::read_to_string(&deployments_file)
            .expect("Should have been able to read the file");
        serde_json::from_str(&contents).expect("JSON was not well-formatted")
    } else {
        serde_json::json!({
            "chainId": chain_id,
            "latest": {},
            "history": []
        })
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

    let contract_address = "0xEf1c6E67703c7BD7107eed8303Fbe6EC2554BF6B".parse::<Address>()?; // universal router

    // let contract_address = "0x1F98431c8aD98523631AE4a59f267346ea31F984".parse::<Address>()?; // v3 factory

    // let mut contract_name = "UniswapV2Factory".to_string();
    // let mut constructor_arguments =
    //     "000000000000000000000000c0a4272bb5df52134178df25d77561cfb17ce407".to_string();
    // let mut constructor_inputs: Option<Constructor> = None;

    let (contract_name, constructor_arguments, constructor) =
        explorer_api.get_contract_data(contract_address).await?;

    println!("Contract name: {}", contract_name);
    println!("Constructor arguments: {}", constructor_arguments);
    println!("Constructor inputs: {:?}", constructor);

    let local_out_path = working_dir
        .join("out")
        .join(contract_name.to_string() + ".sol")
        .join(contract_name.to_string() + ".json");

    if local_out_path.exists() {
        println!("File exists: {}", local_out_path.display());

        detect_duplicate(
            deployments_json["history"].as_array().unwrap().clone(),
            contract_address.to_string(),
        )?;

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
        let args: Vec<alloy::dyn_abi::DynSolValue> = constructor
            .clone()
            .unwrap()
            .abi_decode_input(&hex::decode(constructor_arguments).unwrap(), true)?;

        println!("{:?}", args);
        let mut pool_init_code_hash: Option<FixedBytes<32>> = None;
        if contract_name == "UniswapV2Factory" {
            pool_init_code_hash = Some(
                web3.get_v2_pool_init_code_hash(contract_address, block_number)
                    .await?,
            );
        } else if contract_name == "UniswapV3Factory" {
            pool_init_code_hash = Some(
                web3.get_v3_pool_init_code_hash(contract_address, block_number)
                    .await?,
            );
        }

        let mut contract_data = json!({
            "contracts": {
                contract_name.clone(): {
                    "address": contract_address,
                    // TODO: add proxy support
                    "proxy": false,
                    "deploymentTxn": tx_hash,
                    "input": {
                        "constructor": extract_constructor_inputs(constructor.unwrap().inputs, args).unwrap()
                    }
                }
            },
            "timestamp": timestamp
        });
        if pool_init_code_hash.is_some() {
            contract_data["contracts"][contract_name]["poolInitCodeHash"] =
                pool_init_code_hash.unwrap().to_string().into();
        }
        deployments_json["history"]
            .as_array_mut()
            .unwrap()
            .push(contract_data);
        println!(
            "\n\ncontract_data: {}",
            serde_json::to_string_pretty(&deployments_json).unwrap()
        );

        std::fs::create_dir_all(deployments_file.parent().unwrap())?;
        deployments_json = post_process_deployments_json(deployments_json)?;
        std::fs::write(
            deployments_file,
            serde_json::to_string_pretty(&deployments_json).unwrap(),
        )?;

        let forge_chronicles_path = working_dir
            .join("lib")
            .join("forge-chronicles")
            .join("index.js");
        if !forge_chronicles_path.exists() {
            return Err("forge-chronicles not installed. Please run 'forge install 0xPolygon/forge-chronicles'".into());
        }

        // execute bash command
        let output = std::process::Command::new("node")
            .arg(forge_chronicles_path)
            .arg("-c")
            .arg(chain_id)
            .arg("-s")
            .output()
            .expect("Failed to execute markdown generation script");
        println!("Output: {}", String::from_utf8_lossy(&output.stdout));
    } else {
        println!("File does not exist: {}", local_out_path.display());
    }

    return Ok(true);
}

fn detect_duplicate(
    deployments_history: Vec<serde_json::Value>,
    address: String,
) -> Result<(), Box<dyn std::error::Error>> {
    // TODO: add proxy support
    let history = deployments_history.clone();
    for item in history {
        for (_, v) in item["contracts"].as_object().unwrap() {
            if v["address"].as_str().unwrap() == address {
                return Err("Duplicate contract found".into());
            }
        }
    }
    Ok(())
}

fn post_process_deployments_json(
    mut deployments_json: serde_json::Value,
) -> Result<serde_json::Value, Box<dyn std::error::Error>> {
    // sort history by timestamp
    let mut history = deployments_json["history"].as_array().unwrap().clone();
    history.sort_by_key(|k| k["timestamp"].as_u64().unwrap());
    history.reverse();
    let mut latest = json!({});
    for item in history.clone() {
        for (k, v) in item["contracts"].as_object().unwrap() {
            if !latest[k].is_null()
                && latest[k]["timestamp"].as_u64().unwrap() > item["timestamp"].as_u64().unwrap()
            {
                continue;
            }
            latest[k] = json!({
                    "address": v["address"],
                    "proxy": v["proxy"],
                    "deploymentTxn": v["deploymentTxn"],
                    "timestamp": item["timestamp"]
            });
            if !item["commitHash"].is_null() {
                latest[k]["commitHash"] = item["commitHash"].clone();
            }
            if !v["poolInitCodeHash"].is_null() {
                latest[k]["poolInitCodeHash"] = v["poolInitCodeHash"].clone();
            }
        }
    }
    deployments_json["history"] = serde_json::Value::Array(history);
    deployments_json["latest"] = latest;
    Ok(deployments_json)
}

fn extract_constructor_inputs(
    constructor_params: Vec<Param>,
    args: Vec<DynSolValue>,
) -> Result<serde_json::Value, Box<dyn std::error::Error>> {
    let mut result = json!({});
    // constuctor inputs and arguments should always have the same length because the abi encoded constructor args were decoded using the constructor inputs and validated
    for i in 0..constructor_params.len() {
        let input = constructor_params[i].clone();
        let value = args[i].clone();
        result[input.name] = serialize_value(input.clone(), value)?;
    }
    Ok(result)
}

fn serialize_value(
    param: Param,
    value: DynSolValue,
) -> Result<serde_json::Value, Box<dyn std::error::Error>> {
    return match value {
        DynSolValue::Address(a) => Ok(a.to_string().into()),
        DynSolValue::Bool(b) => Ok(b.to_string().into()),
        DynSolValue::FixedBytes(b, _) => Ok(b.to_string().into()),
        DynSolValue::Int(i, _) => Ok(i.to_string().into()),
        DynSolValue::Uint(u, _) => Ok(u.to_string().into()),
        DynSolValue::String(s) => Ok(s.to_string().into()),
        DynSolValue::Tuple(t) => extract_constructor_inputs(param.components, t),
        DynSolValue::Function(f) => Ok(f.to_string().into()),
        DynSolValue::Bytes(b) => Ok(hex::encode(DynSolValue::Bytes(b).abi_encode()).into()),
        DynSolValue::Array(_) => {
            // TODO
            // let mut arr = json!([]);
            // push items into arr
            Err("Found array, not implemented".into())
        }
        DynSolValue::FixedArray(_) => {
            // TODO
            // let mut arr = json!([]);
            // push items into arr
            Err("Found fixed array, not implemented".into())
        }
    };
}

async fn pretty_print_response(url: &str) -> Result<(), Box<dyn std::error::Error>> {
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
