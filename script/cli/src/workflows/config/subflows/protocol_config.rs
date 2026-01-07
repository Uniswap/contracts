use crate::screens::screen_manager::{Screen, ScreenResult};
use crate::screens::shared::generic_multi_select::GenericMultiSelectScreen;
use crate::screens::shared::generic_select::GenericSelectScreen;
use crate::screens::shared::generic_select_or_enter::GenericSelectOrEnterScreen;
use crate::state_manager::STATE_MANAGER;
use crate::util::screen_util::{validate_address, validate_bytes32, validate_number};
use crate::workflows::error_workflow::ErrorWorkflow;
use crate::workflows::workflow_manager::{process_nested_workflows, Workflow, WorkflowResult};
use alloy::primitives::Address;
use serde_json::Map;
use serde_json::Value;
use std::collections::HashSet;
use std::sync::{Arc, Mutex};

/// Converts an address string to checksummed format (EIP-55).
/// Returns None if the address is invalid.
fn to_checksummed(address: &str) -> Option<String> {
    address.parse::<Address>().ok().map(|a| a.to_checksum(None))
}

type Screens = Vec<Box<dyn Fn() -> Box<dyn Screen> + Send>>;

pub struct ProtocolConfigWorkflow {
    current_screen: isize,
    screens: Arc<Mutex<Screens>>,
    child_workflows: Vec<Box<dyn Workflow>>,
}

impl ProtocolConfigWorkflow {
    pub fn new(_protocol: String) -> Result<Self, Box<dyn std::error::Error>> {
        let contracts = STATE_MANAGER.workflow_state.lock()?.task["protocols"][_protocol.clone()]
            ["contracts"]
            .clone();

        let contract_selection = contracts
            .as_object()
            .ok_or("Contracts key not found in template task")?;

        if contract_selection.is_empty() {
            return Err("No contracts found for this protocol".into());
        }

        // set flag to deploy contracts for this protocol
        STATE_MANAGER.workflow_state.lock()?.task["protocols"][_protocol.clone()]["deploy"] =
            Value::Bool(true);

        let screens: Arc<Mutex<Screens>> = Arc::new(Mutex::new(Vec::new()));
        let protocol = Arc::new(_protocol.clone());

        let workflows_clone_outer = Arc::clone(&screens);
        let protocol_clone_outer = Arc::clone(&protocol);
        let protocol_name = STATE_MANAGER.workflow_state.lock()?.task["protocols"]
            [_protocol.clone()]["name"]
            .as_str()
            .unwrap_or(&_protocol)
            .to_string();
        screens.lock().unwrap().push(Box::new(move || {
            let workflows_clone_inner = Arc::clone(&workflows_clone_outer);
            let protocol_clone_inner = Arc::clone(&protocol_clone_outer);
            Box::new(GenericMultiSelectScreen::new(
                // we have to fetch the data here again because we can't move `contract_selection` here
                STATE_MANAGER.workflow_state.lock().unwrap().task["protocols"]
                    [protocol_clone_outer.to_string()]["contracts"]
                    .clone()
                    .as_object()
                    .unwrap()
                    .keys()
                    .cloned()
                    .collect(),
                format!(
                    "Which contracts do you want to deploy for {}?",
                    protocol_name
                ),
                Box::new(move |selected| {
                    handle_selected_contracts(
                        selected,
                        protocol_clone_inner.to_string(),
                        &workflows_clone_inner,
                    )
                }),
            )) as Box<dyn Screen>
        }));

        Ok(ProtocolConfigWorkflow {
            current_screen: -1,
            screens,
            child_workflows: vec![],
        })
    }
}

impl Workflow for ProtocolConfigWorkflow {
    fn next_screen(
        &mut self,
        new_workflows: Option<Vec<Box<dyn Workflow>>>,
    ) -> Result<WorkflowResult, Box<dyn std::error::Error>> {
        match process_nested_workflows(&mut self.child_workflows, new_workflows)? {
            WorkflowResult::NextScreen(screen) => Ok(WorkflowResult::NextScreen(screen)),
            WorkflowResult::Finished => {
                self.current_screen += 1;

                self.get_screen()
            }
        }
    }

    fn previous_screen(&mut self) -> Result<WorkflowResult, Box<dyn std::error::Error>> {
        if self.current_screen > 0 {
            self.current_screen -= 1;
        }
        // if we are back to the contract selection screen, remove all added screens
        if self.current_screen == 0 {
            self.screens.lock().unwrap().drain(1..);
        }
        self.get_screen()
    }

    fn handle_error(
        &mut self,
        error: Box<dyn std::error::Error>,
    ) -> Result<WorkflowResult, Box<dyn std::error::Error>> {
        self.display_error(error.to_string())
    }
}

impl ProtocolConfigWorkflow {
    fn get_screen(&self) -> Result<WorkflowResult, Box<dyn std::error::Error>> {
        if self.current_screen < self.screens.lock().unwrap().len() as isize {
            return Ok(WorkflowResult::NextScreen((self.screens.lock().unwrap()
                [self.current_screen as usize])(
            )));
        }
        Ok(WorkflowResult::Finished)
    }

    fn display_error(
        &mut self,
        error_message: String,
    ) -> Result<WorkflowResult, Box<dyn std::error::Error>> {
        self.child_workflows = vec![Box::new(ErrorWorkflow::new(error_message))];
        self.current_screen = 1000000;
        self.child_workflows[0].next_screen(None)
    }
}

pub fn handle_selected_contracts(
    selected: Vec<usize>,
    protocol: String,
    screens: &Mutex<Screens>,
) -> Result<ScreenResult, Box<dyn std::error::Error>> {
    let mut task = STATE_MANAGER.workflow_state.lock()?.task.clone();
    let contracts = task["protocols"][protocol.clone()]["contracts"].clone();
    // map selected to contract names
    let contract_names: Vec<String> = selected
        .iter()
        .map(|i| {
            contracts
                .as_object()
                .unwrap()
                .keys()
                .nth(*i)
                .unwrap()
                .to_string()
        })
        .collect();
    for contract_name in contract_names.clone() {
        // set flag to deploy this contract
        task["protocols"][protocol.clone()]["contracts"][contract_name.clone()]["deploy"] =
            Value::Bool(true);
    }
    let mut pointers = HashSet::new();
    // iterate over all selected contracts
    for contract_name in contract_names {
        let params_object = contracts[contract_name.clone()]["params"].clone();
        let params_map = params_object.as_object().unwrap_or(&Map::new()).clone();
        // iterate over all params for this contract
        for param in params_map.keys() {
            let mut param_path = vec![
                "protocols".to_string(),
                protocol.clone(),
                "contracts".to_string(),
                contract_name.clone(),
                "params".to_string(),
                param.clone(),
                "value".to_string(),
            ];
            // get default options to display to the user for this param
            let mut options = HashSet::new();
            // check if the param has a pointer
            if !params_object[param]["pointer"].is_null() {
                // a pointer points to a contract address which could be deployed alongside this contract
                // if the deploy flag is set to true for this pointer, the user doesn't need to enter this parameter, it will be fetched from the deployed contract automatically
                // if the deploy flag is set to false, enter the address field of the pointer contract
                // if another contract has the same dependency and the deploy flag is set to false, the user will not be prompted to enter this parameter again, instead, the address will be fetched from the value set in the previous step
                // e.g., NonfungiblePositionManager and SwapRouter have a pointer to UniswapV3Factory
                // if the deploy flag is set to true for UniswapV3Factory, the user doesn't need to enter the factory address
                // if the deploy flag is set to false for UniswapV3Factory, the user needs to enter the factory address when entering the params for NonfungiblePositionManager
                // when entering the params for SwapRouter, the factory address will already be set, so the user doesn't need to enter it again
                let pointer = params_object[param]["pointer"].as_str().unwrap();

                // Start from the root task and traverse the pointer path
                let mut target_contract = &task;
                for part in pointer.split('.').collect::<Vec<&str>>() {
                    target_contract = &target_contract[part];
                }
                if target_contract["deploy"].eq(&Value::Bool(true)) {
                    // if the deploy flag is set to true, the user doesn't need to enter this parameter, it will be fetched from the deployed contract automatically
                    continue;
                } else if target_contract["address"].is_null() && !pointers.contains(pointer) {
                    // if the address is not set, add it to the pointers map, so we don't add it multiple times
                    pointers.insert(pointer.to_string());
                    param_path = pointer
                        .split('.')
                        .map(String::from)
                        .collect::<Vec<String>>();
                    param_path.push("address".to_string());

                    // if the target contract has a lookup field, check the deployment log for latest/previous addresses
                    options.extend(lookup_deployment_log(target_contract.clone())?);
                } else {
                    // an address was found, skip this parameter
                    continue;
                }
            }
            // if the value is not null, add the default value to the options
            if !params_object[param]["value"].is_null() {
                match &params_object[param]["value"] {
                    Value::String(s) => { options.insert(s.to_string()); },
                    Value::Number(n) => { options.insert(n.to_string()); },
                    Value::Bool(b) => { options.insert(b.to_string()); },
                    _ => return Err("Error fetching default value: Nested types like arrays or objects are not supported".into()),
                }
            }
            // if the param has a lookup field, check the deployment log for latest/previous addresses
            options.extend(lookup_deployment_log(params_object[param].clone())?);

            let name = params_object.clone()[param]["name"]
                .as_str()
                .unwrap_or(param)
                .to_string();
            let contract_name_clone = contracts[contract_name.clone()]["name"]
                .as_str()
                .unwrap_or(&contract_name)
                .to_string();
            // default to address because contract addresses don't have the type defined (e.g., when UniswapV2Factory is looked up)
            let param_type = params_object[param]["type"]
                .as_str()
                .unwrap_or("address")
                .to_string()
                .clone();

            add_screen(
                screens,
                param_type,
                param_path,
                options,
                format!("{} for {}", name, contract_name_clone),
            );
        }

        let dependencies = contracts[contract_name.clone()]["dependencies"].clone();
        if dependencies.is_array() {
            for dependency in dependencies.as_array().unwrap() {
                let dependency_name = dependency.as_str().unwrap().to_string();
                let pointer = "dependencies.".to_string() + &dependency_name;
                let dependency_object = task["dependencies"][dependency_name.clone()].clone();
                if dependency_object["value"].is_null() && !pointers.contains(&pointer) {
                    pointers.insert(pointer);
                    let param_path = vec![
                        "dependencies".to_string(),
                        dependency_name.clone(),
                        "value".to_string(),
                    ];
                    let options = lookup_deployment_log(dependency_object.clone())?;
                    let name = dependency_object.clone()["name"]
                        .as_str()
                        .unwrap_or(&dependency_name)
                        .to_string();
                    let param_type = dependency_object["type"]
                        .as_str()
                        .unwrap_or("address")
                        .to_string()
                        .clone();
                    add_screen(screens, param_type, param_path, options, name.to_string());
                }
            }
        }
    }
    STATE_MANAGER.workflow_state.lock()?.task = task;
    Ok(ScreenResult::NextScreen(None))
}

fn lookup_deployment_log(mut lookup: Value) -> Result<HashSet<String>, Box<dyn std::error::Error>> {
    if !lookup["lookup"].is_object() {
        return Ok(HashSet::new());
    }
    lookup = lookup["lookup"].clone();
    let chain_id = STATE_MANAGER
        .workflow_state
        .lock()?
        .chain_id
        .clone()
        .unwrap();
    let working_dir = STATE_MANAGER.working_directory.clone();
    let deployments_file = working_dir
        .join("deployments")
        .join("json")
        .join(format!("{}.json", chain_id));
    let mut options = HashSet::new();

    let deployments_json = if deployments_file.exists() {
        let contents = std::fs::read_to_string(&deployments_file)?;
        serde_json::from_str(&contents)?
    } else {
        serde_json::json!({
            "chainId": chain_id,
            "latest": {},
            "history": []
        })
    };

    if lookup["latest"].is_string() {
        let latest_address =
            deployments_json["latest"][lookup["latest"].as_str().unwrap()]["address"].as_str();
        if let Some(latest_address) = latest_address {
            if let Some(checksummed) = to_checksummed(latest_address) {
                options.insert(checksummed);
            }
        }
    }
    if lookup["history"].is_array() {
        for history_item in lookup["history"].as_array().unwrap() {
            if !history_item.is_string() {
                continue;
            }
            let param_path = history_item
                .as_str()
                .unwrap()
                .split('.')
                .collect::<Vec<&str>>();
            for deployment in deployments_json["history"].as_array().unwrap() {
                let contracts = &deployment["contracts"];

                // First part is contract name - find matching key (with or without tag)
                let contract_name = param_path[0];
                let matching_key = contracts.as_object().and_then(|obj| {
                    obj.keys().find(|k| {
                        *k == contract_name || k.starts_with(&format!("{}#", contract_name))
                    })
                });

                if let Some(key) = matching_key {
                    let mut option = &contracts[key];
                    for part in param_path.iter().skip(1) {
                        option = &option[*part];
                    }
                    if option.is_string() {
                        if let Some(checksummed) = to_checksummed(option.as_str().unwrap()) {
                            options.insert(checksummed);
                        }
                    }
                }
            }
        }
    }

    Ok(options)
}

// Returns a function that validates the user input for the given param type
fn get_input_validator(param_type: &str) -> fn(String, usize) -> String {
    match param_type {
        "address" => validate_address,
        "bytes32" => validate_bytes32,
        "uint256" => validate_number,
        _ => |s, _| s,
    }
}

// Adds a new screen to handle the input of a param
fn add_screen(
    screens: &Mutex<Screens>,
    param_type: String,
    param_path: Vec<String>,
    options: HashSet<String>,
    title: String,
) {
    if param_type == "bool" {
        screens.lock().unwrap().push(Box::new(move || {
            Box::new(GenericSelectScreen::new(
                vec!["True".to_string(), "False".to_string()],
                title.clone(),
                {
                    let param_type_clone = param_type.clone();
                    let param_path_clone = param_path.clone();
                    Box::new(move |result| {
                        update_task(
                            param_type_clone.clone(),
                            param_path_clone.clone(),
                            if result == 0 {
                                "True".to_string()
                            } else {
                                "False".to_string()
                            },
                        )
                    })
                },
            )) as Box<dyn Screen>
        }));
    } else {
        screens.lock().unwrap().push(Box::new(move || {
            Box::new(GenericSelectOrEnterScreen::new(
                title.clone(),
                options.clone().into_iter().collect(),
                get_input_validator(&param_type),
                |s, _| s,
                false,
                {
                    let param_type_clone = param_type.clone();
                    let param_path_clone = param_path.clone();
                    Box::new(move |result| {
                        update_task(param_type_clone.clone(), param_path_clone.clone(), result)
                    })
                },
            )) as Box<dyn Screen>
        }));
    }
}

// Write the entered param to the task json
fn update_task(
    param_type: String,
    path: Vec<String>,
    value: String,
) -> Result<ScreenResult, Box<dyn std::error::Error>> {
    let mut task = STATE_MANAGER.workflow_state.lock()?.task.clone();
    let mut target = &mut task;
    for part in path.iter() {
        target = &mut target[part];
    }
    let formatted_value = match param_type.as_str() {
        "bool" => Value::Bool(value == "True"),
        _ => Value::String(value),
    };
    *target = formatted_value;
    STATE_MANAGER.workflow_state.lock()?.task = task;
    Ok(ScreenResult::NextScreen(None))
}
