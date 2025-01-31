use crate::errors;
use crate::screens;
use crate::ui::Buffer;
use crate::workflows::default_workflow::DefaultWorkflow;
use crate::workflows::error_workflow::ErrorWorkflow;
use crate::workflows::workflow_manager::{Workflow, WorkflowResult};
use crossterm::event::{Event, KeyCode, KeyModifiers};

// The screen manager is called by the main thread to handle the rendering and input handling of the current screen, as well as switching between screens and workflows.
// Screens are steps within a workflow. When rendering a screen, a screen implementation appends rows of text to the buffer. Pre-made components found in `screens/types` can be used to render common UI elements like input fields or selection menus.
pub enum ScreenResult {
    Continue,
    NextScreen(Option<Vec<Box<dyn Workflow>>>),
    PreviousScreen,
    Reset,
}

pub trait Screen: Send {
    fn handle_input(&mut self, event: Event) -> Result<ScreenResult, Box<dyn std::error::Error>>;
    fn render_content(&self, buffer: &mut Buffer) -> Result<(), Box<dyn std::error::Error>>;
    fn execute(&mut self) -> Result<(), Box<dyn std::error::Error>>;
}

pub struct ScreenManager {
    current_screen: Box<dyn Screen>,
    active_workflow: Box<dyn Workflow>,
}

impl ScreenManager {
    pub fn new() -> Self {
        ScreenManager {
            current_screen: Box::new(screens::home::HomeScreen::new()),
            active_workflow: Box::new(DefaultWorkflow::new()),
        }
    }

    pub fn render(&mut self, buffer: &mut Buffer) {
        match self.current_screen.execute() {
            Ok(_) => {}
            Err(error) => {
                errors::log(format!("Execution error: {}", error));
                self.handle_error(error);
            }
        }
        match self.current_screen.render_content(buffer) {
            Ok(_) => {}
            Err(error) => {
                errors::log(format!("Render error: {}", error));
                self.handle_error(error);
            }
        }
    }

    pub fn handle_input(&mut self, event: Event) {
        if let Event::Key(key_event) = event {
            match (key_event.modifiers, key_event.code) {
                (KeyModifiers::CONTROL, KeyCode::Char('z')) => {
                    let result = self.active_workflow.as_mut().previous_screen();
                    self.handle_workflow_result(result);
                }
                (KeyModifiers::NONE, KeyCode::Esc) => {
                    self.reset();
                    return;
                }
                _ => {}
            }
        }

        // the current screen is called to handle any user input for itself. Any state changes are handled by the screen itself directly by interacting with the STATE_MANAGER singleton. Only when the screen has completed its task and needs to move to the next screen it will return a value.
        let result = self.current_screen.handle_input(event);
        if result.is_ok() {
            match result.unwrap() {
                ScreenResult::Continue => {}
                ScreenResult::NextScreen(new_workflows) => {
                    // a screen has returned an instruction to move to the next screen. If the screen has returned additional workflows in the vector, these will be passed to the current workflow to handle. An example for additional workflows is in the create_config workflow when the user can select multiple protocols to deploy and the create config workflow will insert additional screens based on the selected protocols.
                    let result = self.active_workflow.next_screen(new_workflows);
                    let next_screen_instance_failed = result.is_err();
                    self.handle_workflow_result(result);
                    if next_screen_instance_failed {
                        let error_result = self.active_workflow.next_screen(None);
                        self.handle_workflow_result(error_result);
                    }
                }
                ScreenResult::Reset => {
                    self.reset();
                }
                ScreenResult::PreviousScreen => {
                    let result = self.active_workflow.previous_screen();
                    self.handle_workflow_result(result);
                }
            }
        } else {
            let error = result.err().unwrap();
            errors::log(format!("Input error: {}", error));
            self.handle_error(error);
        }
    }

    pub fn reset(&mut self) {
        self.active_workflow = Box::new(DefaultWorkflow::new());
        let result = self.active_workflow.next_screen(None);
        self.handle_workflow_result(result);
    }

    fn handle_error(&mut self, error: Box<dyn std::error::Error>) {
        let workflow_result = self.active_workflow.handle_error(error);
        self.handle_workflow_result(workflow_result);
    }

    fn set_screen(&mut self, new_screen: Box<dyn Screen>) {
        self.current_screen = new_screen;
    }

    fn handle_workflow_result(
        &mut self,
        result: Result<WorkflowResult, Box<dyn std::error::Error>>,
    ) {
        if result.is_ok() {
            match result.unwrap() {
                WorkflowResult::NextScreen(screen) => {
                    // if a new screen is returned by the workflow, set it as the current screen
                    self.set_screen(screen);
                }
                WorkflowResult::Finished => {
                    // the workflow has completed. We reset the active workflow and set the current screen to the home screen.
                    self.reset();
                }
            }
        } else {
            let error = result.err().unwrap();
            errors::log(format!("Workflow error: {}", error));
            self.active_workflow = Box::new(ErrorWorkflow::new(error.to_string()));
        }
    }
}
