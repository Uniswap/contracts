use crate::screen_manager::Screen;
use crate::screen_manager::Workflow;
use crate::screens::types::select::SelectScreen;
use crate::state_manager::STATE_MANAGER;
use crate::ui::Buffer;
use crate::workflows::create_config::create_config::CreateConfigWorkflow;
use crossterm::{event::Event, style::Color};

// The home screen is the first screen that is shown to the user. It provides a menu to select a workflow to execute. After a workflow completes, the user is returned to the home screen.
pub struct HomeScreen {
    select_screen: SelectScreen,
}

impl HomeScreen {
    pub fn new() -> Self {
        // reset the app state when returning to the home screen to ensure a clean state
        STATE_MANAGER.app_state.lock().unwrap().reset();
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
        render_title(buffer);
        self.select_screen.render(buffer);
        render_instructions(buffer);
    }

    fn handle_input(&mut self, event: Event) -> Option<Vec<Box<dyn Workflow>>> {
        let index = self.select_screen.handle_input(event);
        match index {
            0 => Some(vec![Box::new(CreateConfigWorkflow::new())]),
            _ => None,
        }
    }
}

fn render_title(buffer: &mut Buffer) {
    buffer.append_row_text("Welcome to the Uniswap Deploy CLI! What do you want to do?\n");
}

fn render_instructions(buffer: &mut Buffer) {
    buffer.append_row_text_color(
        "\nUse ↑↓ arrows to navigate, 'Enter' to select, 'Escape' to quit",
        Color::Blue,
    );
}
