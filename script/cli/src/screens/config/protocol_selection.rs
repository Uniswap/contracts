use crate::screen_manager::Screen;
use crate::screens::types::multiple_choice::MultipleChoiceScreen;
use crate::ui::Buffer;
use crossterm::{event::Event, style::Color};

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
}

impl Screen for ProtocolSelectionScreen {
    fn render_content(&self, buffer: &mut Buffer) {
        self.multiple_choice_screen.render(buffer);
    }

    fn handle_input(&mut self, event: Event) -> Vec<Box<dyn Screen>> {
        let _ = self.multiple_choice_screen.handle_input(event);
        vec![]
    }

    fn render_title(&self, buffer: &mut Buffer) {
        buffer.append_row_text("Which protocols do you want to deploy?\n");
    }

    fn render_description(&self, _: &mut Buffer) {}

    fn render_error(&self, _: &mut Buffer) {}

    fn render_warning(&self, _: &mut Buffer) {}

    fn render_instructions(&self, buffer: &mut Buffer) {
        buffer.append_row_text_color(
            "\nUse ↑↓ arrows to navigate, Space to select, Enter to confirm, 'q' to quit",
            Color::Blue,
        );
    }
}
