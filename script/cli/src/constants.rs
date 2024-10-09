use crossterm::style::Color;

pub const DEFAULT_COLOR: Color = Color::Reset;

pub const SELECTION_COLOR: Color = Color::Rgb {
    r: 255,
    g: 20,
    b: 147,
};

pub const INSTRUCTIONS_COLOR: Color = Color::Blue;
