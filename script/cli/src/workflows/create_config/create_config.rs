use crate::errors;
use crate::screens::create_config::protocol_selection::ProtocolSelectionScreen;
use crate::screens::shared::chain_id::ChainIdScreen;
use crate::screens::shared::rpc_url::RpcUrlScreen;
use crate::screens::shared::test_connection::TestConnectionScreen;
use crate::state_manager::STATE_MANAGER;
use crate::workflows::error_workflow::ErrorWorkflow;
use crate::workflows::workflow_manager::{process_nested_workflows, Workflow, WorkflowResult};

pub struct CreateConfigWorkflow {
    current_screen: usize,
    child_workflows: Vec<Box<dyn Workflow>>,
}

impl CreateConfigWorkflow {
    pub fn new() -> Self {
        CreateConfigWorkflow {
            current_screen: 0,
            child_workflows: vec![],
        }
    }
}

impl Workflow for CreateConfigWorkflow {
    fn next_screen(&mut self, new_workflows: Option<Vec<Box<dyn Workflow>>>) -> WorkflowResult {
        match process_nested_workflows(&mut self.child_workflows, new_workflows) {
            WorkflowResult::NextScreen(screen) => return WorkflowResult::NextScreen(screen),
            WorkflowResult::Finished => {
                self.current_screen += 1;
                self.get_screen()
            }
        }
    }

    fn previous_screen(&mut self) -> WorkflowResult {
        if self.current_screen > 1 {
            self.current_screen -= 1;
        }
        if self.current_screen == 3 {
            self.current_screen = 2;
        }
        return self.get_screen();
    }

    fn handle_error(&mut self, error: Box<dyn std::error::Error>) -> WorkflowResult {
        errors::log(self.current_screen.to_string());
        match self.current_screen {
            3 => {
                if error.downcast_ref::<errors::ConnectionError>().is_some() {
                    STATE_MANAGER.app_state.lock().unwrap().set_rpc_url(None);
                    self.current_screen = 2;
                    return self.get_screen();
                }
                return self.display_error(error.to_string());
            }
            _ => return self.display_error(error.to_string()),
        }
    }
}

impl CreateConfigWorkflow {
    fn get_screen(&self) -> WorkflowResult {
        match self.current_screen {
            1 => return WorkflowResult::NextScreen(Box::new(ChainIdScreen::new())),
            2 => return WorkflowResult::NextScreen(Box::new(RpcUrlScreen::new())),
            3 => return WorkflowResult::NextScreen(Box::new(TestConnectionScreen::new())),
            4 => return WorkflowResult::NextScreen(Box::new(ProtocolSelectionScreen::new())),
            _ => return WorkflowResult::Finished,
        }
    }

    fn display_error(&mut self, error_message: String) -> WorkflowResult {
        self.child_workflows = vec![Box::new(ErrorWorkflow::new(error_message))];
        self.current_screen = 1000000;
        return self.child_workflows[0].next_screen(None);
    }
}
