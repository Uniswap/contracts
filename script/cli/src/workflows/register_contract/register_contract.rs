use crate::errors;
use crate::screens::register_contract::enter_address::EnterAddressScreen;
use crate::screens::register_contract::get_contract_info::GetContractInfoScreen;
use crate::screens::shared::block_explorer::BlockExplorerScreen;
use crate::screens::shared::chain_id::ChainIdScreen;
use crate::screens::shared::enter_explorer_api_key::EnterExplorerApiKeyScreen;
use crate::screens::shared::rpc_url::get_rpc_url_screen;
use crate::screens::shared::test_connection::TestConnectionScreen;
use crate::state_manager::STATE_MANAGER;
use crate::workflows::error_workflow::ErrorWorkflow;
use crate::workflows::workflow_manager::{process_nested_workflows, Workflow, WorkflowResult};

pub struct RegisterContractWorkflow {
    current_screen: usize,
    child_workflows: Vec<Box<dyn Workflow>>,
}

impl RegisterContractWorkflow {
    pub fn new() -> Self {
        RegisterContractWorkflow {
            current_screen: 0,
            child_workflows: vec![],
        }
    }
}

impl Workflow for RegisterContractWorkflow {
    fn next_screen(
        &mut self,
        new_workflows: Option<Vec<Box<dyn Workflow>>>,
    ) -> Result<WorkflowResult, Box<dyn std::error::Error>> {
        match process_nested_workflows(&mut self.child_workflows, new_workflows)? {
            WorkflowResult::NextScreen(screen) => return Ok(WorkflowResult::NextScreen(screen)),
            WorkflowResult::Finished => {
                self.current_screen += 1;
                self.get_screen()
            }
        }
    }

    fn previous_screen(&mut self) -> Result<WorkflowResult, Box<dyn std::error::Error>> {
        if self.child_workflows.len() > 0 {
            return self.child_workflows[0].previous_screen();
        }
        if self.current_screen > 1 {
            self.current_screen -= 1;
        }
        // if current screen is the test connection screen, go back to the rpc url screen
        if self.current_screen == 3 {
            self.current_screen = 2;
        }
        return self.get_screen();
    }

    fn handle_error(
        &mut self,
        error: Box<dyn std::error::Error>,
    ) -> Result<WorkflowResult, Box<dyn std::error::Error>> {
        match self.current_screen {
            3 => {
                if error.downcast_ref::<errors::ConnectionError>().is_some() {
                    STATE_MANAGER.workflow_state.lock()?.web3 = None;
                    self.current_screen = 2;
                    return self.get_screen();
                }
                return self.display_error(error.to_string());
            }
            _ => return self.display_error(error.to_string()),
        }
    }
}

impl RegisterContractWorkflow {
    fn get_screen(&self) -> Result<WorkflowResult, Box<dyn std::error::Error>> {
        match self.current_screen {
            1 => {
                return Ok(WorkflowResult::NextScreen(Box::new(ChainIdScreen::new(
                    None,
                ))))
            }
            2 => return get_rpc_url_screen(),
            3 => {
                return Ok(WorkflowResult::NextScreen(Box::new(
                    TestConnectionScreen::new()?,
                )))
            }
            4 => {
                let screen = BlockExplorerScreen::new()?;
                return Ok(WorkflowResult::NextScreen(Box::new(screen)));
            }
            5 => {
                return Ok(WorkflowResult::NextScreen(Box::new(
                    EnterExplorerApiKeyScreen::new()?,
                )))
            }
            6 => {
                return Ok(WorkflowResult::NextScreen(Box::new(
                    EnterAddressScreen::new(),
                )))
            }
            7 => {
                return Ok(WorkflowResult::NextScreen(Box::new(
                    GetContractInfoScreen::new()?,
                )))
            }
            _ => return Ok(WorkflowResult::Finished),
        }
    }

    fn display_error(
        &mut self,
        error_message: String,
    ) -> Result<WorkflowResult, Box<dyn std::error::Error>> {
        self.child_workflows = vec![Box::new(ErrorWorkflow::new(error_message))];
        self.current_screen = 1000000;
        return self.child_workflows[0].next_screen(None);
    }
}
