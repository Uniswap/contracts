use crate::screens::screen_manager::{Screen, ScreenResult};
use crate::screens::types::text_input::TextInputComponent;
use crate::ui::Buffer;
use crate::util::screen_util::validate_address;
use crossterm::event::Event;

type Hook = Box<dyn Fn(String) -> Result<ScreenResult, Box<dyn std::error::Error>> + Send>;

pub struct EnterAddressScreen {
    text_input: TextInputComponent,
    title: String,
    hook: Option<Hook>,
}

impl EnterAddressScreen {
    pub fn new(title: String, hook: Option<Hook>) -> Self {
        EnterAddressScreen {
            text_input: TextInputComponent::new(false, "".to_string(), validate_address),
            title,
            hook,
        }
    }

    fn render_title(&self, buffer: &mut Buffer) {
        buffer.append_row_text(&self.title);
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
        if let Some(address) = address {
            if address.len() == 42 {
                if let Some(hook) = &self.hook {
                    return hook(address);
                }
                return Ok(ScreenResult::NextScreen(None));
            }
        }
        Ok(ScreenResult::Continue)
    }

    fn execute(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        Ok(())
    }
}
