use std::fs;
use std::process::Command;

fn main() {
    // Create assets directory
    fs::create_dir_all("./src/assets").expect("Failed to create assets directory");

    // Download chains.json
    let output = Command::new("wget")
        .args([
            "-O",
            "./src/assets/chains.json",
            "https://chainid.network/chains.json",
        ])
        .output()
        .expect("Failed to download chains.json");

    if !output.status.success() {
        panic!("Failed to download chains.json");
    }

    // Tell cargo to re-run this if chains.json changes
    println!("cargo:rerun-if-changed=src/assets/chains.json");
}
