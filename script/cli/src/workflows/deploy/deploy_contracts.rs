use crate::errors;
use crate::screens::deploy_contracts::execute_deploy_script::ExecuteDeployScriptScreen;
use crate::screens::screen_manager::ScreenResult;
use crate::screens::shared::block_explorer::BlockExplorerScreen;
use crate::screens::shared::chain_id::ChainIdScreen;
use crate::screens::shared::enter_explorer_api_key::EnterExplorerApiKeyScreen;
use crate::screens::shared::generic_select_or_enter::GenericSelectOrEnterScreen;
use crate::screens::shared::rpc_url::get_rpc_url_screen;
use crate::screens::shared::test_connection::TestConnectionScreen;
use crate::screens::shared::text_display_screen::TextDisplayScreen;
use crate::state_manager::STATE_MANAGER;
use crate::util::deploy_config_lib::get_config_dir;
use crate::util::screen_util::validate_bytes32;
use crate::workflows::error_workflow::ErrorWorkflow;
use crate::workflows::workflow_manager::{process_nested_workflows, Workflow, WorkflowResult};

pub struct DeployContractsWorkflow {
    current_screen: usize,
    child_workflows: Vec<Box<dyn Workflow>>,
}

impl DeployContractsWorkflow {
    pub fn new() -> Self {
        DeployContractsWorkflow {
            current_screen: 0,
            child_workflows: vec![],
        }
    }
}

impl Workflow for DeployContractsWorkflow {
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
        // if current screen is the test connection screen, go back to the rpc url screen
        if self.current_screen == 3 {
            self.current_screen = 2;
        }
        self.get_screen()
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
                self.display_error(error.to_string())
            }
            _ => self.display_error(error.to_string()),
        }
    }
}

impl DeployContractsWorkflow {
    fn get_screen(&mut self) -> Result<WorkflowResult, Box<dyn std::error::Error>> {
        match self.current_screen {
            1 => Ok(WorkflowResult::NextScreen(Box::new(ChainIdScreen::new(
                Some(Box::new(|chain_id| {
                    let config_path = get_config_dir(chain_id.clone()).join("task-pending.json");
                    if !config_path.exists() {
                        return Err(format!("No config found for chain id {}", chain_id).into());
                    }
                    Ok(ScreenResult::NextScreen(None))
                })),
            )))),
            2 => get_rpc_url_screen(),
            3 => Ok(WorkflowResult::NextScreen(Box::new(
                TestConnectionScreen::new()?,
            ))),
            4 => match BlockExplorerScreen::new() {
                Ok(screen) => Ok(WorkflowResult::NextScreen(Box::new(screen))),
                Err(_) => {
                    self.current_screen += 1;
                    Ok(WorkflowResult::NextScreen(Box::new(
                        TextDisplayScreen::new(
                            "No explorer found, skipping contract verification during deployment."
                                .to_string(),
                        ),
                    )))
                }
            },
            5 => Ok(WorkflowResult::NextScreen(Box::new(
                EnterExplorerApiKeyScreen::new()?,
            ))),
            6 => Ok(WorkflowResult::NextScreen(Box::new(
                GenericSelectOrEnterScreen::new(
                    "Enter your private key".to_string(),
                    vec!["${PRIVATE_KEY}".to_string()],
                    validate_bytes32,
                    validate_bytes32,
                    true,
                    Box::new(move |result| {
                        STATE_MANAGER.workflow_state.lock()?.private_key = Some(result);
                        Ok(ScreenResult::NextScreen(None))
                    }),
                ),
            ))),
            7 => Ok(WorkflowResult::NextScreen(Box::new(
                ExecuteDeployScriptScreen::new()?,
            ))),
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
