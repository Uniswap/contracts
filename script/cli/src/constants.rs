use crossterm::style::Color;

pub const DEFAULT_COLOR: Color = Color::Reset;

pub const GREY_COLOR: Color = Color::Rgb {
    r: 128,
    g: 128,
    b: 128,
};

pub const SELECTION_COLOR: Color = Color::Rgb {
    r: 255,
    g: 20,
    b: 147,
};

pub const INSTRUCTIONS_COLOR: Color = Color::Blue;
