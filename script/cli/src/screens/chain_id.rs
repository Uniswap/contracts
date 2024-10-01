use crate::screen_manager::Screen;
use crate::screens::config::protocol_selection::ProtocolSelectionScreen;
use crate::screens::types::text_input::TextInputScreen;
use crate::state_manager::STATE_MANAGER;
use crate::ui::Buffer;
use crossterm::{event::Event, style::Color};

pub struct ChainIdScreen {
    text_input: TextInputScreen,
}

impl ChainIdScreen {
    pub fn new() -> Self {
        // let chain_ids = Self::fetch_chain_ids();
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
        self.text_input.render(buffer);
    }

    fn handle_input(&mut self, event: Event) -> Vec<Box<dyn Screen>> {
        let index = self.text_input.handle_input(event);
        if index != None {
            // STATE_MANAGER.set_chain_id(self.text_input.text.clone());
            return vec![Box::new(ProtocolSelectionScreen::new())];
        }
        vec![]
    }

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

    fn render_description(&self, _: &mut Buffer) {}

    fn render_warning(&self, _: &mut Buffer) {}

    fn render_error(&self, _: &mut Buffer) {}

    fn render_instructions(&self, buffer: &mut Buffer) {
        buffer.append_row_text_color("\nUse 'Enter' to select, 'Escape' to quit", Color::Blue);
    }
}
