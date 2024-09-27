use std::fs::OpenOptions;
use std::io::Write;
pub fn debug_log(message: &str) {
    let mut file = OpenOptions::new()
        .create(true)
        .append(true)
        .open("debug.log")
        .expect("Failed to open log file");

    writeln!(file, "{}", message).expect("Failed to write to log file");
}
