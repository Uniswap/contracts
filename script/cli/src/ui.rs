use crossterm::{
    cursor::MoveTo,
    execute,
    style::{Color, SetForegroundColor},
    terminal, Result,
};

use crate::constants;
use std::io::{stdout, Write};
use std::time::{SystemTime, UNIX_EPOCH};

// The buffer is responsible for rendering the UI. It's a 2D vector of characters and colors that will be rendered to the terminal. The height and width are fetched from the terminal size every cycle, this way the UI can always be redrawn correctly if the terminal size changes. Screens append rows to the buffer line by line and the buffer is rendered to the terminal in its entirety every cycle. At the start of the render cycle the buffer is reset to make sure it's empty.

pub struct Buffer {
    old_content: Vec<Vec<(char, Color)>>,
    content: Vec<Vec<(char, Color)>>,
    width: usize,
    height: usize,
}

impl Buffer {
    pub fn new() -> Self {
        let (width, height) = terminal::size().unwrap();
        Buffer {
            old_content: vec![],
            content: vec![],
            width: width as usize,
            height: height as usize,
        }
    }

    pub fn append_row_text(&mut self, text: &str) -> usize {
        self.append_row_text_color(text, constants::DEFAULT_COLOR)
    }

    pub fn append_row_text_color(&mut self, text: &str, color: Color) -> usize {
        let lines: Vec<String> = text.split('\n').map(String::from).collect();
        for line in lines {
            let row: Vec<(char, Color)> = line.chars().map(|ch| (ch, color)).collect();
            self.append_row(row);
        }
        self.content.len() - 1
    }

    pub fn append_row(&mut self, row: Vec<(char, Color)>) -> usize {
        // when appending a row, if it's too long, cut it off, else pad it with spaces
        if row.len() > self.width {
            self.content.push(row[..self.width].to_vec());
        } else {
            let mut padded_row = row;
            padded_row.resize(self.width, (' ', constants::DEFAULT_COLOR));
            self.content.push(padded_row);
        }
        self.content.len() - 1
    }

    pub fn draw(&mut self) -> Result<()> {
        let mut stdout = stdout();
        let mut rerender_content = false;
        let (width, height) = terminal::size().unwrap();
        if self.old_content != self.content
            || self.height != height as usize
            || self.width != width as usize
        {
            rerender_content = true;
            self.height = height as usize;
            self.width = width as usize;
        }
        if !rerender_content {
            self.reset();
            return Ok(());
        }
        // cut off the excess rows if content exceeds terminal height, otherwise pad the top, so it's always bottom aligned
        let mut content = self.content.clone();
        if content.len() > self.height {
            content.drain(0..(content.len() - self.height));
        } else {
            let empty_rows = self.height - content.len();
            let mut new_content =
                vec![vec![(' ', constants::DEFAULT_COLOR); self.width]; empty_rows];
            new_content.append(&mut content);
            content = new_content;
        }

        for (y, row) in content.iter().enumerate() {
            execute!(stdout, MoveTo(0, y as u16))?;
            let mut current_color = constants::DEFAULT_COLOR;
            for &(ch, color) in row {
                if color != current_color {
                    execute!(stdout, SetForegroundColor(color))?;
                    current_color = color;
                }
                write!(stdout, "{}", ch)?;
            }
        }
        self.reset();
        stdout.flush()?;
        Ok(())
    }

    fn reset(&mut self) {
        self.old_content = self.content.clone();
        self.content = vec![];
    }
}

pub fn render_ascii_title(buffer: &mut Buffer) -> Result<()> {
    let title = vec![
        "  *                       ",
        "   **                     ",
        "    **                    ",
        "     ***  ****            ",
        "      * **************    ",
        "       ******  ********     _   _      _                       ___           _             ___ _    ___ ",
        "       ****     *******    | | | |_ _ (_)____ __ ____ _ _ __  |   \\ ___ _ __| |___ _  _   / __| |  |_ _|",
        "       **  **   ********   | |_| | ' \\| (_-< V  V / _` | '_ \\ | |) / -_) '_ \\ / _ \\ || | | (__| |__ | | ",
        "      **          *******   \\___/|_||_|_/__/\\_/\\_/\\__,_| .__/ |___/\\___| .__/_\\___/\\_, |  \\___|____|___|",
        "    ****         ********                              |_|             |_|         |__/                 ",
        "    ******   ****  *****  ",
        "     ***********     ***  ",
        "       **********    **   ",
        "             *****        ",
        ""
    ];

    // Append each line of the title to the buffer
    for line in title.iter() {
        let row: Vec<(char, Color)> = line
            .chars()
            .enumerate()
            .map(|(x, ch)| (ch, rgb(x as u16, buffer.content.len() as u16)))
            .collect();
        buffer.append_row(row);
    }

    Ok(())
}

pub fn get_spinner_frame() -> char {
    let frames = ["_", "_", "_", "-", "`", "`", "'", "´", "-", "_", "_", "_"];
    let time = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_millis();
    let index = (time as usize / 70) % frames.len();
    frames[index].chars().next().unwrap()
}

#[derive(Eq, PartialEq)]
enum ColorType {
    Colorful,
    Animated,
    Default,
}

const COLOR_TYPE: ColorType = ColorType::Colorful;

fn rgb(x: u16, y: u16) -> Color {
    let frequency = 0.1;
    let speed = 1.0;

    let mut combined = 0.0;

    if COLOR_TYPE == ColorType::Animated {
        // Get the current time since UNIX_EPOCH and use it to calculate the color change
        let time = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_millis();
        let time = (time % 62831853) as f32 / 1000.0;
        combined = (x as f32 + y as f32) * frequency - time * speed;
    } else if COLOR_TYPE == ColorType::Colorful {
        combined = (x as f32 + y as f32) * frequency;
    } else if COLOR_TYPE == ColorType::Default {
        return constants::DEFAULT_COLOR;
    }

    let red = ((combined).sin() * 127.0 + 128.0) as u8;
    let green = ((combined + 2.0).sin() * 127.0 + 128.0) as u8;
    let blue = ((combined + 4.0).sin() * 127.0 + 128.0) as u8;

    Color::Rgb {
        r: red,
        g: green,
        b: blue,
    }
}
