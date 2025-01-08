use crate::screens::screen_manager::{Screen, ScreenResult};
use crate::screens::types::select::SelectComponent;
use crate::ui::Buffer;
use crossterm::event::Event;

pub struct GenericSelectScreen {
    select: SelectComponent,
    title: String,
    hook: Box<dyn Fn(usize) -> Result<ScreenResult, Box<dyn std::error::Error>> + Send>,
}

impl GenericSelectScreen {
    pub fn new(
        options: Vec<String>,
        title: String,
        hook: Box<dyn Fn(usize) -> Result<ScreenResult, Box<dyn std::error::Error>> + Send>,
    ) -> Self {
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
        if result.is_some() {
            return (self.hook)(result.unwrap());
        }
        Ok(ScreenResult::Continue)
    }

    fn execute(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        Ok(())
    }
}
