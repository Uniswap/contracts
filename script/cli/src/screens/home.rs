use crate::constants;
use crate::screens::screen_manager::{Screen, ScreenResult};
use crate::screens::types::select::SelectComponent;
use crate::state_manager::STATE_MANAGER;
use crate::ui::Buffer;
use crate::workflows::{
    create_config::create_config::CreateConfigWorkflow,
    register_contract::register_contract::RegisterContractWorkflow,
};
use crossterm::event::Event;

// The home screen is the first screen that is shown to the user. It provides a menu to select a workflow to execute. After a workflow completes, the user is returned to the home screen.
pub struct HomeScreen {
    select_screen: SelectComponent,
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
            select_screen: SelectComponent::new(options),
        }
    }

    pub fn render_title(&self, buffer: &mut Buffer) {
        buffer.append_row_text("Welcome to the Uniswap Deploy CLI! What do you want to do?\n");
    }

    pub fn render_instructions(&self, buffer: &mut Buffer) {
        self.select_screen.render_default_instructions(buffer);
        buffer.append_row_text_color(
            "Press 'Esc' to return to the home screen, 'Ctrl+Z' to go back to the previous screen",
            constants::INSTRUCTIONS_COLOR,
        );
    }
}

impl Screen for HomeScreen {
    fn render_content(&self, buffer: &mut Buffer) {
        self.render_title(buffer);
        self.select_screen.render(buffer);
        self.render_instructions(buffer);
    }

    fn handle_input(&mut self, event: Event) -> Result<ScreenResult, Box<dyn std::error::Error>> {
        let index = self.select_screen.handle_input(event);
        if index.is_some() {
            return match index.unwrap() {
                0 => Ok(ScreenResult::NextScreen(Some(vec![Box::new(
                    CreateConfigWorkflow::new(),
                )]))),
                3 => Ok(ScreenResult::NextScreen(Some(vec![Box::new(
                    RegisterContractWorkflow::new(),
                )]))),
                _ => Ok(ScreenResult::Continue),
            };
        }
        Ok(ScreenResult::Continue)
    }

    fn execute(&mut self) {
        // nothing to execute
    }
}
