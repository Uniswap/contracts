use crate::constants;
use crate::ui::Buffer;
use crossterm::event::Event;

pub struct TextDisplayComponent {
    pub text: String,
}

impl TextDisplayComponent {
    pub fn new(text: String) -> Self {
        TextDisplayComponent { text }
    }

    pub fn render(&self, buffer: &mut Buffer) {
        buffer.append_row_text(&self.text);
        buffer.append_row_text_color(&"> Press any key to continue", constants::SELECTION_COLOR);
    }

    pub fn handle_input(&mut self, event: Event) -> bool {
        if let Event::Key(_) = event {
            return true;
        }
        false
    }
}
