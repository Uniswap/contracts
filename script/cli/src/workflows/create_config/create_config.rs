use crate::screen_manager::{Screen, Workflow};
use crate::screens::config::protocol_selection::ProtocolSelectionScreen;
use crate::screens::shared::chain_id::ChainIdScreen;

pub struct CreateConfigWorkflow {
    current_screen: usize,
}

impl CreateConfigWorkflow {
    pub fn new() -> Self {
        CreateConfigWorkflow { current_screen: 0 }
    }
}

impl Workflow for CreateConfigWorkflow {
    fn next_screen(&mut self, new_workflows: Vec<Box<dyn Workflow>>) -> Option<Box<dyn Screen>> {
        self.current_screen += 1;
        match self.current_screen {
            1 => Some(Box::new(ChainIdScreen::new())),
            2 => Some(Box::new(ProtocolSelectionScreen::new())),
            _ => None,
        }
    }
}
