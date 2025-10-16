use crate::libs::explorer::{Explorer, SupportedExplorerType};
use crate::screens::screen_manager::{Screen, ScreenResult};
use crate::screens::types::select::SelectComponent;
use crate::state_manager::STATE_MANAGER;
use crate::ui::Buffer;
use crossterm::event::Event;

pub struct SelectVerifierTypeScreen {
    explorer: Explorer,
    select: SelectComponent,
}

impl SelectVerifierTypeScreen {
    pub fn new() -> Result<Self, Box<dyn std::error::Error>> {
        let explorer = STATE_MANAGER
            .workflow_state
            .lock()?
            .block_explorer
            .clone()
            .ok_or("No explorer selected")?;

        let api_url = format!("{}/api?", explorer.url);

        let options = vec![
            format!("Try as Blockscout (API URL: {})", api_url),
            "Use Sourcify (custom API URL)".to_string(),
        ];

        Ok(SelectVerifierTypeScreen {
            explorer,
            select: SelectComponent::new(options),
        })
    }
}

impl Screen for SelectVerifierTypeScreen {
    fn render_content(&self, buffer: &mut Buffer) -> Result<(), Box<dyn std::error::Error>> {
        buffer.append_row_text(&format!(
            "Explorer: {} ({})\n",
            self.explorer.name, self.explorer.url
        ));
        buffer.append_row_text("This explorer type is unknown. Please select:\n\n");

        self.select.render(buffer);

        self.select.render_default_instructions(buffer);

        Ok(())
    }

    fn handle_input(&mut self, event: Event) -> Result<ScreenResult, Box<dyn std::error::Error>> {
        if let Some(index) = self.select.handle_input(event) {
            match index {
                0 => {
                    // Set as Blockscout
                    STATE_MANAGER
                        .workflow_state
                        .lock()?
                        .block_explorer
                        .as_mut()
                        .unwrap()
                        .explorer_type = SupportedExplorerType::Blockscout;
                    Ok(ScreenResult::NextScreen(None))
                }
                1 => {
                    // Set as Sourcify
                    let mut state = STATE_MANAGER.workflow_state.lock()?;
                    let explorer = state.block_explorer.as_mut().unwrap();

                    // If there's a URL in the explorer.url field (from custom URL entry),
                    // move it to sourcify_api_url so we don't need to prompt again
                    if !explorer.url.is_empty() && explorer.sourcify_api_url.is_none() {
                        explorer.sourcify_api_url = Some(explorer.url.clone());
                    }

                    explorer.explorer_type = SupportedExplorerType::Sourcify;
                    Ok(ScreenResult::NextScreen(None))
                }
                _ => Ok(ScreenResult::Continue),
            }
        } else {
            Ok(ScreenResult::Continue)
        }
    }

    fn execute(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        Ok(())
    }
}
