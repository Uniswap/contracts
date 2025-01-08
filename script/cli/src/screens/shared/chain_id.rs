use crate::screens::screen_manager::{Screen, ScreenResult};
use crate::screens::types::text_input::TextInputComponent;
use crate::state_manager::STATE_MANAGER;
use crate::ui::Buffer;
use crate::util::screen_util::validate_number;
use crossterm::event::Event;

pub struct ChainIdScreen {
    text_input: TextInputComponent,
    hook: Option<Box<dyn Fn(String) -> Result<ScreenResult, Box<dyn std::error::Error>> + Send>>,
}

impl ChainIdScreen {
    pub fn new(
        hook: Option<
            Box<dyn Fn(String) -> Result<ScreenResult, Box<dyn std::error::Error>> + Send>,
        >,
    ) -> Self {
        ChainIdScreen {
            text_input: TextInputComponent::new(false, "".to_string(), validate_number),
            hook,
        }
    }

    fn render_title(&self, buffer: &mut Buffer) {
        let chain_id = self.text_input.text.clone();
        if chain_id.is_empty() {
            buffer.append_row_text("Please enter the chain id of the network\n");
            return;
        }
        let chain_name = STATE_MANAGER.get_chain(chain_id);
        if chain_name.is_none() {
            buffer.append_row_text("Unknown network\n");
            return;
        }
        buffer.append_row_text(&format!("Selected network: {}\n", chain_name.unwrap().name));
    }

    fn render_instructions(&self, buffer: &mut Buffer) {
        self.text_input.render_default_instructions(buffer);
    }
}

impl Screen for ChainIdScreen {
    fn render_content(&self, buffer: &mut Buffer) -> Result<(), Box<dyn std::error::Error>> {
        self.render_title(buffer);
        self.text_input.render(buffer);
        self.render_instructions(buffer);
        Ok(())
    }

    fn handle_input(&mut self, event: Event) -> Result<ScreenResult, Box<dyn std::error::Error>> {
        let chain_id = self.text_input.handle_input(event);
        if chain_id.is_some() && !chain_id.clone().unwrap().is_empty() {
            STATE_MANAGER.workflow_state.lock()?.chain_id = chain_id.clone();
            if let Some(hook) = &self.hook {
                return hook(chain_id.unwrap());
            } else {
                return Ok(ScreenResult::NextScreen(None));
            }
        }
        Ok(ScreenResult::Continue)
    }

    fn execute(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        Ok(())
    }
}
