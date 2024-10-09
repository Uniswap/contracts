use crate::screens::home::HomeScreen;
use crate::workflows::workflow_manager::{process_nested_workflows, Workflow, WorkflowResult};

pub struct DefaultWorkflow {
    child_workflows: Vec<Box<dyn Workflow>>,
}

impl DefaultWorkflow {
    pub fn new() -> Self {
        DefaultWorkflow {
            child_workflows: vec![],
        }
    }
}

impl Workflow for DefaultWorkflow {
    fn next_screen(&mut self, new_workflows: Option<Vec<Box<dyn Workflow>>>) -> WorkflowResult {
        match process_nested_workflows(&mut self.child_workflows, new_workflows) {
            WorkflowResult::NextScreen(screen) => return WorkflowResult::NextScreen(screen),
            WorkflowResult::Finished => {
                return WorkflowResult::NextScreen(Box::new(HomeScreen::new()));
            }
        }
    }

    fn previous_screen(&mut self) -> WorkflowResult {
        if !self.child_workflows.is_empty() {
            return self.child_workflows[0].previous_screen();
        }
        return WorkflowResult::NextScreen(Box::new(HomeScreen::new()));
    }

    fn handle_error(&mut self, error: Box<dyn std::error::Error>) -> WorkflowResult {
        if !self.child_workflows.is_empty() {
            return self.child_workflows[0].handle_error(error);
        }
        return WorkflowResult::NextScreen(Box::new(HomeScreen::new()));
    }
}
