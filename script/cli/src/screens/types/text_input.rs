use crate::ui::Buffer;
use crossterm::{
    event::{Event, KeyCode, KeyModifiers},
    style::{Attribute, Color, SetAttribute},
};

pub struct TextInputScreen {
    pub text: String,
    hidden: bool,
    cursor_position: usize,
    validate_input: fn(String) -> String,
}

impl TextInputScreen {
    pub fn new(hidden: bool, validate_input: fn(String) -> String) -> Self {
        TextInputScreen {
            text: String::new(),
            hidden,
            cursor_position: 0,
            validate_input,
        }
    }

    pub fn render(&self, buffer: &mut Buffer) {
        let color = Color::Reset;
        let cursor_position = self.cursor_position;
        let mut text = if self.hidden {
            "*".repeat(self.text.len()) + " "
        } else {
            self.text.clone() + " "
        };
        // Create an inverted cursor
        let cursor_char = self.text[cursor_position..].chars().next().unwrap_or(' ');
        let inverted_cursor = format!(
            "{}{}{}",
            SetAttribute(Attribute::Reverse),
            cursor_char,
            SetAttribute(Attribute::Reset)
        );

        text.replace_range(
            self.cursor_position..self.cursor_position + 1,
            &inverted_cursor,
        );
        buffer.append_row_text_color(&text, color);
    }

    pub fn handle_input(&mut self, event: Event) -> Option<String> {
        if let Event::Key(key_event) = event {
            match (key_event.modifiers, key_event.code) {
                (KeyModifiers::NONE, KeyCode::Char(c)) => {
                    self.text.insert(self.cursor_position, c);
                    let new_text = (self.validate_input)(self.text.clone());
                    if new_text.len() == self.text.len() {
                        self.cursor_position += 1
                    }
                    if self.cursor_position > self.text.len() {
                        self.cursor_position = self.text.len();
                    }
                    self.text = new_text;
                }
                // Command + Backspace
                (KeyModifiers::CONTROL, KeyCode::Char('u')) => {
                    self.text = String::new();
                    self.cursor_position = 0;
                }
                // Control + Backspace / Alt + Backspace
                (KeyModifiers::CONTROL, KeyCode::Char('h'))
                | (KeyModifiers::CONTROL, KeyCode::Char('w')) => {
                    let next_delimiter = self.find_next_delimiter(true);
                    self.text.drain(next_delimiter..self.cursor_position);
                    self.cursor_position = next_delimiter;
                }
                // Control + Delete
                (KeyModifiers::ALT, KeyCode::Char('d')) => {
                    let next_delimiter = self.find_next_delimiter(false);
                    self.text.drain(self.cursor_position..next_delimiter);
                }
                (KeyModifiers::NONE, KeyCode::Delete) => {
                    if self.cursor_position < self.text.len() {
                        self.text.remove(self.cursor_position);
                    }
                }
                (KeyModifiers::NONE, KeyCode::Backspace) => {
                    if self.text.len() > 0 {
                        self.text.remove(self.cursor_position - 1);
                        self.cursor_position -= 1;
                    }
                }
                (KeyModifiers::NONE, KeyCode::Left) => {
                    if self.cursor_position > 0 {
                        self.cursor_position -= 1;
                    }
                }
                (KeyModifiers::NONE, KeyCode::Right) => {
                    if self.cursor_position < self.text.len() {
                        self.cursor_position += 1;
                    }
                }
                // Alt + Left
                (KeyModifiers::ALT, KeyCode::Char('b')) => {
                    self.cursor_position = self.find_next_delimiter(true);
                }
                // Alt + Right
                (KeyModifiers::ALT, KeyCode::Char('f')) => {
                    self.cursor_position = self.find_next_delimiter(false);
                }
                (KeyModifiers::NONE, KeyCode::Home) => {
                    self.cursor_position = 0;
                }
                (KeyModifiers::NONE, KeyCode::End) => {
                    self.cursor_position = self.text.len();
                }
                (KeyModifiers::NONE, KeyCode::Enter) => {
                    return Some(self.text.clone());
                }
                _ => {}
            }
        }
        None
    }

    fn find_next_delimiter(&self, look_left: bool) -> usize {
        let text_len = self.text.len();
        if text_len == 0 {
            return 0;
        }

        if look_left {
            // Looking left
            if self.cursor_position == 0 {
                return 0;
            }
            let start = if is_delimiter(self.text.chars().nth(self.cursor_position - 1).unwrap()) {
                self.cursor_position - 2
            } else {
                self.cursor_position - 1
            };
            for i in (0..=start).rev() {
                if is_delimiter(self.text.chars().nth(i).unwrap()) {
                    return i + 1; // Return the position after the delimiter
                }
            }
            0 // If no delimiter found, return the start of the string
        } else {
            // Looking right
            if self.cursor_position >= text_len {
                return text_len;
            }
            let start = if is_delimiter(self.text.chars().nth(self.cursor_position).unwrap()) {
                self.cursor_position + 1
            } else {
                self.cursor_position
            };
            for i in start..text_len {
                if is_delimiter(self.text.chars().nth(i).unwrap()) {
                    return i;
                }
            }
            text_len // If no delimiter found, return the end of the string
        }
    }
}

fn is_delimiter(c: char) -> bool {
    " _-.,;:/\\()[]{}<>\"'\t\n".contains(c)
}
