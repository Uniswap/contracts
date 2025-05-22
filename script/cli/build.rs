use reqwest;
use std::{env, fs};

fn main() {
    let clean = env::var("CLEAN").unwrap_or("false".to_string()) == "true";
    fs::create_dir_all("./src/assets").expect("Failed to create assets directory");
    if clean {
        // Download chains.json using reqwest
        let response = reqwest::blocking::get("https://chainid.network/chains.json")
            .expect("Failed to download chains.json");

        if !response.status().is_success() {
            panic!("Failed to download chains.json: HTTP {}", response.status());
        }

        let content = response
            .bytes()
            .expect("Failed to read chains response body");
        fs::write("./src/assets/chains.json", content).expect("Failed to write chains.json");

        // Tell cargo to re-run this if chains.json changes
        println!("cargo:rerun-if-changed=src/assets/chains.json");

        // Download etherscan_chainlist.json using reqwest
        let response = reqwest::blocking::get("https://api.etherscan.io/v2/chainlist")
            .expect("Failed to download etherscan_chainlist.json");

        if !response.status().is_success() {
            panic!(
                "Failed to download etherscan_chainlist.json: HTTP {}",
                response.status()
            );
        }

        let content = response
            .bytes()
            .expect("Failed to read etherscan_chainlist response body");
        fs::write("./src/assets/etherscan_chainlist.json", content)
            .expect("Failed to write etherscan_chainlist.json");

        // Tell cargo to re-run this if etherscan_chainlist.json changes
        println!("cargo:rerun-if-changed=src/assets/etherscan_chainlist.json");
    }
}
