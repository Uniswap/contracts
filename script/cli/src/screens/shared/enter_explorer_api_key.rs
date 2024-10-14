use crate::screens::screen_manager::{Screen, ScreenResult};
use crate::screens::types::enter_env_var::EnterEnvVarComponent;
use crate::state_manager::STATE_MANAGER;
use crate::ui::Buffer;
use crossterm::event::Event;

// Sets the rpc url for further operations
pub struct EnterExplorerApiKeyScreen {
    env_var_name: String,
    enter_env_var: EnterEnvVarComponent,
}

impl EnterExplorerApiKeyScreen {
    pub fn new() -> Result<Self, Box<dyn std::error::Error>> {
        let explorer = STATE_MANAGER.workflow_state.lock()?.block_explorer.clone();
        let mut env_var_name = "".to_string();
        if explorer.is_some() {
            env_var_name = explorer.unwrap().name.clone().to_uppercase() + "_API_KEY";
        }
        Ok(EnterExplorerApiKeyScreen {
            env_var_name: env_var_name.clone(),
            enter_env_var: EnterEnvVarComponent::new(env_var_name, |input, _| input),
        })
    }
}

impl Screen for EnterExplorerApiKeyScreen {
    fn render_content(&self, buffer: &mut Buffer) -> Result<(), Box<dyn std::error::Error>> {
        self.enter_env_var.render(buffer);
        Ok(())
    }

    fn handle_input(&mut self, event: Event) -> Result<ScreenResult, Box<dyn std::error::Error>> {
        let result = self.enter_env_var.handle_input(event);
        if result.is_some() {
            STATE_MANAGER.workflow_state.lock()?.explorer_api_key = result;
            return Ok(ScreenResult::NextScreen(None));
        }
        Ok(ScreenResult::Continue)
    }

    fn execute(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        if self.env_var_name.is_empty() {
            return Err("Could not find environment variable name for the explorer".into());
        }
        Ok(())
    }
}
