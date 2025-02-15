use reqwest;
use std::fs;

fn main() {
    // Create assets directory
    fs::create_dir_all("./src/assets").expect("Failed to create assets directory");

    // Download chains.json using reqwest
    let response = reqwest::blocking::get("https://chainid.network/chains.json")
        .expect("Failed to download chains.json");

    if !response.status().is_success() {
        panic!("Failed to download chains.json: HTTP {}", response.status());
    }

    let content = response.bytes().expect("Failed to read response body");
    fs::write("./src/assets/chains.json", content).expect("Failed to write chains.json");

    // Tell cargo to re-run this if chains.json changes
    println!("cargo:rerun-if-changed=src/assets/chains.json");
}
