use crate::libs::explorer::ExplorerApiLib;
use crate::libs::web3::Web3Lib;
use alloy::{
    dyn_abi::{DynSolValue, JsonAbiExt},
    hex::{self, FromHex},
    json_abi::Param,
    primitives::{Address, FixedBytes, U256},
    providers::Provider,
};
use serde_json::{json, Value};
use std::path::PathBuf;

pub struct RegisterContractData {
    pub address: Option<String>,
}

pub async fn generate_deployment_log(
    contract_address: Address,
    chain_id: String,
    working_dir: PathBuf,
    explorer_api: ExplorerApiLib,
    web3: Web3Lib,
) -> Result<String, Box<dyn std::error::Error>> {
    // check if deployments/chainid.json exists, if yes load it
    let deployments_file = working_dir
        .join("deployments")
        .join("json")
        .join(format!("{}.json", chain_id));
    let mut deployments_json = if deployments_file.exists() {
        let contents = std::fs::read_to_string(&deployments_file)?;
        serde_json::from_str(&contents)?
    } else {
        serde_json::json!({
            "chainId": chain_id,
            "latest": {},
            "history": []
        })
    };

    crate::errors::log(format!(
        "Getting verified contract data for {} from explorer",
        contract_address
    ));
    let (mut contract_name, constructor_arguments, mut constructor) =
        explorer_api.get_contract_data(contract_address).await?;

    let local_out_path: PathBuf = working_dir
        .join("out")
        .join(contract_name.to_string() + ".sol")
        .join(contract_name.to_string() + ".json");

    if contract_name != "TransparentUpgradeableProxy" && !local_out_path.exists() {
        return Err(format!(
            "Smart contract '{}' not found in foundry 'out' directory",
            contract_name
        )
        .into());
    }

    detect_duplicate(
        deployments_json["history"].as_array().unwrap().clone(),
        contract_address.to_string(),
    )?;

    let tx_hash = explorer_api
        .get_creation_transaction_hash(contract_address)
        .await?;
    crate::errors::log(format!("creation transaction hash: {}", tx_hash));

    let block_number = if !tx_hash.starts_with("GENESIS") {
        web3.get_block_number_by_transaction_hash(FixedBytes::<32>::from_hex(tx_hash.as_str())?)
            .await?
    } else {
        1
    };
    crate::errors::log(format!(
        "block number for creation transaction hash: {}",
        block_number
    ));

    let timestamp = web3
        .get_block_timestamp_by_block_number(block_number)
        .await?;
    crate::errors::log(format!("block timestamp for block number: {}", timestamp));

    crate::errors::log(format!(
        "Decoding constructor arguments {:?}\n{}",
        constructor, constructor_arguments
    ));
    let mut args = None;
    if constructor.is_some() && !constructor_arguments.is_empty() {
        args = Some(
            constructor
                .clone()
                .unwrap()
                .abi_decode_input(&hex::decode(constructor_arguments).unwrap(), true)?,
        );
    }

    // ignore pool init code hash for now because there is no good way to get it.
    // let mut pool_init_code_hash: Option<FixedBytes<32>> = None;
    // if contract_name == "UniswapV2Factory" {
    //     pool_init_code_hash = Some(
    //         web3.get_v2_pool_init_code_hash(contract_address, block_number)
    //             .await?,
    //     );
    // } else if contract_name == "UniswapV3Factory" {
    //     pool_init_code_hash = Some(
    //         web3.get_v3_pool_init_code_hash(contract_address, block_number)
    //             .await?,
    //     );
    // }
    let proxy = contract_name == "TransparentUpgradeableProxy";
    let mut contract_data = if proxy {
        crate::errors::log(
            "Proxy contract detected. Getting admin and implementation addresses".to_string(),
        );
        let admin: U256 = web3
            .provider
            .get_storage_at(
                contract_address,
                "0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103"
                    .parse()
                    .unwrap(),
            )
            .await?;
        crate::errors::log(format!("Admin storage slot: {}", admin));
        let implementation: U256 = web3
            .provider
            .get_storage_at(
                contract_address,
                "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc"
                    .parse()
                    .unwrap(),
            )
            .await?;
        crate::errors::log(format!("Implementation storage slot: {}", implementation));
        let implementation_address = Address::from_word(FixedBytes::<32>::from(implementation));
        crate::errors::log(format!(
            "Implementation address: {}",
            implementation_address
        ));
        let admin_address = Address::from_word(FixedBytes::<32>::from(admin));
        crate::errors::log(format!("Admin address: {}", admin_address));
        let (implementation_name, implementation_constructor_arguments, implementation_constructor) =
            explorer_api
                .get_contract_data(implementation_address)
                .await?;
        crate::errors::log(format!(
            "implementation constructor arguments: {:?}\n{:?}",
            implementation_constructor_arguments, implementation_constructor
        ));

        let local_out_path: PathBuf = working_dir
            .join("out")
            .join(implementation_name.to_string() + ".sol")
            .join(implementation_name.to_string() + ".json");

        if !local_out_path.exists() {
            return Err(format!(
                "Smart contract '{}' not found in foundry 'out' directory",
                implementation_name
            )
            .into());
        }

        let mut implementation_args = None;
        if implementation_constructor.is_some() && !implementation_constructor_arguments.is_empty()
        {
            implementation_args = Some(
                implementation_constructor
                    .clone()
                    .unwrap()
                    .abi_decode_input(
                        &hex::decode(implementation_constructor_arguments).unwrap(),
                        true,
                    )?,
            );
        }
        let mut res = json!({
        "contracts": {
            implementation_name.clone(): {
                "address": contract_address.to_checksum(None),
                "implementation": implementation_address.to_checksum(None),
                "proxy": true,
                "proxyType": contract_name,
                "deploymentTxn": tx_hash,
                "proxyAdmin": admin_address.to_checksum(None),
                "input": {}
            }
        },
            "timestamp": timestamp
        });
        contract_name = implementation_name;
        if args.is_some() {
            res["contracts"][contract_name.clone()]["input"]["proxy"] =
                extract_constructor_inputs(constructor.unwrap().inputs, args.unwrap())?;
            constructor = implementation_constructor;
            args = implementation_args;
        }
        res
    } else {
        json!({
        "contracts": {
            contract_name.clone(): {
                "address": contract_address.to_checksum(None),
                "proxy": false,
                "deploymentTxn": tx_hash,
                "input": {}
            }
        },
            "timestamp": timestamp
        })
    };

    if args.is_some() {
        contract_data["contracts"][contract_name.clone()]["input"]["constructor"] =
            extract_constructor_inputs(constructor.unwrap().inputs, args.unwrap())?;
    } else {
        contract_data["contracts"][contract_name.clone()]["input"]["constructor"] = json!({});
    }
    // if pool_init_code_hash.is_some() {
    //     contract_data["contracts"][contract_name]["poolInitCodeHash"] =
    //         pool_init_code_hash.unwrap().to_string().into();
    // }
    deployments_json["history"]
        .as_array_mut()
        .unwrap()
        .push(contract_data);

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
        return Err(
            "forge-chronicles not installed. Please run 'forge install 0xPolygon/forge-chronicles'"
                .into(),
        );
    }

    // execute bash command
    std::process::Command::new("node")
        .arg(forge_chronicles_path)
        .arg("-c")
        .arg(chain_id)
        .arg("--rpc-url")
        .arg(web3.rpc_url)
        .arg("-e")
        .arg(explorer_api.explorer.url)
        .arg("-s")
        .output()
        .expect("Failed to execute markdown generation script");
    Ok(if proxy { "Proxy:" } else { "" }.to_string() + &contract_name)
}

fn detect_duplicate(
    deployments_history: Vec<Value>,
    address: String,
) -> Result<(), Box<dyn std::error::Error>> {
    let history = deployments_history.clone();
    for item in history {
        for (_, v) in item["contracts"].as_object().unwrap() {
            if v["address"].as_str().unwrap() == address {
                return Err(
                    format!("Contract {} already found in deployment logs", address).into(),
                );
            }
        }
    }
    Ok(())
}

fn post_process_deployments_json(
    mut deployments_json: Value,
) -> Result<Value, Box<dyn std::error::Error>> {
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
            latest[k] = if !v["proxy"].as_bool().unwrap_or(false) {
                json!({
                        "address": v["address"],
                        "proxy": v["proxy"],
                        "deploymentTxn": v["deploymentTxn"],
                        "timestamp": item["timestamp"]
                })
            } else {
                json!({
                        "address": v["address"],
                        "implementation": v["implementation"],
                        "proxy": v["proxy"],
                        "proxyType": v["proxyType"],
                        "deploymentTxn": v["deploymentTxn"],
                        "proxyAdmin": v["proxyAdmin"],
                        "timestamp": item["timestamp"]
                })
            };
            if !item["commitHash"].is_null() {
                latest[k]["commitHash"] = item["commitHash"].clone();
            }
            if !v["poolInitCodeHash"].is_null() {
                latest[k]["poolInitCodeHash"] = v["poolInitCodeHash"].clone();
            }
        }
    }
    deployments_json["history"] = Value::Array(history);
    deployments_json["latest"] = latest;
    Ok(deployments_json)
}

fn extract_constructor_inputs(
    constructor_params: Vec<Param>,
    args: Vec<DynSolValue>,
) -> Result<Value, Box<dyn std::error::Error>> {
    let mut result = json!({});
    // constuctor inputs and arguments should always have the same length because the abi encoded constructor args were decoded using the constructor inputs and validated
    for i in 0..constructor_params.len() {
        let input = constructor_params[i].clone();
        let value = args[i].clone();
        result[input.name] = serialize_value(input.clone(), value)?;
    }
    Ok(result)
}

fn serialize_value(param: Param, value: DynSolValue) -> Result<Value, Box<dyn std::error::Error>> {
    match value {
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
    }
}
