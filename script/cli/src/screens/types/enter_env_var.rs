use crate::screens::types::select::SelectComponent;
use crate::screens::types::text_input::TextInputComponent;
use crate::ui::Buffer;
use crossterm::event::Event;
use regex::Regex;
use std::borrow::Borrow;
use std::io::Write;

pub struct EnterEnvVarComponent {
    env_var_input: TextInputComponent,
    env_save: SelectComponent,
    env_confirm: SelectComponent,
    current_step: Step,
    env_var_name: String,
    env_var: String,
}

#[derive(PartialEq, Debug)]
enum Step {
    EnterEnvVar,
    SaveEnvVar,
    ConfirmEnvVar,
    Finished,
}

// check for environment variable in .env file first, if not found, check system environment variables
// if found, ask user if they want to use it
// if not found, or user chooses not to use it, ask user to enter it manually
// if user enters it manually, ask if they want to save it to .env file
impl EnterEnvVarComponent {
    pub fn new(env_var_name: String, env_var_input_validator: fn(String, usize) -> String) -> Self {
        let mut this = EnterEnvVarComponent {
            env_var_input: TextInputComponent::new(false, "".to_string(), env_var_input_validator),
            env_save: SelectComponent::new(vec!["Yes".to_string(), "No".to_string()]),
            env_confirm: SelectComponent::new(vec!["Yes".to_string(), "No".to_string()]),
            current_step: Step::EnterEnvVar,
            env_var: "".to_string(),
            env_var_name,
        };

        this.env_var = find_in_env_file(&this.env_var_name).unwrap_or("".to_string());

        if !this.env_var.is_empty() {
            // found in .env file
            this.current_step = Step::ConfirmEnvVar;
        } else {
            // not found in file, check system environment
            let env_var = std::env::var(&this.env_var_name);
            if env_var.is_ok() && !env_var.clone().unwrap().is_empty() {
                // found in .env file
                this.env_var = env_var.unwrap();
                this.current_step = Step::ConfirmEnvVar;
            }
        }

        this
    }

    pub fn render(&self, buffer: &mut Buffer) {
        if self.current_step == Step::EnterEnvVar {
            buffer.append_row_text(&format!("Enter {} variable\n", self.env_var_name));
            self.env_var_input.render(buffer);
            self.env_var_input.render_default_instructions(buffer);
        } else if self.current_step == Step::SaveEnvVar {
            buffer.append_row_text(&format!(
                "Do you want to save this environment variable?\n\n{}: {}\n",
                self.env_var_name, self.env_var
            ));
            self.env_save.render(buffer);
            self.env_save.render_default_instructions(buffer);
        } else if self.current_step == Step::ConfirmEnvVar {
            buffer.append_row_text(&format!(
                "Environment variable found:\n\n{}: {}\n\nDo you want to use it?\n",
                self.env_var_name, self.env_var
            ));
            self.env_confirm.render(buffer);
            self.env_confirm.render_default_instructions(buffer);
        } else if self.current_step == Step::Finished {
        }
    }

    pub fn handle_input(&mut self, event: Event) -> Option<String> {
        if self.current_step == Step::EnterEnvVar {
            let env_var = self.env_var_input.handle_input(event.clone());
            if env_var != None && !env_var.clone().unwrap().is_empty() {
                self.env_var = env_var.unwrap();
                self.current_step = Step::SaveEnvVar;
            }
        } else if self.current_step == Step::SaveEnvVar {
            let index = self.env_save.handle_input(event.clone());
            if index.borrow().is_some() {
                if index.unwrap() == 0 {
                    save_env_var(&self.env_var_name, &self.env_var);
                }
                self.current_step = Step::Finished;
            }
        } else if self.current_step == Step::ConfirmEnvVar {
            let index = self.env_confirm.handle_input(event.clone());
            if index.borrow().is_some() {
                if index.unwrap() == 0 {
                    self.current_step = Step::Finished;
                } else {
                    self.env_var = "".to_string();
                    self.current_step = Step::EnterEnvVar;
                }
            }
        }
        if self.current_step == Step::Finished {
            return Some(self.env_var.clone());
        }

        None
    }
}

pub fn find_in_env_file(env_var_name: &str) -> Option<String> {
    if let Ok(env_content) = std::fs::read_to_string(".env") {
        for line in env_content.lines() {
            if let Some((key, value)) = line.split_once('=') {
                if key.trim() == env_var_name {
                    return Some(value.trim().to_string());
                }
            }
        }
    }
    None
}

pub fn save_env_var(env_var_name: &str, env_var: &str) {
    // if the env_var_name already exists, try replacing it with the new value
    if !std::path::Path::new(".env").exists() {
        // Create .env file if it doesn't exist
        std::fs::File::create(".env").unwrap();
    } else {
        // file does not exist, search for the env_var_name
        let env_content = std::fs::read_to_string(".env").unwrap();
        let pattern = format!(r"(?m)^{}=.*$", regex::escape(env_var_name));
        let replaced_env_content = Regex::new(&pattern)
            .unwrap()
            .replace_all(&env_content, format!("{}={}", env_var_name, env_var))
            .to_string();
        // the strings are different so the env_var was replaced, write file and return
        if replaced_env_content != env_content {
            std::fs::write(".env", replaced_env_content).unwrap();
            return;
        }
    }
    // if env_var_name does not exist, add it to the end of the file
    let env_content = format!("{}={}\n", env_var_name, env_var);
    std::fs::OpenOptions::new()
        .append(true)
        .open(".env")
        .unwrap()
        .write_all(env_content.as_bytes())
        .unwrap();
}
