use crate::constants;
use crate::ui::Buffer;
use crossterm::{
    event::{Event, KeyCode, KeyModifiers},
    style::{Attribute, SetAttribute},
};

pub struct TextInputComponent {
    pub text: String,
    default_text: String,
    hidden: bool,
    cursor_position: usize,
    validate_input: fn(String, usize) -> String,
}

impl TextInputComponent {
    pub fn new(
        hidden: bool,
        default_text: String,
        validate_input: fn(String, usize) -> String,
    ) -> Self {
        TextInputComponent {
            text: String::new(),
            default_text,
            hidden,
            cursor_position: 0,
            validate_input,
        }
    }

    pub fn render_default_instructions(&self, buffer: &mut Buffer) {
        buffer.append_row_text_color("\nUse 'Enter' to select", constants::INSTRUCTIONS_COLOR);
    }

    pub fn render(&self, buffer: &mut Buffer) {
        let cursor_position = self.cursor_position;
        let mut text = if self.hidden {
            "*".repeat(self.text.len()) + " "
        } else {
            self.text.clone() + " "
        };
        if self.text.is_empty() && !self.default_text.is_empty() {
            text = self.default_text.clone();
            buffer.append_row_text_color(&text, constants::GREY_COLOR);
            return;
        }
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
        buffer.append_row_text_color(&text, constants::DEFAULT_COLOR);
    }

    pub fn handle_input(&mut self, event: Event) -> Option<String> {
        if let Event::Key(key_event) = event {
            match (key_event.modifiers, key_event.code) {
                (KeyModifiers::NONE, KeyCode::Char(c))
                | (KeyModifiers::SHIFT, KeyCode::Char(c)) => {
                    let mut new_text = self.text.clone();
                    new_text.insert(self.cursor_position, c);
                    new_text = (self.validate_input)(new_text, self.cursor_position + 1);
                    if new_text.len() > self.text.len() {
                        self.cursor_position += 1;
                    }
                    if self.cursor_position > new_text.len() {
                        self.cursor_position = new_text.len();
                    }
                    self.text = new_text;
                }
                // Command + Backspace
                (KeyModifiers::SUPER, KeyCode::Backspace)
                | (KeyModifiers::CONTROL, KeyCode::Char('u')) => {
                    self.text = String::new();
                    self.cursor_position = 0;
                }
                // Control + Backspace / Alt + Backspace
                (KeyModifiers::CONTROL, KeyCode::Backspace)
                | (KeyModifiers::ALT, KeyCode::Backspace)
                | (KeyModifiers::CONTROL, KeyCode::Char('h'))
                | (KeyModifiers::CONTROL, KeyCode::Char('w')) => {
                    let next_delimiter = self.find_next_delimiter(true);
                    let mut new_text = self.text.clone();
                    new_text.drain(next_delimiter..self.cursor_position);
                    self.cursor_position = next_delimiter;
                    new_text = (self.validate_input)(new_text, self.cursor_position);
                    if self.cursor_position > self.text.len() {
                        self.cursor_position = self.text.len();
                    }
                    self.text = new_text;
                }
                // Control + Delete
                (KeyModifiers::ALT, KeyCode::Delete) | (KeyModifiers::ALT, KeyCode::Char('d')) => {
                    let mut new_text = self.text.clone();
                    let next_delimiter = self.find_next_delimiter(false);
                    new_text.drain(self.cursor_position..next_delimiter);
                    new_text = (self.validate_input)(new_text, self.cursor_position);
                    if self.cursor_position > new_text.len() {
                        self.cursor_position = new_text.len();
                    }
                    self.text = new_text;
                }
                (KeyModifiers::NONE, KeyCode::Delete) => {
                    let mut new_text = self.text.clone();
                    if self.cursor_position < self.text.len() {
                        new_text.remove(self.cursor_position);
                        new_text = (self.validate_input)(new_text, self.cursor_position);
                    }
                    if self.cursor_position > new_text.len() {
                        self.cursor_position = new_text.len();
                    }
                    self.text = new_text;
                }
                (KeyModifiers::NONE, KeyCode::Backspace) => {
                    if self.text.len() > 0 && self.cursor_position > 0 {
                        let mut new_text = self.text.clone();
                        new_text.remove(self.cursor_position - 1);
                        if self.cursor_position > 0 {
                            self.cursor_position -= 1;
                        }
                        new_text = (self.validate_input)(new_text, self.cursor_position);
                        if self.cursor_position > new_text.len() {
                            self.cursor_position = new_text.len();
                        }
                        self.text = new_text;
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
                (KeyModifiers::ALT, KeyCode::Left) | (KeyModifiers::ALT, KeyCode::Char('b')) => {
                    self.cursor_position = self.find_next_delimiter(true);
                }
                // Alt + Right
                (KeyModifiers::ALT, KeyCode::Right) | (KeyModifiers::ALT, KeyCode::Char('f')) => {
                    self.cursor_position = self.find_next_delimiter(false);
                }
                (KeyModifiers::NONE, KeyCode::Home) => {
                    self.cursor_position = 0;
                }
                (KeyModifiers::NONE, KeyCode::End) => {
                    self.cursor_position = self.text.len();
                }
                (KeyModifiers::NONE, KeyCode::Enter) => {
                    if self.text.is_empty() && !self.default_text.is_empty() {
                        return Some(self.default_text.clone());
                    }
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
