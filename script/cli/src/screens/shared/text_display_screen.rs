use crate::screens::screen_manager::{Screen, ScreenResult};
use crate::screens::types::text_display::TextDisplayComponent;
use crate::ui::Buffer;
use crossterm::event::Event;

pub struct TextDisplayScreen {
    text_component: TextDisplayComponent,
}

impl TextDisplayScreen {
    pub fn new(text: String) -> Self {
        TextDisplayScreen {
            text_component: TextDisplayComponent::new(format!("{}\n", text)),
        }
    }
}

impl Screen for TextDisplayScreen {
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
