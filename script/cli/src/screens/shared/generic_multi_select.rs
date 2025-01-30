use crate::screens::screen_manager::{Screen, ScreenResult};
use crate::screens::types::multiple_choice::MultipleChoiceComponent;
use crate::ui::Buffer;
use crossterm::event::Event;

type Hook = Box<dyn Fn(Vec<usize>) -> Result<ScreenResult, Box<dyn std::error::Error>> + Send>;

pub struct GenericMultiSelectScreen {
    multiple_choice_screen: MultipleChoiceComponent,
    title: String,
    hook: Hook,
}

impl GenericMultiSelectScreen {
    pub fn new(options: Vec<String>, title: String, hook: Hook) -> Self {
        GenericMultiSelectScreen {
            multiple_choice_screen: MultipleChoiceComponent::new(options),
            title,
            hook,
        }
    }

    fn render_title(&self, buffer: &mut Buffer) {
        buffer.append_row_text(&format!("{}\n", self.title));
    }

    fn render_instructions(&self, buffer: &mut Buffer) {
        self.multiple_choice_screen
            .render_default_instructions(buffer);
    }
}

impl Screen for GenericMultiSelectScreen {
    fn render_content(&self, buffer: &mut Buffer) -> Result<(), Box<dyn std::error::Error>> {
        self.render_title(buffer);
        self.multiple_choice_screen.render(buffer);
        self.render_instructions(buffer);
        Ok(())
    }

    fn handle_input(&mut self, event: Event) -> Result<ScreenResult, Box<dyn std::error::Error>> {
        let result = self.multiple_choice_screen.handle_input(event);
        if let Some(result) = result {
            if !result.is_empty() {
                return (self.hook)(result);
            }
        }
        Ok(ScreenResult::Continue)
    }

    fn execute(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        Ok(())
    }
}
