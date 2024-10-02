mod screen_manager;
mod screens;
mod state_manager;
mod ui;
mod workflows;

use crossterm::{
    cursor::{Hide, MoveTo, Show},
    event::{poll, read, Event, KeyCode, KeyModifiers},
    execute,
    terminal::{
        disable_raw_mode, enable_raw_mode, Clear, ClearType, EnterAlternateScreen,
        LeaveAlternateScreen,
    },
    Result,
};
use screen_manager::ScreenManager;
use signal_hook::{
    consts::{SIGINT, SIGTERM},
    iterator::Signals,
};
use std::io::{stdout, Write};
use std::panic;
use std::thread;
use std::time::Duration;
use ui::{render_ascii_title, Buffer};

fn main() -> Result<()> {
    // clean up terminal on panic or when the program is terminated
    let original_hook = panic::take_hook();
    panic::set_hook(Box::new(move |panic_info| {
        let _ = clean_terminal();
        original_hook(panic_info);
    }));

    let mut signals = Signals::new([SIGTERM, SIGINT])?;
    thread::spawn(move || {
        for _ in signals.forever() {
            clean_terminal().unwrap();
        }
    });

    enable_raw_mode()?;
    let mut stdout = stdout();
    execute!(stdout, EnterAlternateScreen, Hide, Clear(ClearType::All),)?;

    let result = run_main_menu();

    clean_terminal()?;
    result
}

fn clean_terminal() -> Result<()> {
    let mut stdout = stdout();
    let result = disable_raw_mode();
    execute!(
        stdout,
        LeaveAlternateScreen,
        Show,
        Clear(ClearType::All),
        MoveTo(0, 0),
    )?;
    stdout.flush()?;

    result
}

fn run_main_menu() -> Result<()> {
    let mut stdout = stdout();
    let mut buffer = Buffer::new();
    let mut screen_manager = ScreenManager::new();

    // run the main loop, render the current screen, afterwards handle any user input and update the screen accordingly
    loop {
        render_ascii_title(&mut buffer)?;
        screen_manager.render(&mut buffer);
        buffer.draw(&mut stdout)?;

        if poll(Duration::from_millis(16))? {
            let event = read()?;
            if let Event::Key(key_event) = event {
                // if the user presses escape or control c the program will exit
                match (key_event.modifiers, key_event.code) {
                    (KeyModifiers::NONE, KeyCode::Esc) => break,
                    (KeyModifiers::CONTROL, KeyCode::Char('c')) => break,
                    _ => {}
                }
            }
            screen_manager.handle_input(event);
        }
    }

    Ok(())
}
