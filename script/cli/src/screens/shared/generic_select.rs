use crate::screens::screen_manager::{Screen, ScreenResult};
use crate::screens::types::select::SelectComponent;
use crate::ui::Buffer;
use crossterm::event::Event;

type Hook = Box<dyn Fn(usize) -> Result<ScreenResult, Box<dyn std::error::Error>> + Send>;

pub struct GenericSelectScreen {
    select: SelectComponent,
    title: String,
    hook: Hook,
}

impl GenericSelectScreen {
    pub fn new(options: Vec<String>, title: String, hook: Hook) -> Self {
        GenericSelectScreen {
            select: SelectComponent::new(options),
            title,
            hook,
        }
    }

    fn render_title(&self, buffer: &mut Buffer) {
        buffer.append_row_text(&format!("{}\n", self.title));
    }

    fn render_instructions(&self, buffer: &mut Buffer) {
        self.select.render_default_instructions(buffer);
    }
}

impl Screen for GenericSelectScreen {
    fn render_content(&self, buffer: &mut Buffer) -> Result<(), Box<dyn std::error::Error>> {
        self.render_title(buffer);
        self.select.render(buffer);
        self.render_instructions(buffer);
        Ok(())
    }

    fn handle_input(&mut self, event: Event) -> Result<ScreenResult, Box<dyn std::error::Error>> {
        let result = self.select.handle_input(event);
        if let Some(result) = result {
            return (self.hook)(result);
        }
        Ok(ScreenResult::Continue)
    }

    fn execute(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        Ok(())
    }
}
