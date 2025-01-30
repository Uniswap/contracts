use crate::screens::types::enter_env_var::{find_in_env_file, save_env_var};
use crate::screens::types::select::SelectComponent;
use crate::screens::types::text_input::TextInputComponent;
use crate::ui::Buffer;
use crossterm::event::Event;
use regex::Regex;
use std::borrow::Borrow;

// Let the user select an option from a list or enter a value manually, handle environment variables
// If there are default options, show to the user to select one, user has an option to enter manually
// If there are no default options, user is prompted to enter the text manually automatically
// After the text is set, check whether the text contains a placeholder for an environment variable
// If it does, check a .env file for the variable first, if not found, check the system environment variables
// If the variable is found, prompt the user to confirm whether to use it
// If the user denies or the variable is not found, they are prompted to enter the variable manually
// After the variable is entered, offer the user to save the variable to the .env file
pub struct SelectOrEnterComponent {
    title: String,
    text_input: TextInputComponent,
    env_var_input: TextInputComponent,
    select: SelectComponent,
    env_save: SelectComponent,
    env_confirm: SelectComponent,
    current_step: Step,
    selected_option: String,
    env_var_name: String,
    env_var: String,
    hidden: bool,
}

#[derive(PartialEq, Debug)]
enum Step {
    EnterManually,
    SelectFromList,
    EnterEnvVar,
    SaveEnvVar,
    ConfirmEnvVar,
    Finished,
}

impl SelectOrEnterComponent {
    pub fn new(
        title: String,
        hidden: bool,
        mut options: Vec<String>,
        text_input_validator: fn(String, usize) -> String,
        env_var_input_validator: fn(String, usize) -> String,
    ) -> Self {
        let mut current_step = Step::EnterManually;
        if !options.is_empty() {
            options.push("Enter manually".to_string());
            current_step = Step::SelectFromList;
        }
        SelectOrEnterComponent {
            title,
            text_input: TextInputComponent::new(hidden, "".to_string(), text_input_validator),
            env_var_input: TextInputComponent::new(hidden, "".to_string(), env_var_input_validator),
            select: SelectComponent::new(options),
            env_save: SelectComponent::new(vec!["Yes".to_string(), "No".to_string()]),
            env_confirm: SelectComponent::new(vec!["Yes".to_string(), "No".to_string()]),
            current_step,
            selected_option: "".to_string(),
            env_var: "".to_string(),
            env_var_name: "".to_string(),
            hidden,
        }
    }

    pub fn render(&self, buffer: &mut Buffer) {
        if self.current_step == Step::SelectFromList {
            buffer.append_row_text(&format!("Select {}\n", self.title));
            self.select.render(buffer);
            self.select.render_default_instructions(buffer);
        } else if self.current_step == Step::EnterManually {
            buffer.append_row_text(&format!("Enter {}\n", self.title));
            self.text_input.render(buffer);
            self.text_input.render_default_instructions(buffer);
        } else if self.current_step == Step::EnterEnvVar {
            buffer.append_row_text(&format!("Enter {} variable\n", self.env_var_name));
            self.env_var_input.render(buffer);
            self.env_var_input.render_default_instructions(buffer);
        } else if self.current_step == Step::SaveEnvVar {
            buffer.append_row_text(&format!(
                "Do you want to save this environment variable?\n\n{}: {}\n",
                self.env_var_name,
                mask_env_var(&self.env_var, self.hidden)
            ));
            self.env_save.render(buffer);
            self.env_save.render_default_instructions(buffer);
        } else if self.current_step == Step::ConfirmEnvVar {
            buffer.append_row_text(&format!(
                "Environment variable found:\n\n{}: {}\n\nDo you want to use it?\n",
                self.env_var_name,
                mask_env_var(&self.env_var, self.hidden)
            ));
            self.env_confirm.render(buffer);
            self.env_confirm.render_default_instructions(buffer);
        } else if self.current_step == Step::Finished {
        }
    }

    pub fn handle_input(&mut self, event: Event) -> Option<String> {
        // if there are no default options or the user has selected to enter the text manually, render the text input
        if self.current_step == Step::EnterManually {
            let selected_option = self.text_input.handle_input(event.clone());
            if let Some(selected_option) = selected_option {
                if !selected_option.is_empty() {
                    self.set_selected_option(selected_option);
                }
            }
        }
        // if there are default options, render the text selection
        else if self.current_step == Step::SelectFromList {
            let index = self.select.handle_input(event.clone());
            if index.borrow().is_some() {
                if index.unwrap() == self.select.options.len() - 1 {
                    self.current_step = Step::EnterManually;
                } else {
                    self.set_selected_option(self.select.options[index.unwrap()].clone());
                }
            }
        } else if self.current_step == Step::EnterEnvVar {
            let env_var = self.env_var_input.handle_input(event.clone());
            if env_var.is_some() && !env_var.clone().unwrap().is_empty() {
                self.env_var = env_var.unwrap();
                self.current_step = Step::SaveEnvVar;
            }
        } else if self.current_step == Step::SaveEnvVar {
            let index = self.env_save.handle_input(event.clone());
            if index.borrow().is_some() {
                self.selected_option =
                    replace_env_var(&self.selected_option, &self.env_var_name, &self.env_var);
                if index.unwrap() == 0 {
                    save_env_var(&self.env_var_name, &self.env_var);
                }
                self.current_step = Step::Finished;
            }
        } else if self.current_step == Step::ConfirmEnvVar {
            let index = self.env_confirm.handle_input(event.clone());
            if index.borrow().is_some() {
                if index.unwrap() == 0 {
                    self.selected_option =
                        replace_env_var(&self.selected_option, &self.env_var_name, &self.env_var);
                    self.current_step = Step::Finished;
                } else {
                    self.env_var = "".to_string();
                    self.current_step = Step::EnterEnvVar;
                }
            }
        }
        if self.current_step == Step::Finished {
            return Some(self.selected_option.clone());
        }

        None
    }

    fn set_selected_option(&mut self, selected_option: String) {
        self.selected_option = selected_option;
        // if the text is set and contains an environment variable, first attempt to read it from the system environment, if it is not set, check the .env file next. If it is not found, prompt the user to enter it manually.
        if let Some(captures) = Regex::new(r"\$\{([^}]+)\}")
            .unwrap()
            .captures(&self.selected_option)
        {
            if let Some(env_var_name) = captures.get(1) {
                // found an environment variable in the text
                // read from file first, if not found, read from system environment
                self.env_var_name = env_var_name.as_str().to_string();
                self.env_var = find_in_env_file(&self.env_var_name).unwrap_or("".to_string());

                if !self.env_var.is_empty() {
                    // found in .env file
                    self.current_step = Step::ConfirmEnvVar;
                } else {
                    // not found in file, check system environment
                    let env_var = std::env::var(&self.env_var_name);
                    if env_var.is_ok() && !env_var.clone().unwrap().is_empty() {
                        // found in .env file
                        self.env_var = env_var.unwrap();
                        self.current_step = Step::ConfirmEnvVar;
                    } else {
                        // not found in .env file, prompt user to enter it manually
                        self.current_step = Step::EnterEnvVar;
                    }
                }
            } else {
                // no environment variable found in the text
                self.current_step = Step::Finished;
            }
        } else {
            // no environment variable found in the text
            self.current_step = Step::Finished;
        }
    }
}

fn replace_env_var(text: &str, env_var_name: &str, env_var: &str) -> String {
    // replace the ${env_var_name} in the text with the env_var
    let re = Regex::new(&format!(r"\$\{{{}}}", env_var_name)).unwrap();
    re.replace(text, env_var).to_string()
}

fn mask_env_var(env_var: &str, hidden: bool) -> String {
    if hidden && env_var.len() > 8 {
        format!(
            "{}{}{}",
            &env_var[..4],
            "*".repeat(env_var.len().saturating_sub(8)),
            &env_var[env_var.len().saturating_sub(4)..]
        )
    } else {
        env_var.to_string()
    }
}
