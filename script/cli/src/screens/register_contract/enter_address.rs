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
    fn render_content(&self, buffer: &mut Buffer) -> Result<(), Box<dyn std::error::Error>> {
        self.render_title(buffer);
        self.text_input.render(buffer);
        self.render_instructions(buffer);
        Ok(())
    }

    fn handle_input(&mut self, event: Event) -> Result<ScreenResult, Box<dyn std::error::Error>> {
        let address = self.text_input.handle_input(event);
        if address.is_some() && address.clone().unwrap().len() == 42 {
            STATE_MANAGER
                .workflow_state
                .lock()
                .unwrap()
                .register_contract_data
                .address = address;
            return Ok(ScreenResult::NextScreen(None));
        }
        Ok(ScreenResult::Continue)
    }

    fn execute(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        Ok(())
    }
}
