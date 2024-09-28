use crate::ui::Buffer;
use crossterm::{
    event::{Event, KeyCode},
    style::Color,
};

pub struct MultipleChoiceScreen {
    options: Vec<String>,
    hovered_index: usize,
    selected_indices: Vec<usize>,
}
impl MultipleChoiceScreen {
    pub fn new(options: Vec<String>) -> Self {
        MultipleChoiceScreen {
            options,
            hovered_index: 0,
            selected_indices: Vec::new(),
        }
    }

    pub fn render(&self, buffer: &mut Buffer) {
        for (i, option) in self.options.iter().enumerate() {
            let color = if self.hovered_index == i {
                Color::Rgb {
                    r: 255,
                    g: 20,
                    b: 147,
                }
            } else {
                Color::Reset
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
                    return Some(self.selected_indices.clone());
                }
                _ => {}
            }
        }
        None
    }
}
