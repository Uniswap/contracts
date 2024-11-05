use crate::libs::web3::Web3Lib;
use crate::screens::screen_manager::ScreenResult;
use crate::screens::shared::generic_select_or_enter::GenericSelectOrEnterScreen;
use crate::state_manager::STATE_MANAGER;
use crate::workflows::workflow_manager::WorkflowResult;

pub fn get_rpc_url_screen() -> Result<WorkflowResult, Box<dyn std::error::Error>> {
    let chain_id: Option<String> = STATE_MANAGER.workflow_state.lock()?.chain_id.clone();
    let mut pre_selected_rpcs = vec![];
    if chain_id.is_some()
        && STATE_MANAGER
            .chains
            .contains_key(&chain_id.clone().unwrap())
    {
        pre_selected_rpcs = STATE_MANAGER
            .chains
            .get(&chain_id.unwrap())
            .unwrap()
            .rpc_url
            .clone();
        pre_selected_rpcs.push("${RPC_URL}".to_string());
    }
    return Ok(WorkflowResult::NextScreen(Box::new(
        GenericSelectOrEnterScreen::new(
            "RPC URL".to_string(),
            pre_selected_rpcs,
            |input, _| input,
            |input, _| input,
            false,
            Box::new(handle_rpc_url),
        ),
    )));
}

fn handle_rpc_url(rpc_url: String) -> Result<ScreenResult, Box<dyn std::error::Error>> {
    STATE_MANAGER.workflow_state.lock()?.web3 = Some(Web3Lib::new(rpc_url)?);
    Ok(ScreenResult::NextScreen(None))
}
