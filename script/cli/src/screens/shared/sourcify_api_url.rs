use crate::screens::screen_manager::{Screen, ScreenResult};
use crate::screens::types::text_input::TextInputComponent;
use crate::state_manager::STATE_MANAGER;
use crate::ui::Buffer;
use crossterm::event::Event;

pub struct SourcifyApiUrlScreen {
    text_input: TextInputComponent,
}

impl SourcifyApiUrlScreen {
    pub fn new() -> Result<Self, Box<dyn std::error::Error>> {
        let chain_id = STATE_MANAGER
            .workflow_state
            .lock()?
            .chain_id
            .clone()
            .ok_or("Chain ID not found")?;

        // Try chain-specific env var first, then fallback
        let env_var = format!("SOURCIFY_API_URL_{}", chain_id);
        let default_url = std::env::var(&env_var)
            .or_else(|_| std::env::var("SOURCIFY_API_URL"))
            .unwrap_or_default();

        Ok(SourcifyApiUrlScreen {
            text_input: TextInputComponent::new(false, default_url, |input, _| input),
        })
    }
}

impl Screen for SourcifyApiUrlScreen {
    fn render_content(&self, buffer: &mut Buffer) -> Result<(), Box<dyn std::error::Error>> {
        buffer.append_row_text("Enter the Sourcify API URL:\n\n");
        self.text_input.render(buffer);
        self.text_input.render_default_instructions(buffer);
        Ok(())
    }

    fn handle_input(&mut self, event: Event) -> Result<ScreenResult, Box<dyn std::error::Error>> {
        if let Some(url) = self.text_input.handle_input(event) {
            // Store in Explorer struct
            STATE_MANAGER
                .workflow_state
                .lock()?
                .block_explorer
                .as_mut()
                .ok_or("No explorer selected")?
                .sourcify_api_url = Some(url);
            Ok(ScreenResult::NextScreen(None))
        } else {
            Ok(ScreenResult::Continue)
        }
    }

    fn execute(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        Ok(())
    }
}
