import os
import json
import re
import sys
import textwrap
import logging
from typing import Dict, List, Tuple, Optional, Any, Set, Match

# --- Constants ---
# File suffixes
DEPLOYER_SUFFIX = "Deployer.sol"
JSON_SUFFIX = ".json"
SOL_SUFFIX = ".sol"

# JSON Keys (common ones)
BYTECODE_KEY = "bytecode"
OBJECT_KEY = "object"
LINK_REFS_KEY = "linkReferences"
METADATA_KEY = "metadata"
SETTINGS_KEY = "settings"
COMPILER_KEY = "compiler"
COMPILATION_TARGET_KEY = "compilationTarget"
OPTIMIZER_KEY = "optimizer"
RUNS_KEY = "runs"
ENABLED_KEY = "enabled"
VIA_IR_KEY = "viaIR"
EVM_VERSION_KEY = "evmVersion"
VERSION_KEY = "version"

# --- Pre-compiled Regex Patterns ---

# Pattern to find the initcode function in Solidity source
INITCODE_FUNC_PATTERN = re.compile(
    r"""
    (^\s*function\s+initcode\s*\([^)]*\)\s+internal\s+pure\s+returns\s*\(\s*bytes\s+memory\s*\)\s*\{\s*\n) # Group 1: Function definition start
    .*?                                                                                                    # Non-greedy match for the function body
    (\})                                                                                                   # Group 2: Closing brace
    """,
    flags=re.DOTALL | re.VERBOSE | re.MULTILINE,
)

# Pattern to extract the source contract path from deployer comments
SRC_PATH_PATTERN = re.compile(
    r"@notice This initcode is generated from the following contract:\s*\* - Source Contract: (.+)"
)

# Patterns to extract optional filter values from deployer comments
FILTER_PATTERNS = {
    "solc": re.compile(r"\* -\s+solc:\s*(\S+)"),
    "optimizer_runs": re.compile(r"\* -\s+optimizer_runs:\s*(\d+)"),
    "via_ir": re.compile(
        r"\* -\s+via_ir:\s*(true|false)", re.IGNORECASE
    ),  # Allow True/False case-insensitive
    "evm_version": re.compile(r"\* -\s+evm_version:\s*(\S+)"),
}

# Basic validation for library address placeholders in bytecode
# Example: __$0123456789abcdef0123456789abcdef01$__
BYTECODE_PLACEHOLDER_PATTERN = re.compile(r"^__\$[0-9a-fA-F]{34}\$__$")

# --- Logging Configuration ---
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)

# --- Core Logic Functions ---


def update_initcode_in_file(sol_file_path: str, updated_initcode_function: str) -> None:
    """
    Replaces the initcode() function in a Solidity file with the provided code.

    Args:
        sol_file_path: Path to the Solidity deployer file.
        updated_initcode_function: The new initcode function code (including signature and body).

    Raises:
        RuntimeError: If file cannot be read/written or if replacement fails.
        ValueError: If the initcode function signature is not found.
    """
    try:
        with open(sol_file_path, "r", encoding="utf-8") as sol_file:
            content: str = sol_file.read()

        match = INITCODE_FUNC_PATTERN.search(content)
        if not match:
            raise ValueError(
                f"Could not find standard initcode() function signature in {sol_file_path}"
            )

        updated_content = INITCODE_FUNC_PATTERN.sub(
            updated_initcode_function,
            content,
            count=1,  # Replace only the first occurrence
        )

        with open(sol_file_path, "w", encoding="utf-8") as sol_file:
            sol_file.write(updated_content)

    except FileNotFoundError:
        logging.error(f"Solidity file not found: {sol_file_path}")
        raise RuntimeError(f"Solidity file not found: {sol_file_path}")
    except Exception as e:
        logging.error(f"Error updating initcode in {sol_file_path}: {e}")
        raise RuntimeError(f"Error updating initcode in {sol_file_path}: {e}")


def generate_solidity_initcode_function(json_file_path: str) -> str:
    """
    Generates the Solidity initcode() function code string from a JSON artifact.
    Handles bytecode linking by creating function parameters for linked libraries.

    Args:
        json_file_path: Path to the compiler output JSON file.

    Returns:
        A string containing the complete Solidity initcode() function.

    Raises:
        ValueError: If JSON format is invalid, placeholder format is incorrect, or expected keys missing.
        RuntimeError: If file cannot be read or processed.
    """
    try:
        with open(json_file_path, "r", encoding="utf-8") as json_file:
            json_data: Dict[str, Any] = json.load(json_file)

        if BYTECODE_KEY not in json_data or OBJECT_KEY not in json_data[BYTECODE_KEY]:
            raise ValueError(
                f"Missing '{BYTECODE_KEY}.{OBJECT_KEY}' in JSON file: {json_file_path}"
            )

        bytecode: str = json_data[BYTECODE_KEY][OBJECT_KEY]
        # Remove '0x' prefix if present
        if bytecode.startswith("0x"):
            bytecode = bytecode[2:]

        link_references: Dict[str, Any] = json_data[BYTECODE_KEY].get(LINK_REFS_KEY, {})
        solidity_parts: List[str] = []
        parameter_names: Set[str] = set()
        current_pos: int = 0

        if not link_references:
            # No link references, use the bytecode directly in a single string return
            generated_code = f"""\
            function initcode() internal pure returns (bytes memory) {{
                return hex'{bytecode}';
            }}"""
        else:
            # Process link references if they exist
            # Flatten and sort link references by start position for correct processing
            sorted_links: List[Tuple[int, int, str]] = []
            for file_links in link_references.values():
                for contract_name, locations in file_links.items():
                    for loc in locations:
                        # Store start (in hex chars), length (in hex chars), and contract name
                        sorted_links.append(
                            (loc["start"] * 2, loc["length"] * 2, contract_name)
                        )

            sorted_links.sort(key=lambda x: x[0])  # Sort by start position

            for start, length, contract_name in sorted_links:
                placeholder = bytecode[start : start + length]

                # Validation for placeholder format
                if not BYTECODE_PLACEHOLDER_PATTERN.match(placeholder):
                    raise ValueError(
                        f"Invalid placeholder format found in {json_file_path} at position {start // 2}: {placeholder}"
                    )

                # Add the bytecode segment before the placeholder
                if start > current_pos:
                    solidity_parts.append(f"hex'{bytecode[current_pos:start]}'")

                # Add the address parameter
                address_param_name = f"{contract_name}"
                solidity_parts.append(address_param_name)
                parameter_names.add(f"address {address_param_name}")

                current_pos = start + length  # Move position after the placeholder

            # Add the remaining part of the bytecode after the last placeholder
            if current_pos < len(bytecode):
                solidity_parts.append(f"hex'{bytecode[current_pos:]}'")

            # Prepare function parameters list
            parameters_str = ", ".join(parameter_names)

            # Use abi.encodePacked to join all parts together
            concat_code = "abi.encodePacked(" + ", ".join(solidity_parts) + ")"

            generated_code = f"""\
            function initcode({parameters_str}) internal pure returns (bytes memory) {{
                return {concat_code};
            }}"""

        # Return the code block, correctly dedented
        return textwrap.dedent(generated_code)

    except FileNotFoundError:
        logging.error(f"JSON artifact file not found: {json_file_path}")
        raise RuntimeError(f"JSON artifact file not found: {json_file_path}")
    except json.JSONDecodeError as e:
        logging.error(f"Error decoding JSON file {json_file_path}: {e}")
        raise RuntimeError(f"Error decoding JSON file {json_file_path}: {e}")
    except KeyError as e:
        logging.error(f"Missing expected key {e} in JSON file: {json_file_path}")
        raise ValueError(f"Missing expected key {e} in JSON file: {json_file_path}")
    except Exception as e:
        logging.error(f"Error generating initcode from {json_file_path}: {e}")
        raise RuntimeError(f"Error generating initcode from {json_file_path}: {e}")


# --- Filtering and Searching Functions ---


def check_filters_match(json_data: Dict[str, Any], filters: Dict[str, Any]) -> bool:
    """
    Checks if the JSON metadata matches the provided filters.

    Args:
        json_data: The loaded JSON data from the artifact file.
        filters: A dictionary of filters to apply (e.g., {'solc': '0.8.20'}).

    Returns:
        True if all specified filters match, False otherwise.
    """
    metadata: Dict[str, Any] = json_data.get(METADATA_KEY, {})
    settings: Dict[str, Any] = metadata.get(SETTINGS_KEY, {})
    compiler_info: Dict[str, Any] = metadata.get(COMPILER_KEY, {})

    # Check solc version (exact match before '+commit')
    if "solc" in filters:
        json_solc_full: Optional[str] = compiler_info.get(VERSION_KEY)
        if not json_solc_full:
            return False
        json_solc_base = json_solc_full.split("+")[0]
        if json_solc_base != filters["solc"]:
            return False

    # Check optimizer runs
    if "optimizer_runs" in filters:
        json_optimizer: Dict[str, Any] = settings.get(OPTIMIZER_KEY, {})
        json_runs: Optional[int] = json_optimizer.get(RUNS_KEY)
        json_optimizer_enabled: bool = json_optimizer.get(ENABLED_KEY, False)
        # Optimizer must be enabled AND runs must match
        if not json_optimizer_enabled or json_runs != filters["optimizer_runs"]:
            return False

    # Check viaIR
    if "via_ir" in filters:
        # Defaults to False if 'viaIR' key is missing in JSON
        json_via_ir: bool = settings.get(VIA_IR_KEY, False)
        if json_via_ir != filters["via_ir"]:
            return False

    # Check EVM version (case-insensitive comparison)
    if "evm_version" in filters:
        json_evm: Optional[str] = settings.get(EVM_VERSION_KEY)
        if not json_evm or json_evm.lower() != str(filters["evm_version"]).lower():
            return False

    # All specified filters passed
    return True


def search_matching_initcode_json(
    json_directory: str,
    class_name_prefix: str,
    src_file_path_target: str,
    filters: Dict[str, Any],
) -> str:
    """
    Searches recursively for a unique JSON artifact matching criteria.

    Args:
        json_directory: Directory to search for JSON files.
        class_name_prefix: Expected starting part of the JSON filename (e.g., "MyContract.").
        src_file_path_target: Expected source contract path in metadata.settings.compilationTarget.
        filters: Dictionary of additional metadata filters to apply.

    Returns:
        The absolute path to the uniquely matching JSON file.

    Raises:
        ValueError: If zero or more than one JSON file matches the criteria.
        RuntimeError: If there's an error reading or processing a JSON file.
    """
    potential_matches: List[Dict[str, Any]] = []  # Store {'path': str, 'data': dict}

    logging.debug(
        f"Searching in '{json_directory}' for JSON files starting with '{class_name_prefix}'..."
    )

    for json_root, _, json_files in os.walk(json_directory):
        for json_file in json_files:
            # Check if filename starts with prefix and ends with .json
            if json_file.startswith(class_name_prefix) and json_file.endswith(
                JSON_SUFFIX
            ):
                json_file_path = os.path.join(json_root, json_file)
                logging.debug(f"Checking potential match: {json_file_path}")
                try:
                    with open(json_file_path, "r", encoding="utf-8") as f:
                        data: Dict[str, Any] = json.load(f)

                    # Check 1: compilationTarget source path must match
                    metadata = data.get(METADATA_KEY, {})
                    settings = metadata.get(SETTINGS_KEY, {})
                    compilation_target = settings.get(COMPILATION_TARGET_KEY, {})
                    actual_src_path = next(iter(compilation_target), None)

                    if actual_src_path == src_file_path_target:
                        logging.debug(f"  Source path match: '{actual_src_path}'")
                        potential_matches.append({"path": json_file_path, "data": data})
                    else:
                        logging.debug(
                            f"  Source path mismatch (Expected: '{src_file_path_target}', Found: '{actual_src_path}')"
                        )

                except json.JSONDecodeError:
                    logging.warning(f"Skipping invalid JSON file: {json_file_path}")
                    continue
                except Exception as e:
                    logging.error(f"Error processing JSON file {json_file_path}: {e}")
                    raise RuntimeError(
                        f"Error processing JSON file {json_file_path}: {e}"
                    )

    # Check 2: Apply filters to the potential matches
    if not potential_matches:
        raise ValueError(
            f"No JSON file found starting with '{class_name_prefix}' and having source path "
            f"'{src_file_path_target}' in {COMPILATION_TARGET_KEY} within '{json_directory}'."
        )

    logging.debug(
        f"Found {len(potential_matches)} potential matches based on prefix and source path. Applying filters..."
    )

    matching_files: List[str] = []
    filter_str = f"Filters: {filters}" if filters else "No additional filters."

    for match in potential_matches:
        if check_filters_match(match["data"], filters):
            logging.debug(f"  Match passes filters: {match['path']}")
            matching_files.append(match["path"])
        else:
            logging.debug(f"  Match fails filters: {match['path']}")

    # Final Check: Ensure exactly one match
    if len(matching_files) == 0:
        potential_paths = [p["path"] for p in potential_matches]
        raise ValueError(
            f"No JSON file matched all criteria for prefix '{class_name_prefix}'.\n"
            f"  Source Path: '{src_file_path_target}'\n"
            f"  {filter_str}\n"
            f"  Potential candidates checked (based on prefix and source path): {potential_paths}"
        )
    elif len(matching_files) > 1:
        raise ValueError(
            f"Multiple JSON files matched criteria for prefix '{class_name_prefix}'.\n"
            f"  Source Path: '{src_file_path_target}'\n"
            f"  {filter_str}\n"
            f"  Matching files found: {matching_files}"
        )
    else:
        # Exactly one match found
        return matching_files[0]


def extract_deployer_metadata(deployer_file_path: str) -> Dict[str, Any]:
    """
    Extracts source contract path and optional filters from deployer comments.

    Args:
        deployer_file_path: Path to the deployer Solidity file.

    Returns:
        {'src_path': str, 'filters': dict}
              Filters dict contains parsed optional filters found in comments.

    Raises:
        ValueError: If the mandatory source contract path comment is not found or filter parsing fails.
        RuntimeError: If the file cannot be read.
    """
    metadata: Dict[str, Any] = {"src_path": None, "filters": {}}
    try:
        with open(deployer_file_path, "r", encoding="utf-8") as f:
            content = f.read()

        # Mandatory: Source Contract Path
        src_match = SRC_PATH_PATTERN.search(content)
        if src_match:
            metadata["src_path"] = src_match.group(1).strip()
        else:
            raise ValueError(
                f"Required comment '@notice ... - Source Contract: ...' not found in {deployer_file_path}."
            )

        # Optional Filters
        for key, pattern in FILTER_PATTERNS.items():
            match = pattern.search(content)
            if match:
                value_str = match.group(1).strip()
                try:
                    # Type conversion for specific keys
                    if key == "optimizer_runs":
                        metadata["filters"][key] = int(value_str)
                    elif key == "via_ir":
                        metadata["filters"][key] = value_str.lower() == "true"
                    else:  # solc, evm_version are strings
                        metadata["filters"][key] = value_str
                except ValueError as e:
                    raise ValueError(
                        f"Invalid value format for filter '{key}' ('{value_str}') in {deployer_file_path}: {e}"
                    )

        return metadata

    except FileNotFoundError:
        logging.error(f"Deployer file not found: {deployer_file_path}")
        raise RuntimeError(f"Deployer file not found: {deployer_file_path}")
    except Exception as e:
        logging.error(f"Error processing metadata in {deployer_file_path}: {e}")
        raise RuntimeError(f"Error processing metadata in {deployer_file_path}: {e}")


# --- Main Processing Logic ---


def process_deployer_file(deployer_file_path: str, json_directory: str) -> None:
    """
    Processes a single deployer file: extracts metadata, finds matching JSON,
    generates new initcode, and updates the deployer file.

    Raises exceptions from underlying functions on failure.
    """
    logging.info(f"Processing Deployer: {os.path.relpath(deployer_file_path)}")

    # 1. Extract metadata (source path and filters) from Deployer comments
    deployer_meta = extract_deployer_metadata(deployer_file_path)
    src_file_path = deployer_meta["src_path"]
    filters = deployer_meta["filters"]
    logging.info(f"  - Specified Source Contract: {src_file_path}")
    if filters:
        logging.info(f"  - Specified Filters: {filters}")
    else:
        logging.info("  - No additional filters specified.")

    # 2. Derive class name prefix from source file path
    base_name = os.path.basename(src_file_path)
    if base_name.endswith(SOL_SUFFIX):
        class_name_prefix = base_name[: -len(SOL_SUFFIX)] + "."
    else:
        # Handle cases where source path might not end with .sol (unlikely but safer)
        class_name_prefix = base_name + "."
        logging.warning(
            f"Source file path '{src_file_path}' does not end with '{SOL_SUFFIX}'. Using '{class_name_prefix}' as prefix."
        )

    logging.info(f"  - Expecting JSON filename starting with: '{class_name_prefix}'")

    # 3. Search for the unique matching JSON artifact
    logging.info(f"  - Searching for matching JSON in '{json_directory}'...")
    matching_json_path = search_matching_initcode_json(
        json_directory, class_name_prefix, src_file_path, filters
    )
    logging.info(
        f"  - Found unique matching JSON: {os.path.relpath(matching_json_path)}"
    )

    # 4. Generate the new initcode() function code from the JSON
    logging.info("  - Generating new initcode function...")
    updated_initcode_function = generate_solidity_initcode_function(matching_json_path)
    logging.debug(
        f"  - Generated code:\n{textwrap.indent(updated_initcode_function, '    ')}"
    )

    # 5. Update the initcode() function in the deployer file
    logging.info("  - Updating initcode in deployer file...")
    update_initcode_in_file(deployer_file_path, updated_initcode_function)

    logging.info(
        f"  ✅ Successfully updated initcode for {os.path.basename(deployer_file_path)}."
    )


def process_directory(src_directory: str, json_directory: str) -> Tuple[int, int]:
    """
    Walks through the source directory, finds deployer files, and processes them.

    Returns:
        Tuple[int, int]: (processed_count, error_count)
    """
    processed_count = 0
    error_count = 0
    processed_files: List[str] = []
    error_files: Dict[str, str] = {}  # Store filename -> error message

    for root, dirs, files in os.walk(src_directory):
        # Skip hidden directories (like .git, .vscode, etc.) more robustly
        dirs[:] = [d for d in dirs if not d.startswith(".")]

        for file in files:
            # Process only files ending with the deployer suffix
            if file.endswith(DEPLOYER_SUFFIX):
                deployer_file_path = os.path.join(root, file)
                relative_path = os.path.relpath(deployer_file_path, src_directory)
                try:
                    process_deployer_file(deployer_file_path, json_directory)
                    processed_count += 1
                    processed_files.append(relative_path)
                except (ValueError, RuntimeError) as e:
                    # Catch errors specific to processing logic (already logged in functions)
                    logging.error(f"❌ FAILED processing {relative_path}: {e}")
                    error_count += 1
                    error_files[relative_path] = str(e)
                except Exception as e:
                    # Catch unexpected errors
                    logging.exception(
                        f"❌ UNEXPECTED ERROR processing {relative_path}: {e}"
                    )  # Includes traceback
                    error_count += 1
                    error_files[relative_path] = f"Unexpected error: {e}"
                finally:
                    logging.info("-" * 60)  # Separator between files

    # --- Final Summary ---
    logging.info("Script finished.")
    logging.info(f"Successfully processed: {processed_count} Deployer files.")
    if processed_files:
        logging.debug("Processed files:\n - " + "\n - ".join(processed_files))

    logging.info(f"Errors encountered: {error_count}")
    if error_files:
        logging.error("Files with errors:")
        for fname, err in error_files.items():
            logging.error(f" - {fname}: {err}")
    logging.info("-" * 60)

    return processed_count, error_count


# --- Script Entry Point ---
if __name__ == "__main__":
    # Basic argument handling
    if len(sys.argv) != 3:
        print(
            "Usage: python script_name.py <path_to_src_directory> <path_to_json_directory>"
        )
        sys.exit(2)

    src_dir = sys.argv[1]
    json_dir = sys.argv[2]

    if not os.path.isdir(src_dir):
        logging.critical(
            f"Error: Source directory not found or is not a directory: {src_dir}"
        )
        sys.exit(1)
    if not os.path.isdir(json_dir):
        logging.critical(
            f"Error: JSON directory not found or is not a directory: {json_dir}"
        )
        sys.exit(1)

    logging.info("-" * 60)
    logging.info(f"Scanning source directory for deployers: {src_dir}")
    logging.info(f"Searching for JSON artifacts in:        {json_dir}")
    logging.info("-" * 60)

    processed_count, error_count = process_directory(src_dir, json_dir)
