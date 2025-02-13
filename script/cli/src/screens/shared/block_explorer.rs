use crate::libs::explorer::{Explorer, SupportedExplorerType};
use crate::screens::screen_manager::{Screen, ScreenResult};
use crate::screens::types::select::SelectComponent;
use crate::state_manager::STATE_MANAGER;
use crate::ui::Buffer;
use crossterm::event::Event;

// Sets the block explorer for further operations
pub struct BlockExplorerScreen {
    explorer_select: SelectComponent,
    explorers: Vec<Explorer>,
}

impl BlockExplorerScreen {
    pub fn new() -> Result<Self, Box<dyn std::error::Error>> {
        let chain_id = STATE_MANAGER.workflow_state.lock()?.chain_id.clone();
        let mut pre_selected_explorers = vec![];
        let mut explorers = vec![];
        if chain_id.is_some()
            && STATE_MANAGER
                .chains
                .contains_key(&chain_id.clone().unwrap())
        {
            explorers = STATE_MANAGER
                .get_chain(chain_id.unwrap().clone())
                .unwrap()
                .explorers
                .clone()
                .into_iter()
                .filter(|explorer| {
                    explorer.explorer_type == SupportedExplorerType::Blockscout
                        || explorer.explorer_type == SupportedExplorerType::EtherscanV2
                        || explorer.explorer_type == SupportedExplorerType::Etherscan
                })
                .collect();

            pre_selected_explorers = explorers
                .clone()
                .into_iter()
                .map(|explorer| format!("{} ({})", explorer.url, explorer.explorer_type.name()))
                .collect();
        }
        if explorers.is_empty() {
            return Err("No block explorer found".into());
        }
        Ok(BlockExplorerScreen {
            explorer_select: SelectComponent::new(pre_selected_explorers),
            explorers,
        })
    }
}

impl Screen for BlockExplorerScreen {
    fn render_content(&self, buffer: &mut Buffer) -> Result<(), Box<dyn std::error::Error>> {
        buffer.append_row_text("Select a block explorer\n");
        self.explorer_select.render(buffer);
        self.explorer_select.render_default_instructions(buffer);
        Ok(())
    }

    fn handle_input(&mut self, event: Event) -> Result<ScreenResult, Box<dyn std::error::Error>> {
        let result = self.explorer_select.handle_input(event);
        if result.is_some() {
            STATE_MANAGER.workflow_state.lock()?.block_explorer =
                Some(self.explorers[result.unwrap()].clone());
            return Ok(ScreenResult::NextScreen(None));
        }
        Ok(ScreenResult::Continue)
    }

    fn execute(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        Ok(())
    }
}
