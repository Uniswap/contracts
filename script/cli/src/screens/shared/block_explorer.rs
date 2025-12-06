use crate::libs::explorer::{Explorer, SupportedExplorerType};
use crate::screens::screen_manager::{Screen, ScreenResult};
use crate::screens::types::select_or_enter::SelectOrEnterComponent;
use crate::state_manager::STATE_MANAGER;
use crate::ui::Buffer;
use crossterm::event::Event;

// Sets the block explorer for further operations
pub struct BlockExplorerScreen {
    select_or_enter: SelectOrEnterComponent,
    explorers: Vec<Explorer>,
}

impl BlockExplorerScreen {
    pub fn new() -> Result<Self, Box<dyn std::error::Error>> {
        let state = STATE_MANAGER.workflow_state.lock()?;
        let chain_id = state.chain_id.clone().ok_or("Chain ID not found")?;
        drop(state);

        let mut pre_selected_explorers = vec![];
        let mut explorers = vec![];

        if STATE_MANAGER.chains.contains_key(&chain_id) {
            explorers = STATE_MANAGER
                .get_chain(chain_id.clone())
                .unwrap()
                .explorers
                .clone()
                .into_iter()
                .filter(|explorer| {
                    // Show all explorers - Unknown types will require user selection
                    !explorer.url.is_empty()
                })
                .collect();

            pre_selected_explorers = explorers
                .clone()
                .into_iter()
                .map(|explorer| format!("{} ({})", explorer.url, explorer.explorer_type.name()))
                .collect();
        }

        // Always add custom URL options at the end
        pre_selected_explorers.push(format!("${{EXPLORER_URL_{}}}", chain_id));

        Ok(BlockExplorerScreen {
            select_or_enter: SelectOrEnterComponent::new(
                "Select a block explorer or enter the explorer URL".to_string(),
                false,
                pre_selected_explorers,
                |input, _| input,
                |input, _| input,
            ),
            explorers,
        })
    }
}

impl Screen for BlockExplorerScreen {
    fn render_content(&self, buffer: &mut Buffer) -> Result<(), Box<dyn std::error::Error>> {
        self.select_or_enter.render(buffer);
        Ok(())
    }

    fn handle_input(&mut self, event: Event) -> Result<ScreenResult, Box<dyn std::error::Error>> {
        let result = self.select_or_enter.handle_input(event);
        if let Some(result) = result {
            // Check if user entered a custom URL (not from the explorer list)
            let selected_index = self.select_or_enter.get_selected_index();

            if selected_index < self.explorers.len() {
                // User selected an existing explorer from the list
                STATE_MANAGER.workflow_state.lock()?.block_explorer =
                    Some(self.explorers[selected_index].clone());
            } else {
                // User selected custom URL or entered manually
                // Create a new Explorer with Unknown type - will be resolved later
                let custom_explorer = Explorer {
                    name: "Custom".to_string(),
                    url: result,
                    standard: "custom".to_string(),
                    explorer_type: SupportedExplorerType::Unknown,
                    sourcify_api_url: None,
                    oklink_api_url: None,
                };
                STATE_MANAGER.workflow_state.lock()?.block_explorer = Some(custom_explorer);
            }
            return Ok(ScreenResult::NextScreen(None));
        }
        Ok(ScreenResult::Continue)
    }

    fn execute(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        Ok(())
    }
}
