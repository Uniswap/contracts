use crate::screens::screen_manager::Screen;

// Workflows are sequences of screens that are executed in order. When a workflow completes, it returns to the home screen and the state is reset. A screen can spawn new sub-workflows that are integrated into the current workflow until they complete. For example the protocol selection screen can spawn new workflows depending on the selected protocols to enter information required to deploy the selected protocols.

pub enum WorkflowResult {
    NextScreen(Box<dyn Screen>),
    Finished,
}

pub trait Workflow: Send {
    // this function prompts the workflow to return the next screen to be displayed. It also accepts a list of new child workflows to be executed in parallel to the current workflow.
    fn next_screen(&mut self, new_workflows: Option<Vec<Box<dyn Workflow>>>) -> WorkflowResult {
        let mut added_workflows = vec![];
        process_nested_workflows(&mut added_workflows, new_workflows)
    }
    // this function prompts the workflow to return the previous screen to be displayed.
    fn previous_screen(&mut self) -> WorkflowResult;
    // this function is called when an error occurs in a nested workflow. It should return the next screen to be displayed.
    fn handle_error(&mut self, error: Box<dyn std::error::Error>) -> WorkflowResult;
}

// This function is used to manage nested workflows. It should be called at the start of the next_screen function of a workflow. It will handle the logic of passing the screen selection to the child workflows and managing new workflows that are spawned.
pub fn process_nested_workflows(
    child_workflows: &mut Vec<Box<dyn Workflow>>,
    new_workflows: Option<Vec<Box<dyn Workflow>>>,
) -> WorkflowResult {
    let mut passed_workflows = None;
    if new_workflows.is_some() {
        // there are new workflows returned from the screen
        if child_workflows.is_empty() {
            // there are no child workflows, so we add the new workflows as children if there are any
            // new_workflows is consumed here, so no additional workflows are passed to the child workflows
            child_workflows.extend(new_workflows.unwrap());
        } else {
            // there are child workflows, pass them to the first child
            passed_workflows = new_workflows;
        }
    }

    if !child_workflows.is_empty() {
        // there are child workflows present or new workflows have just been added by this function attempt to get the next screen from the first child and pass any additional workflows to it
        match child_workflows[0].next_screen(passed_workflows) {
            WorkflowResult::NextScreen(screen) => return WorkflowResult::NextScreen(screen),
            WorkflowResult::Finished => {
                // the first child workflow has finished, remove it and continue with the next one until there is a child workflow that is not finished and returns a new screen
                child_workflows.remove(0);
                while !child_workflows.is_empty() {
                    match child_workflows[0].next_screen(None) {
                        WorkflowResult::NextScreen(screen) => {
                            return WorkflowResult::NextScreen(screen)
                        }
                        WorkflowResult::Finished => {
                            child_workflows.remove(0);
                        }
                    }
                }
            }
        }
    }
    // all child workflows are finished
    WorkflowResult::Finished
}
