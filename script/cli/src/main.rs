mod debug;
mod screen_manager;
mod screens;
mod ui;

use crossterm::{
    cursor::{Hide, MoveTo, Show},
    event::{poll, read, Event, KeyCode},
    execute,
    terminal::{
        disable_raw_mode, enable_raw_mode, Clear, ClearType, EnterAlternateScreen,
        LeaveAlternateScreen,
    },
    Result,
};
use std::io::{stdout, Write};
use std::time::Duration;
use ui::{render_ascii_title, Buffer};

fn main() -> Result<()> {
    enable_raw_mode()?;
    let mut stdout = stdout();
    execute!(stdout, EnterAlternateScreen, Hide, Clear(ClearType::All))?;

    let result = run_main_menu();

    clean_terminal()?;
    result
}

fn clean_terminal() -> Result<()> {
    let mut stdout = stdout();
    disable_raw_mode()?;
    execute!(
        stdout,
        LeaveAlternateScreen,
        Show,
        Clear(ClearType::All),
        MoveTo(0, 0)
    )?;
    stdout.flush()?;

    Ok(())
}

fn run_main_menu() -> Result<()> {
    let mut stdout = stdout();
    let mut buffer = Buffer::new();
    let mut screen_manager = screen_manager::ScreenManager::new();

    loop {
        render_ascii_title(&mut buffer)?;
        screen_manager.render(&mut buffer);
        buffer.draw(&mut stdout)?;

        if poll(Duration::from_millis(16))? {
            let event = read()?;
            if let Event::Key(key_event) = event {
                if key_event.code == KeyCode::Char('q') || key_event.code == KeyCode::Esc {
                    break;
                }
            }
            screen_manager.handle_input(event);
        }
    }

    Ok(())
}
