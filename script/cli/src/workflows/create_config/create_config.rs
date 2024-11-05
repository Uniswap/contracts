use super::subflows::protocol_config::ProtocolConfigWorkflow;
use crate::errors;
use crate::screens::screen_manager::ScreenResult;
use crate::screens::shared::chain_id::ChainIdScreen;
use crate::screens::shared::generic_multi_select::GenericMultiSelectScreen;
use crate::screens::shared::rpc_url::get_rpc_url_screen;
use crate::screens::shared::test_connection::TestConnectionScreen;
use crate::screens::shared::text_display_screen::TextDisplayScreen;
use crate::state_manager::STATE_MANAGER;
use crate::util::deploy_config_lib::{get_config_dir, load_template_config};
use crate::workflows::error_workflow::ErrorWorkflow;
use crate::workflows::workflow_manager::{process_nested_workflows, Workflow, WorkflowResult};
use std::error::Error;

// array to handle protocol display automatically
// first element is the name of the protocol that is displayed
// second element is the function that creates the workflow for the protocol
fn get_protocols() -> Vec<(
    String,
    Box<dyn Fn() -> Result<Box<dyn Workflow>, Box<dyn Error>> + Send>,
)> {
    let mut res: Vec<(
        String,
        Box<dyn Fn() -> Result<Box<dyn Workflow>, Box<dyn Error>> + Send>,
    )> = vec![];
    let protocols = STATE_MANAGER.workflow_state.lock().unwrap().task["protocols"].clone();
    if let Some(protocols_obj) = protocols.as_object() {
        for (protocol, val) in protocols_obj.iter() {
            if let Some(name) = val.get("name").and_then(|n| n.as_str()) {
                let protocol = protocol.to_string(); // Clone the protocol string
                res.push((
                    name.to_string(),
                    Box::new(move || {
                        Ok(Box::new(ProtocolConfigWorkflow::new(protocol.clone())?)
                            as Box<dyn Workflow>)
                    }),
                ));
            }
        }
    }
    return res;
}

pub struct CreateConfigWorkflow {
    current_screen: usize,
    child_workflows: Vec<Box<dyn Workflow>>,
}

impl CreateConfigWorkflow {
    pub fn new() -> Result<Self, Box<dyn Error>> {
        STATE_MANAGER.workflow_state.lock()?.task = load_template_config()?;

        Ok(CreateConfigWorkflow {
            current_screen: 0,
            child_workflows: vec![],
        })
    }
}

impl Workflow for CreateConfigWorkflow {
    fn next_screen(
        &mut self,
        new_workflows: Option<Vec<Box<dyn Workflow>>>,
    ) -> Result<WorkflowResult, Box<dyn std::error::Error>> {
        match process_nested_workflows(&mut self.child_workflows, new_workflows)? {
            WorkflowResult::NextScreen(screen) => return Ok(WorkflowResult::NextScreen(screen)),
            WorkflowResult::Finished => {
                self.current_screen += 1;
                return self.get_screen();
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

impl CreateConfigWorkflow {
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
                return Ok(WorkflowResult::NextScreen(Box::new(
                    GenericMultiSelectScreen::new(
                        get_protocols()
                            .iter()
                            .map(|(name, _)| name.clone())
                            .collect::<Vec<String>>(),
                        "Which protocols do you want to deploy?".to_string(),
                        Box::new(|selected| handle_selected_protocols(selected)),
                    ),
                )));
            }
            5 => {
                let task = STATE_MANAGER.workflow_state.lock()?.task.clone();
                let chain_id = STATE_MANAGER
                    .workflow_state
                    .lock()?
                    .chain_id
                    .clone()
                    .unwrap();

                let mut task_path = get_config_dir(chain_id);

                std::fs::create_dir_all(task_path.clone())?;
                task_path = task_path.join("task-pending.json");
                std::fs::write(task_path.clone(), serde_json::to_string_pretty(&task)?)?;

                return Ok(WorkflowResult::NextScreen(Box::new(
                    TextDisplayScreen::new(format!(
                        "Config created and saved successfully to {}",
                        task_path.display()
                    )),
                )));
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

fn handle_selected_protocols(
    selected: Vec<usize>,
) -> Result<ScreenResult, Box<dyn std::error::Error>> {
    let mut workflows = vec![];
    for &selected in &selected {
        let (_, workflow_creator) = &get_protocols()[selected];
        workflows.push(workflow_creator()?);
    }
    if workflows.is_empty() {
        return Ok(ScreenResult::NextScreen(None));
    }
    Ok(ScreenResult::NextScreen(Some(workflows)))
}
