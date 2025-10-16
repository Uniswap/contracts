use crate::libs::explorer::SupportedExplorerType;
use crate::screens::shared::block_explorer::BlockExplorerScreen;
use crate::screens::shared::enter_explorer_api_key::EnterExplorerApiKeyScreen;
use crate::screens::shared::select_verifier_type::SelectVerifierTypeScreen;
use crate::screens::shared::sourcify_api_url::SourcifyApiUrlScreen;
use crate::state_manager::STATE_MANAGER;
use crate::workflows::error_workflow::ErrorWorkflow;
use crate::workflows::workflow_manager::{process_nested_workflows, Workflow, WorkflowResult};

pub struct VerifierSelectionWorkflow {
    current_screen: usize,
    child_workflows: Vec<Box<dyn Workflow>>,
}

impl VerifierSelectionWorkflow {
    pub fn new() -> Self {
        VerifierSelectionWorkflow {
            current_screen: 0,
            child_workflows: vec![],
        }
    }
}

impl Workflow for VerifierSelectionWorkflow {
    fn next_screen(
        &mut self,
        new_workflows: Option<Vec<Box<dyn Workflow>>>,
    ) -> Result<WorkflowResult, Box<dyn std::error::Error>> {
        match process_nested_workflows(&mut self.child_workflows, new_workflows)? {
            WorkflowResult::NextScreen(screen) => Ok(WorkflowResult::NextScreen(screen)),
            WorkflowResult::Finished => {
                self.current_screen += 1;
                self.get_screen()
            }
        }
    }

    fn previous_screen(&mut self) -> Result<WorkflowResult, Box<dyn std::error::Error>> {
        if !self.child_workflows.is_empty() {
            return self.child_workflows[0].previous_screen();
        }
        if self.current_screen > 1 {
            self.current_screen -= 1;
        }
        self.get_screen()
    }

    fn handle_error(
        &mut self,
        error: Box<dyn std::error::Error>,
    ) -> Result<WorkflowResult, Box<dyn std::error::Error>> {
        self.display_error(error.to_string())
    }
}

impl VerifierSelectionWorkflow {
    fn get_screen(&mut self) -> Result<WorkflowResult, Box<dyn std::error::Error>> {
        match self.current_screen {
            1 => Ok(WorkflowResult::NextScreen(Box::new(
                BlockExplorerScreen::new()?,
            ))),
            2 => {
                // Check if explorer type is Unknown - if so, show verifier type selection
                let state = STATE_MANAGER.workflow_state.lock()?;
                let explorer = state.block_explorer.clone();
                drop(state);

                if let Some(explorer) = explorer {
                    if explorer.explorer_type == SupportedExplorerType::Unknown {
                        Ok(WorkflowResult::NextScreen(Box::new(
                            SelectVerifierTypeScreen::new()?,
                        )))
                    } else {
                        // Explorer type already known, skip to next screen
                        self.current_screen += 1;
                        self.get_screen()
                    }
                } else {
                    // No explorer selected, skip to end
                    Ok(WorkflowResult::Finished)
                }
            }
            3 => {
                // Check if Sourcify was selected - if so, always prompt for verifier API URL
                let state = STATE_MANAGER.workflow_state.lock()?;
                let explorer = state.block_explorer.clone();
                drop(state);

                if let Some(explorer) = explorer {
                    if explorer.explorer_type == SupportedExplorerType::Sourcify {
                        // Sourcify selected - always prompt for verifier API URL
                        Ok(WorkflowResult::NextScreen(Box::new(
                            SourcifyApiUrlScreen::new()?,
                        )))
                    } else {
                        // Not Sourcify - skip to API key screen
                        self.current_screen += 1;
                        self.get_screen()
                    }
                } else {
                    // No explorer selected, skip to end
                    Ok(WorkflowResult::Finished)
                }
            }
            4 => {
                // Enter API key for the selected verifier
                let state = STATE_MANAGER.workflow_state.lock()?;
                let explorer = state.block_explorer.clone();
                drop(state);

                if explorer.is_some() {
                    Ok(WorkflowResult::NextScreen(Box::new(
                        EnterExplorerApiKeyScreen::new()?,
                    )))
                } else {
                    // No explorer selected, skip to end
                    Ok(WorkflowResult::Finished)
                }
            }
            _ => Ok(WorkflowResult::Finished),
        }
    }

    fn display_error(
        &mut self,
        error_message: String,
    ) -> Result<WorkflowResult, Box<dyn std::error::Error>> {
        self.child_workflows = vec![Box::new(ErrorWorkflow::new(error_message))];
        self.current_screen = 1000000;
        self.child_workflows[0].next_screen(None)
    }
}
