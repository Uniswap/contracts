use crate::screen_manager::{Screen, Workflow};
use crate::screens::types::text_input::TextInputScreen;
use crate::state_manager::STATE_MANAGER;
use crate::ui::Buffer;
use crossterm::{event::Event, style::Color};

pub struct ChainIdScreen {
    text_input: TextInputScreen,
}

impl ChainIdScreen {
    pub fn new() -> Self {
        ChainIdScreen {
            text_input: TextInputScreen::new(false, ChainIdScreen::validate_input),
        }
    }

    pub fn validate_input(input: String) -> String {
        let cleaned = input.chars().filter(|c| c.is_digit(10)).collect::<String>();
        if cleaned.is_empty() {
            return "".to_string();
        }
        cleaned
    }
}

impl Screen for ChainIdScreen {
    fn render_content(&self, buffer: &mut Buffer) {
        self.render_title(buffer);
        self.text_input.render(buffer);
        render_instructions(buffer);
    }

    fn handle_input(&mut self, event: Event) -> Option<Vec<Box<dyn Workflow>>> {
        let chain_id = self.text_input.handle_input(event);
        if chain_id != None && !chain_id.unwrap().is_empty() {
            return Some(vec![]);
        }
        None
    }
}

impl ChainIdScreen {
    fn render_title(&self, buffer: &mut Buffer) {
        let chain_id = self.text_input.text.clone();
        if chain_id.is_empty() {
            buffer.append_row_text("Please enter the chain id of the network\n");
            return;
        }
        let chain_name = STATE_MANAGER.get_chain(chain_id);
        if chain_name.is_none() {
            buffer.append_row_text("Unknown network\n");
            return;
        }
        buffer.append_row_text(&format!("Selected network: {}\n", chain_name.unwrap().name));
    }
}

fn render_instructions(buffer: &mut Buffer) {
    buffer.append_row_text_color("\nUse 'Enter' to select, 'Escape' to quit", Color::Blue);
}
