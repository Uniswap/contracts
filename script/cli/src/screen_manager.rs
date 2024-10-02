use super::screens;
use super::ui::Buffer;
use crossterm::event::Event;

pub trait Screen: Send {
    fn handle_input(&mut self, event: Event) -> Option<Vec<Box<dyn Workflow>>>;
    fn render_content(&self, buffer: &mut Buffer);
}

pub trait Workflow: Send {
    fn next_screen(&mut self, new_workflows: Vec<Box<dyn Workflow>>) -> Option<Box<dyn Screen>>;
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

    pub fn set_screen(&mut self, new_screen: Box<dyn Screen>) {
        self.current_screen = new_screen;
    }

    pub fn render(&self, buffer: &mut Buffer) {
        self.current_screen.render_content(buffer);
    }

    pub fn handle_input(&mut self, event: Event) {
        // the current screen is called to handle any user input for itself. Any state changes are handled by the screen itself directly by interacting with the STATE_MANAGER singleton. Only when the screen has completed its task and needs to move to the next screen it will return a value.
        let mut new_workflows = self.current_screen.handle_input(event);
        if new_workflows.is_some() {
            // a screen has returned some value. By default this value should be an empty vector and this is an indicator to move to the next screen. If the screen has returned additional workflows in the vector, these will be passed to the current workflow to handle. An example for additional workflows is in the create_config workflow when the user can select multiple protocols to deploy and the create config workflow will insert additional screens based on the selected protocols.
            if self.active_workflow.is_none() {
                // if there is no active workflow this means that we are on the home screen. The home screen will always return a vector with a single workflow to start.
                self.active_workflow = new_workflows.take().and_then(|mut v| v.pop());
                // get the first screen from the new workflows and set it as the current screen
                let new_screen = self.active_workflow.as_mut().unwrap().next_screen(vec![]);
                self.set_screen(new_screen.unwrap());
            } else {
                // if there is an active workflow this means that we are not on the home screen. The active workflow is notified to display the next screen. Additional workflows are passed to the current workflow to handle.
                let new_screen = self
                    .active_workflow
                    .as_mut()
                    .unwrap()
                    .next_screen(new_workflows.unwrap());
                if new_screen.is_some() {
                    // if a new screen is returned by the workflow, set it as the current screen
                    self.set_screen(new_screen.unwrap());
                } else {
                    // if no new screen is returned by the workflow this means that the workflow has completed. We reset the active workflow and set the current screen to the home screen.
                    self.active_workflow = None;
                    self.set_screen(Box::new(screens::home::HomeScreen::new()));
                }
            }
        }
    }
}
