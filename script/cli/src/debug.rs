// this allows to run test code during development so it's not necessary to click through a bunch of screens over and over again. Return false to continue with the normal program flow and show the main menu. Return true to abort the program after the code from this function has been executed. On errors this function will also automatically exit the program. By default this function should be empty and just return false.
pub async fn run() -> Result<bool, Box<dyn std::error::Error>> {
    return Ok(false);
}

// async fn pretty_print_response(url: &str) -> Result<(), Box<dyn std::error::Error>> {
//     let response: Result<reqwest::Response, reqwest::Error> = reqwest::get(url).await;
//     match response {
//         Ok(response) => {
//             println!(
//                 "{}",
//                 serde_json::to_string_pretty(&response.json::<serde_json::Value>().await.unwrap())
//                     .unwrap()
//             );
//             Ok(())
//         }
//         Err(e) => {
//             println!("Error: {:?}", e);
//             Err(e.into())
//         }
//     }
// }
