use crate::screen_manager::{Screen, Workflow};
use crate::screens::types::multiple_choice::MultipleChoiceScreen;
use crate::ui::Buffer;
use crossterm::event::Event;

pub struct ProtocolSelectionScreen {
    multiple_choice_screen: MultipleChoiceScreen,
}

impl ProtocolSelectionScreen {
    pub fn new() -> Self {
        let options = vec![
            "Uniswap v2".to_string(),
            "Uniswap v3".to_string(),
            "Permit 2".to_string(),
        ];
        ProtocolSelectionScreen {
            multiple_choice_screen: MultipleChoiceScreen::new(options),
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

    fn handle_input(&mut self, event: Event) -> Option<Vec<Box<dyn Workflow>>> {
        let result = self.multiple_choice_screen.handle_input(event);
        if result.is_some() && !result.unwrap().is_empty() {
            return Some(vec![]);
        }
        None
    }

    fn execute(&mut self) {
        // nothing to execute
    }
}
