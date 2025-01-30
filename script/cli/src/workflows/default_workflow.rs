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
    fn next_screen(
        &mut self,
        new_workflows: Option<Vec<Box<dyn Workflow>>>,
    ) -> Result<WorkflowResult, Box<dyn std::error::Error>> {
        match process_nested_workflows(&mut self.child_workflows, new_workflows)? {
            WorkflowResult::NextScreen(screen) => Ok(WorkflowResult::NextScreen(screen)),
            WorkflowResult::Finished => Ok(WorkflowResult::NextScreen(Box::new(HomeScreen::new()))),
        }
    }

    fn previous_screen(&mut self) -> Result<WorkflowResult, Box<dyn std::error::Error>> {
        if !self.child_workflows.is_empty() {
            return self.child_workflows[0].previous_screen();
        }
        Ok(WorkflowResult::NextScreen(Box::new(HomeScreen::new())))
    }

    fn handle_error(
        &mut self,
        error: Box<dyn std::error::Error>,
    ) -> Result<WorkflowResult, Box<dyn std::error::Error>> {
        if !self.child_workflows.is_empty() {
            return self.child_workflows[0].handle_error(error);
        }
        Ok(WorkflowResult::NextScreen(Box::new(HomeScreen::new())))
    }
}
