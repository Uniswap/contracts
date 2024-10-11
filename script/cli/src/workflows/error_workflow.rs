use crate::screens::shared::error_screen::ErrorScreen;
use crate::workflows::workflow_manager::{Workflow, WorkflowResult};

pub struct ErrorWorkflow {
    error_displayed: bool,
    error_message: String,
}

impl ErrorWorkflow {
    pub fn new(error_message: String) -> Self {
        ErrorWorkflow {
            error_displayed: false,
            error_message,
        }
    }
}

impl Workflow for ErrorWorkflow {
    fn next_screen(&mut self, _: Option<Vec<Box<dyn Workflow>>>) -> WorkflowResult {
        if !self.error_displayed {
            self.error_displayed = true;
            return WorkflowResult::NextScreen(Box::new(ErrorScreen::new(
                self.error_message.clone(),
            )));
        }
        return WorkflowResult::Finished;
    }

    fn previous_screen(&mut self) -> WorkflowResult {
        return WorkflowResult::Finished;
    }

    fn handle_error(&mut self, _: Box<dyn std::error::Error>) -> WorkflowResult {
        return WorkflowResult::Finished;
    }
}
