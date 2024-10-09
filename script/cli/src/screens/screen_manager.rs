use crate::errors;
use crate::screens;
use crate::ui::Buffer;
use crate::workflows::workflow_manager::{Workflow, WorkflowResult};
use crossterm::event::{Event, KeyCode, KeyModifiers};

// The screen manager is called by the main thread to handle the rendering and input handling of the current screen, as well as switching between screens and workflows.
// Screens are steps within a workflow. When rendering a screen, a screen implementation appends rows of text to the buffer. Pre-made components found in `screens/types` can be used to render common UI elements like input fields or selection menus.
pub enum ScreenResult {
    Continue,
    StartWorkflow(Box<dyn Workflow>),
    NextScreen(Option<Vec<Box<dyn Workflow>>>),
    PreviousScreen,
    Reset,
}

pub trait Screen: Send {
    fn handle_input(&mut self, event: Event) -> Result<ScreenResult, Box<dyn std::error::Error>>;
    fn render_content(&self, buffer: &mut Buffer);
    fn execute(&mut self);
}

pub struct ScreenManager {
    current_screen: Box<dyn Screen>,
    active_workflow: Option<Box<dyn Workflow>>,
}

impl ScreenManager {
    pub fn new() -> Self {
        ScreenManager {
            current_screen: Box::new(screens::home::HomeScreen::new()),
            active_workflow: None,
        }
    }

    pub fn render(&mut self, buffer: &mut Buffer) {
        self.current_screen.execute();
        self.current_screen.render_content(buffer);
    }

    pub fn handle_input(&mut self, event: Event) {
        if let Event::Key(key_event) = event {
            match (key_event.modifiers, key_event.code) {
                (KeyModifiers::CONTROL, KeyCode::Char('b')) => {
                    if self.active_workflow.is_some() {
                        let result = self.active_workflow.as_mut().unwrap().previous_screen();
                        self.handle_workflow_result(result);
                    }
                }
                (KeyModifiers::NONE, KeyCode::Esc) => self.reset(),
                _ => {}
            }
        }

        // the current screen is called to handle any user input for itself. Any state changes are handled by the screen itself directly by interacting with the STATE_MANAGER singleton. Only when the screen has completed its task and needs to move to the next screen it will return a value.
        let result = self.current_screen.handle_input(event);
        if result.is_ok() {
            match result.unwrap() {
                ScreenResult::Continue => {}
                ScreenResult::StartWorkflow(workflow) => {
                    self.active_workflow = Some(workflow);
                    let result = self.active_workflow.as_mut().unwrap().next_screen(None);
                    self.handle_workflow_result(result);
                }
                ScreenResult::NextScreen(new_workflows) => {
                    // a screen has returned an instruction to move to the next screen. If the screen has returned additional workflows in the vector, these will be passed to the current workflow to handle. An example for additional workflows is in the create_config workflow when the user can select multiple protocols to deploy and the create config workflow will insert additional screens based on the selected protocols.
                    let result = self
                        .active_workflow
                        .as_mut()
                        .unwrap()
                        .next_screen(new_workflows);
                    self.handle_workflow_result(result);
                }
                ScreenResult::Reset => {
                    self.reset();
                }
                ScreenResult::PreviousScreen => {
                    if self.active_workflow.is_some() {
                        self.active_workflow.as_mut().unwrap().previous_screen();
                    }
                }
            }
        } else {
            let error = result.err().unwrap();
            errors::log(&error.to_string());
            if self.active_workflow.is_some() {
                let workflow_result = self.active_workflow.as_mut().unwrap().handle_error(error);
                self.handle_workflow_result(workflow_result);
            }
        }
    }

    pub fn reset(&mut self) {
        self.active_workflow = None;
        self.set_screen(Box::new(screens::home::HomeScreen::new()));
    }

    fn set_screen(&mut self, new_screen: Box<dyn Screen>) {
        self.current_screen = new_screen;
    }

    fn handle_workflow_result(&mut self, result: WorkflowResult) {
        match result {
            WorkflowResult::NextScreen(screen) => {
                // if a new screen is returned by the workflow, set it as the current screen
                self.set_screen(screen);
            }
            WorkflowResult::Finished => {
                // the workflow has completed. We reset the active workflow and set the current screen to the home screen.
                self.reset();
            }
        }
    }
}
