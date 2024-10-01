use super::screens;
use super::ui::Buffer;
use crossterm::event::Event;

pub trait Screen {
    fn handle_input(&mut self, event: Event) -> Vec<Box<dyn Screen>>;
    fn render_title(&self, buffer: &mut Buffer);
    fn render_description(&self, buffer: &mut Buffer);
    fn render_content(&self, buffer: &mut Buffer);
    fn render_error(&self, buffer: &mut Buffer);
    fn render_warning(&self, buffer: &mut Buffer);
    fn render_instructions(&self, buffer: &mut Buffer);
}

pub struct ScreenManager {
    current_screen: Box<dyn Screen>,
}

impl ScreenManager {
    pub fn new() -> Self {
        ScreenManager {
            current_screen: Box::new(screens::home::HomeScreen::new()),
        }
    }

    pub fn set_screen(&mut self, new_screen: Box<dyn Screen>) {
        self.current_screen = new_screen;
    }

    pub fn render(&self, buffer: &mut Buffer) {
        self.current_screen.render_title(buffer);
        self.current_screen.render_description(buffer);
        self.current_screen.render_content(buffer);
        self.current_screen.render_warning(buffer);
        self.current_screen.render_error(buffer);
        self.current_screen.render_instructions(buffer);
    }

    pub fn handle_input(&mut self, event: Event) {
        let mut new_screens = self.current_screen.handle_input(event);
        if new_screens.len() > 0 {
            self.set_screen(new_screens.remove(0));
        }
    }
}
