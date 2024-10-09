mod constants;
mod errors;
mod libs;
mod screens;
mod state_manager;
mod ui;
mod workflows;

use crossterm::{
    cursor::{Hide, MoveTo, MoveToColumn, Show},
    event::{poll, read, Event, KeyCode, KeyModifiers},
    execute,
    terminal::{
        disable_raw_mode, enable_raw_mode, Clear, ClearType, EnterAlternateScreen,
        LeaveAlternateScreen,
    },
    Result,
};
use screens::screen_manager::ScreenManager;
use signal_hook::{
    consts::{SIGINT, SIGTERM},
    iterator::Signals,
};
use std::io::{stdout, Write};
use std::panic;
use std::thread;
use std::time::Duration;
use ui::{render_ascii_title, Buffer};

#[tokio::main]
async fn main() -> Result<()> {
    // clean up terminal on panic or when the program is terminated
    let original_hook = panic::take_hook();
    panic::set_hook(Box::new(move |panic_info| {
        let _ = clean_terminal();
        original_hook(panic_info);
    }));

    let mut signals = Signals::new([SIGTERM, SIGINT])?;
    thread::spawn(move || {
        for _ in signals.forever() {
            let _ = clean_terminal();
        }
    });

    let mut stdout = stdout();
    execute!(stdout, EnterAlternateScreen, Hide,)?;
    enable_raw_mode()?;

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
    let mut buffer = Buffer::new();
    let mut screen_manager = ScreenManager::new();
    let mut debug_mode = false;
    // run the main loop, render the current screen, afterwards handle any user input and update the screen accordingly
    loop {
        render_ascii_title(&mut buffer)?;
        screen_manager.render(&mut buffer);
        if !debug_mode {
            buffer.draw(&mut stdout())?;
        }

        if poll(Duration::from_millis(16))? {
            let event = read()?;

            if let Event::Key(key_event) = event {
                // if the user presses escape or control c the program will exit
                match (key_event.modifiers, key_event.code) {
                    (KeyModifiers::CONTROL, KeyCode::Char('c')) => break,
                    (KeyModifiers::CONTROL, KeyCode::Char('d')) => {
                        // Toggle debug mode
                        debug_mode = !debug_mode;
                        if debug_mode {
                            execute!(stdout(), LeaveAlternateScreen, Show, MoveToColumn(0),)?;
                        } else {
                            execute!(stdout(), EnterAlternateScreen, Hide, Clear(ClearType::All),)?;
                        }
                    }
                    _ => {}
                }
            }
            screen_manager.handle_input(event);
        }
    }

    Ok(())
}
