use crate::screens::screen_manager::{Screen, ScreenResult};
use crate::screens::types::multiple_choice::MultipleChoiceComponent;
use crate::ui::Buffer;
use crossterm::event::Event;

pub struct ProtocolSelectionScreen {
    multiple_choice_screen: MultipleChoiceComponent,
}

impl ProtocolSelectionScreen {
    pub fn new() -> Self {
        let options = vec![
            "Uniswap v2".to_string(),
            "Uniswap v3".to_string(),
            "Permit 2".to_string(),
        ];
        ProtocolSelectionScreen {
            multiple_choice_screen: MultipleChoiceComponent::new(options),
        }
    }

    fn render_title(&self, buffer: &mut Buffer) {
        buffer.append_row_text("Which protocols do you want to deploy?\n");
    }

    fn render_instructions(&self, buffer: &mut Buffer) {
        self.multiple_choice_screen
            .render_default_instructions(buffer);
    }
}

impl Screen for ProtocolSelectionScreen {
    fn render_content(&self, buffer: &mut Buffer) {
        self.render_title(buffer);
        self.multiple_choice_screen.render(buffer);
        self.render_instructions(buffer);
    }

    fn handle_input(&mut self, event: Event) -> Result<ScreenResult, Box<dyn std::error::Error>> {
        let result = self.multiple_choice_screen.handle_input(event);
        if result.is_some() && !result.unwrap().is_empty() {
            return Ok(ScreenResult::NextScreen(None));
        }
        Ok(ScreenResult::Continue)
    }

    fn execute(&mut self) {
        // nothing to execute
    }
}
