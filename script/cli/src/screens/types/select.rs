use crate::constants;
use crate::ui::Buffer;
use crossterm::event::{Event, KeyCode};

pub struct SelectScreen {
    pub options: Vec<String>,
    selected_index: usize,
}

impl SelectScreen {
    pub fn new(options: Vec<String>) -> Self {
        SelectScreen {
            options,
            selected_index: 0,
        }
    }

    pub fn render_default_instructions(&self, buffer: &mut Buffer) {
        buffer.append_row_text_color(
            "\nUse ↑↓ arrows to navigate, 'Enter' to select",
            constants::INSTRUCTIONS_COLOR,
        );
    }

    pub fn render(&self, buffer: &mut Buffer) {
        for (i, option) in self.options.iter().enumerate() {
            let color = if i == self.selected_index {
                constants::SELECTION_COLOR
            } else {
                constants::DEFAULT_COLOR
            };
            let prefix = if i == self.selected_index { "> " } else { "  " };
            buffer.append_row_text_color(&format!("{}{}", prefix, option), color);
        }
    }

    pub fn handle_input(&mut self, event: Event) -> Option<usize> {
        if let Event::Key(key_event) = event {
            match key_event.code {
                KeyCode::Up => {
                    if self.selected_index == 0 {
                        self.selected_index = self.options.len() - 1;
                    } else {
                        self.selected_index -= 1;
                    }
                }
                KeyCode::Down => {
                    if self.selected_index == self.options.len() - 1 {
                        self.selected_index = 0;
                    } else {
                        self.selected_index += 1;
                    }
                }
                KeyCode::Enter => {
                    return Some(self.selected_index);
                }
                _ => {}
            }
        }
        None
    }
}
