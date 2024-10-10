use crate::screens::screen_manager::{Screen, ScreenResult};
use crate::screens::types::select_or_enter::SelectOrEnterComponent;
use crate::state_manager::STATE_MANAGER;
use crate::ui::Buffer;
use crossterm::event::Event;

// Sets the rpc url for further operations
pub struct RpcUrlScreen {
    select_or_enter: SelectOrEnterComponent,
}

impl RpcUrlScreen {
    pub fn new() -> Self {
        let chain_id = STATE_MANAGER.app_state.lock().unwrap().chain_id.clone();
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
        }
        RpcUrlScreen {
            select_or_enter: SelectOrEnterComponent::new(
                "RPC URL".to_string(),
                pre_selected_rpcs,
                |input, _| input,
                |input, _| input,
            ),
        }
    }
}

impl Screen for RpcUrlScreen {
    fn render_content(&self, buffer: &mut Buffer) {
        self.select_or_enter.render(buffer);
    }

    fn handle_input(&mut self, event: Event) -> Result<ScreenResult, Box<dyn std::error::Error>> {
        let rpc_url = self.select_or_enter.handle_input(event);
        if rpc_url.is_some() {
            STATE_MANAGER.app_state.lock().unwrap().rpc_url = Some(rpc_url.unwrap());
            return Ok(ScreenResult::NextScreen(None));
        }
        Ok(ScreenResult::Continue)
    }

    fn execute(&mut self) {}
}
