use std::path::PathBuf;

use crate::state_manager::STATE_MANAGER;
use serde_json::Value;

pub fn load_template_config() -> Result<Value, Box<dyn std::error::Error>> {
    let working_dir = STATE_MANAGER.working_directory.clone();
    let task_template_file = working_dir
        .join("script")
        .join("deploy")
        .join("tasks")
        .join("task_template.json");

    let task_template_content = std::fs::read_to_string(&task_template_file)?;
    let task_template = serde_json::from_str(&task_template_content)?;
    Ok(task_template)
}

pub fn get_config_dir(chain_id: String) -> PathBuf {
    let working_dir = STATE_MANAGER.working_directory.clone();
    let config_path = working_dir
        .join("script")
        .join("deploy")
        .join("tasks")
        .join(chain_id);
    config_path
}
