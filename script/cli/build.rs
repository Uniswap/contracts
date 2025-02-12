use std::path::Path;
use std::process::Command;
use std::{env, fs};

fn main() {
    let clean = env::var("CLEAN").unwrap_or("false".to_string()) == "true";
    fs::create_dir_all("./src/assets").expect("Failed to create assets directory");
    if clean {
        fs::remove_file("./src/assets/chains.json").expect("Failed to remove chains.json");
        fs::remove_file("./src/assets/etherscan_chainlist.json")
            .expect("Failed to remove etherscan_chainlist.json");
    }

    // Only download chains.json if it doesn't exist
    let chains_path = Path::new("./src/assets/chains.json");
    if !chains_path.exists() {
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
    }

    let etherscan_path = Path::new("./src/assets/etherscan_chainlist.json");
    if !etherscan_path.exists() {
        let etherscan_chainlist = Command::new("wget")
            .args([
                "-O",
                "./src/assets/etherscan_chainlist.json",
                "https://api.etherscan.io/v2/chainlist",
            ])
            .output()
            .expect("Failed to download etherscan chain list");

        if !etherscan_chainlist.status.success() {
            panic!("Failed to download etherscan chain list");
        }
    }
}
