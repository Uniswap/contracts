mod debug;
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
use std::panic;
use std::process;
use std::time::Duration;
use ui::{render_ascii_title, render_instructions, render_menu, Buffer};

fn main() -> Result<()> {
    // Set up panic hook
    let original_hook = panic::take_hook();
    panic::set_hook(Box::new(move |panic_info| {
        let _ = clean_terminal();
        original_hook(panic_info);
    }));

    // Run the main program logic
    let result = panic::catch_unwind(|| -> Result<()> {
        enable_raw_mode()?;
        let mut stdout = stdout();
        execute!(stdout, EnterAlternateScreen, Hide, Clear(ClearType::All))?;

        let result = run_main_menu();

        clean_terminal()?;
        result
    });

    // Handle the result
    match result {
        Ok(inner_result) => inner_result,
        Err(_) => {
            clean_terminal()?;
            process::exit(1);
        }
    }
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
    let mut selected = 0;
    let mut stdout = stdout();
    let mut buffer = Buffer::new();

    let options = vec!["Create Config", "Deploy Contract", "Exit"];
    loop {
        render_ascii_title(&mut buffer)?;
        render_menu(&mut buffer, &options, selected)?;
        render_instructions(&mut buffer)?;
        // stdout.queue(Clear(ClearType::All))?;
        buffer.draw(&mut stdout)?;

        if poll(Duration::from_millis(16))? {
            if let Event::Key(event) = read()? {
                match event.code {
                    KeyCode::Up => {
                        selected = (selected + options.len() - 1) % options.len();
                    }
                    KeyCode::Down => {
                        selected = (selected + 1) % options.len();
                    }
                    KeyCode::Enter => match options[selected] {
                        "Create Config" => create_config()?,
                        "Deploy Contract" => deploy_contract()?,
                        "Exit" => break,
                        _ => {}
                    },
                    KeyCode::Char('q') | KeyCode::Esc => break,
                    _ => {}
                }
            }
        }
    }

    Ok(())
}

fn create_config() -> Result<()> {
    let mut stdout = stdout();
    execute!(
        stdout,
        Clear(ClearType::All),
        crossterm::cursor::MoveTo(0, 0),
        crossterm::style::Print("Creating config...\n"),
        crossterm::style::Print("Press any key to return to the main menu.")
    )?;
    read()?; // Wait for any key press
    Ok(())
}

fn deploy_contract() -> Result<()> {
    let mut stdout = stdout();
    execute!(
        stdout,
        Clear(ClearType::All),
        crossterm::cursor::MoveTo(0, 0),
        crossterm::style::Print("Coming soon...\n"),
        crossterm::style::Print("Press any key to return to the main menu.")
    )?;
    read()?; // Wait for any key press
    Ok(())
}
