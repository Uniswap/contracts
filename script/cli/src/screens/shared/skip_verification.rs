use crate::screens::screen_manager::{Screen, ScreenResult};
use crate::screens::types::select::SelectComponent;
use crate::state_manager::STATE_MANAGER;
use crate::ui::Buffer;
use crossterm::event::Event;

pub struct SkipVerificationScreen {
    select: SelectComponent,
}

impl SkipVerificationScreen {
    pub fn new() -> Result<Self, Box<dyn std::error::Error>> {
        let options = vec![
            "Yes, verify contracts".to_string(),
            "No, skip verification".to_string(),
        ];

        Ok(SkipVerificationScreen {
            select: SelectComponent::new(options),
        })
    }
}

impl Screen for SkipVerificationScreen {
    fn render_content(&self, buffer: &mut Buffer) -> Result<(), Box<dyn std::error::Error>> {
        buffer.append_row_text("Do you want to verify contracts after deployment?\n\n");

        self.select.render(buffer);

        self.select.render_default_instructions(buffer);

        Ok(())
    }

    fn handle_input(&mut self, event: Event) -> Result<ScreenResult, Box<dyn std::error::Error>> {
        if let Some(index) = self.select.handle_input(event) {
            match index {
                0 => {
                    // Yes, verify contracts
                    STATE_MANAGER.workflow_state.lock()?.skip_verification = false;
                    Ok(ScreenResult::NextScreen(None))
                }
                1 => {
                    // No, skip verification
                    STATE_MANAGER.workflow_state.lock()?.skip_verification = true;
                    Ok(ScreenResult::NextScreen(None))
                }
                _ => Ok(ScreenResult::Continue),
            }
        } else {
            Ok(ScreenResult::Continue)
        }
    }

    fn execute(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        Ok(())
    }
}
