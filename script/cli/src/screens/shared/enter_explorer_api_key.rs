use crate::libs::explorer::SupportedExplorerType;
use crate::screens::screen_manager::{Screen, ScreenResult};
use crate::screens::types::enter_env_var::EnterEnvVarComponent;
use crate::state_manager::STATE_MANAGER;
use crate::ui::Buffer;
use crossterm::event::Event;

pub struct EnterExplorerApiKeyScreen {
    env_var_name: String,
    explorer_type: SupportedExplorerType,
    enter_env_var: EnterEnvVarComponent,
}

impl EnterExplorerApiKeyScreen {
    pub fn new() -> Result<Self, Box<dyn std::error::Error>> {
        let state = STATE_MANAGER.workflow_state.lock()?;
        let explorer = state.block_explorer.clone().ok_or("No explorer selected")?;
        let chain_id = state.chain_id.clone().ok_or("Chain ID not found")?;

        // Explorer type must be resolved before reaching this screen
        if explorer.explorer_type == SupportedExplorerType::Unknown {
            return Err("Explorer type must be selected before entering API key. This is a workflow error.".into());
        }

        let env_var_name = explorer.explorer_type.to_env_var_name(&chain_id);
        let explorer_type = explorer.explorer_type.clone();

        Ok(EnterExplorerApiKeyScreen {
            env_var_name: env_var_name.clone(),
            explorer_type,
            enter_env_var: EnterEnvVarComponent::new(env_var_name, |input, _| input),
        })
    }
}

impl Screen for EnterExplorerApiKeyScreen {
    fn render_content(&self, buffer: &mut Buffer) -> Result<(), Box<dyn std::error::Error>> {
        let hint = match self.explorer_type {
            SupportedExplorerType::EtherscanV2 => "(Required for Etherscan verification)",
            SupportedExplorerType::Blockscout => "(Keep empty if no API key required)",
            SupportedExplorerType::Sourcify => "(Keep empty if no API key required)",
            SupportedExplorerType::Unknown => {
                // This should never happen due to validation in new()
                return Err("Invalid explorer type: Unknown".into());
            }
        };

        buffer.append_row_text(&format!("{}\n\n", hint));
        self.enter_env_var.render(buffer);
        Ok(())
    }

    fn handle_input(&mut self, event: Event) -> Result<ScreenResult, Box<dyn std::error::Error>> {
        let result = self.enter_env_var.handle_input(event);
        if result.is_some() {
            let api_key = result.clone().unwrap_or_default();

            // Validate: Etherscan requires key, others optional
            if self.explorer_type == SupportedExplorerType::EtherscanV2 && api_key.is_empty() {
                return Err("Etherscan API key is required".into());
            }

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
