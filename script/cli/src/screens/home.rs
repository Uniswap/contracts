use crate::screen_manager::Screen;
use crate::screens::chain_id::ChainIdScreen;
use crate::screens::types::select::SelectScreen;
use crate::ui::Buffer;
use crossterm::{event::Event, style::Color};

pub struct HomeScreen {
    select_screen: SelectScreen,
}

impl HomeScreen {
    pub fn new() -> Self {
        let options = vec![
            "Create Config".to_string(),
            "Verify Deployment".to_string(),
            "Deploy Protocol".to_string(),
            "Register Existing Contract".to_string(),
        ];
        HomeScreen {
            select_screen: SelectScreen::new(options),
        }
    }
}

impl Screen for HomeScreen {
    fn render_content(&self, buffer: &mut Buffer) {
        self.select_screen.render(buffer);
    }

    fn handle_input(&mut self, event: Event) -> Vec<Box<dyn Screen>> {
        let index = self.select_screen.handle_input(event);
        if index == 0 {
            return vec![Box::new(ChainIdScreen::new())];
        }
        vec![]
    }

    fn render_title(&self, buffer: &mut Buffer) {
        buffer.append_row_text("Welcome to the Uniswap Deploy CLI! What do you want to do?\n");
    }

    fn render_description(&self, _: &mut Buffer) {}

    fn render_warning(&self, _: &mut Buffer) {}

    fn render_error(&self, _: &mut Buffer) {}

    fn render_instructions(&self, buffer: &mut Buffer) {
        buffer.append_row_text_color(
            "\nUse ↑↓ arrows to navigate, 'Enter' to select, 'Escape' to quit",
            Color::Blue,
        );
    }
}
