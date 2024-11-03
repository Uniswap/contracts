use crate::screens::screen_manager::{Screen, ScreenResult};
use crate::screens::types::select_or_enter::SelectOrEnterComponent;
use crate::ui::Buffer;
use crossterm::event::Event;

pub struct GenericSelectOrEnterScreen {
    select_or_enter: SelectOrEnterComponent,
    hook: Box<dyn Fn(String) -> Result<ScreenResult, Box<dyn std::error::Error>> + Send>,
}

impl GenericSelectOrEnterScreen {
    pub fn new(
        title: String,
        options: Vec<String>,
        text_input_validator: fn(String, usize) -> String,
        env_var_input_validator: fn(String, usize) -> String,
        hook: Box<dyn Fn(String) -> Result<ScreenResult, Box<dyn std::error::Error>> + Send>,
    ) -> Self {
        GenericSelectOrEnterScreen {
            select_or_enter: SelectOrEnterComponent::new(
                title,
                options,
                text_input_validator,
                env_var_input_validator,
            ),
            hook,
        }
    }
}

impl Screen for GenericSelectOrEnterScreen {
    fn handle_input(
        &mut self,
        event: Event,
    ) -> Result<crate::screens::screen_manager::ScreenResult, Box<dyn std::error::Error>> {
        let result = self.select_or_enter.handle_input(event);
        if result.is_some() {
            return (self.hook)(result.unwrap());
        }
        Ok(ScreenResult::Continue)
    }

    fn render_content(&self, buffer: &mut Buffer) -> Result<(), Box<dyn std::error::Error>> {
        Ok(self.select_or_enter.render(buffer))
    }

    fn execute(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        Ok(())
    }
}
