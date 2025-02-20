use crate::constants;
use crate::ui::Buffer;
use crossterm::event::{Event, KeyCode};

pub struct MultipleChoiceComponent {
    options: Vec<String>,
    hovered_index: usize,
    selected_indices: Vec<usize>,
}
impl MultipleChoiceComponent {
    pub fn new(options: Vec<String>) -> Self {
        MultipleChoiceComponent {
            options,
            hovered_index: 0,
            selected_indices: Vec::new(),
        }
    }

    pub fn render_default_instructions(&self, buffer: &mut Buffer) {
        buffer.append_row_text_color(
            "\nUse ↑↓ arrows to navigate, 'Space' to select, 'Enter' to confirm",
            constants::INSTRUCTIONS_COLOR,
        );
    }

    pub fn render(&self, buffer: &mut Buffer) {
        for (i, option) in self.options.iter().enumerate() {
            let color = if self.hovered_index == i {
                constants::SELECTION_COLOR
            } else {
                constants::DEFAULT_COLOR
            };
            let prefix = if self.selected_indices.contains(&i) {
                "● "
            } else {
                "○ "
            };
            buffer.append_row_text_color(&format!("{}{}", prefix, option), color);
        }
    }

    pub fn handle_input(&mut self, event: Event) -> Option<Vec<usize>> {
        if let Event::Key(key_event) = event {
            match key_event.code {
                KeyCode::Up => {
                    if self.hovered_index > 0 {
                        self.hovered_index -= 1;
                    }
                }
                KeyCode::Down => {
                    if self.hovered_index < self.options.len() - 1 {
                        self.hovered_index += 1;
                    }
                }
                KeyCode::Char(' ') => {
                    if self.selected_indices.contains(&self.hovered_index) {
                        self.selected_indices.retain(|&x| x != self.hovered_index);
                    } else {
                        self.selected_indices.push(self.hovered_index);
                    }
                }
                KeyCode::Enter => {
                    let mut sorted_indices = self.selected_indices.clone();
                    sorted_indices.sort();
                    return Some(sorted_indices);
                }
                _ => {}
            }
        }
        None
    }
}
