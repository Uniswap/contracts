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
    cursor::{Hide, MoveTo, MoveToColumn, Show},
    event::{poll, read, Event, KeyCode, KeyModifiers},
    execute,
    terminal::{
        disable_raw_mode, enable_raw_mode, is_raw_mode_enabled, Clear, ClearType,
        EnterAlternateScreen, LeaveAlternateScreen,
    },
    Result,
};
use screens::screen_manager::ScreenManager;
use signal_hook::{
    consts::{SIGINT, SIGTERM},
    iterator::Signals,
};
use state_manager::STATE_MANAGER;
use std::{
    env,
    io::{stdout, Write},
    panic, process, thread,
    time::Duration,
};
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

    check_for_foundry_toml();

    if debug::run().await {
        return Ok(());
    }

    let mut stdout = stdout();
    execute!(stdout, EnterAlternateScreen, Hide,)?;
    enable_raw_mode()?;

    let result = run_main_menu();

    clean_terminal()?;
    result
}

fn clean_terminal() -> Result<()> {
    let mut stdout = stdout();
    if is_raw_mode_enabled().unwrap() {
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
    } else {
        Ok(())
    }
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
                    _ => screen_manager.handle_input(event),
                }
            }
        }
    }

    Ok(())
}

fn check_for_foundry_toml() {
    // check if foundry.toml file exists in the current directory
    let mut current_dir = env::current_dir().unwrap();
    let default_dir = current_dir.clone();
    if !default_dir.join("foundry.toml").exists() {
        // check for constructor argument: --dir <directory>
        let args: Vec<String> = env::args().collect();
        if args.len() > 2 && args[1] == "--dir" {
            let dir = &args[2];
            current_dir = current_dir.join(dir);
            if !current_dir.join("foundry.toml").exists() {
                println!("{} does not exist.", current_dir.to_str().unwrap());
                process::exit(1);
            }
        } else {
            println!("No foundry.toml file found in the current directory. Use the --dir <directory> argument to provide a relative path to your foundry directory containing the foundry.toml file. Example: ./deploy-cli --dir ../path/to/your/foundry_project");
            process::exit(1);
        }
    } else {
        current_dir = default_dir;
    }

    STATE_MANAGER.app_state.lock().unwrap().working_directory = current_dir;
}
