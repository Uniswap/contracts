use crate::screens::screen_manager::{Screen, ScreenResult};
use crate::screens::types::text_input::TextInputComponent;
use crate::state_manager::STATE_MANAGER;
use crate::ui::Buffer;
use crate::util::screen_util::validate_address;
use crossterm::event::Event;

pub struct EnterAddressScreen {
    text_input: TextInputComponent,
}

impl EnterAddressScreen {
    pub fn new() -> Self {
        EnterAddressScreen {
            text_input: TextInputComponent::new(false, "".to_string(), validate_address),
        }
    }

    fn render_title(&self, buffer: &mut Buffer) {
        buffer.append_row_text("Please enter the contract address to register\n");
    }

    fn render_instructions(&self, buffer: &mut Buffer) {
        self.text_input.render_default_instructions(buffer);
    }
}

impl Screen for EnterAddressScreen {
    fn render_content(&self, buffer: &mut Buffer) {
        self.render_title(buffer);
        self.text_input.render(buffer);
        self.render_instructions(buffer);
    }

    fn handle_input(&mut self, event: Event) -> Result<ScreenResult, Box<dyn std::error::Error>> {
        let address = self.text_input.handle_input(event);
        if address.is_some() && address.unwrap().len() == 42 {
            return Ok(ScreenResult::NextScreen(None));
        }
        // if chain_id != None && !chain_id.clone().unwrap().is_empty() {
        //     STATE_MANAGER
        //         .app_state
        //         .lock()
        //         .unwrap()
        //         .set_chain_id(chain_id.unwrap());
        //     return Ok(ScreenResult::NextScreen(None));
        // }
        Ok(ScreenResult::Continue)
    }

    fn execute(&mut self) {
        // nothing to execute
    }
}
