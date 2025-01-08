use crate::screens::screen_manager::{Screen, ScreenResult};
use crate::screens::types::text_display::TextDisplayComponent;
use crate::ui::Buffer;
use crossterm::event::Event;

pub struct ErrorScreen {
    text_component: TextDisplayComponent,
}

impl ErrorScreen {
    pub fn new(error_message: String) -> Self {
        ErrorScreen {
            text_component: TextDisplayComponent::new(format!("Error: {}\n", error_message)),
        }
    }
}

impl Screen for ErrorScreen {
    fn render_content(&self, buffer: &mut Buffer) -> Result<(), Box<dyn std::error::Error>> {
        self.text_component.render(buffer);
        Ok(())
    }

    fn handle_input(&mut self, event: Event) -> Result<ScreenResult, Box<dyn std::error::Error>> {
        let result = self.text_component.handle_input(event);
        if result {
            return Ok(ScreenResult::NextScreen(None));
        }
        Ok(ScreenResult::Continue)
    }

    fn execute(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        Ok(())
    }
}
