mod constants;
mod debug;
mod errors;
mod libs;
mod screens;
mod state_manager;
mod ui;
mod util;
mod workflows;

use crossterm::{
    cursor::{Hide, MoveToColumn, Show},
    event::{poll, read, Event, KeyCode, KeyModifiers},
    execute,
    terminal::{enable_raw_mode, Clear, ClearType, EnterAlternateScreen, LeaveAlternateScreen},
    Result,
};
use screens::screen_manager::ScreenManager;
use signal_hook::{
    consts::{SIGINT, SIGTERM},
    iterator::Signals,
};
use state_manager::{clean_terminal, STATE_MANAGER};
use std::{io::stdout, panic, process, thread, time::Duration};
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

    match debug::run().await {
        Ok(true) => process::exit(0),
        Ok(false) => (),
        Err(e) => {
            println!("Error: {}", e);
            process::exit(1);
        }
    }

    let mut stdout = stdout();
    execute!(stdout, EnterAlternateScreen, Hide,)?;
    enable_raw_mode()?;

    let result = run_main_menu();

    clean_terminal()?;
    result
}

fn run_main_menu() -> Result<()> {
    let mut screen_manager = ScreenManager::new();
    let mut buffer = Buffer::new();

    // run the main loop, render the current screen, afterwards handle any user input and update the screen accordingly
    loop {
        render_ascii_title(&mut buffer)?;
        screen_manager.render(&mut buffer);
        if !STATE_MANAGER.workflow_state.lock().unwrap().debug_mode {
            buffer.draw()?;
        }

        if poll(Duration::from_millis(1))? {
            let event = read()?;

            if let Event::Key(key_event) = event {
                // if the user presses escape or control c the program will exit
                match (key_event.modifiers, key_event.code) {
                    (KeyModifiers::CONTROL, KeyCode::Char('c')) => break,
                    (KeyModifiers::CONTROL, KeyCode::Char('d')) => {
                        // Toggle debug mode
                        let debug_mode = STATE_MANAGER.workflow_state.lock().unwrap().debug_mode;
                        STATE_MANAGER.workflow_state.lock().unwrap().debug_mode = !debug_mode;
                        if !debug_mode {
                            execute!(stdout(), LeaveAlternateScreen, Show, MoveToColumn(0),)?;
                        } else {
                            execute!(stdout(), EnterAlternateScreen, Hide, Clear(ClearType::All),)?;
                        }
                    }
                    _ => screen_manager.handle_input(event),
                }
            }
        }
    }

    Ok(())
}
