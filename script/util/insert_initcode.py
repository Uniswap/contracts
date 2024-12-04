import os
import json
import re
import sys
import textwrap


def update_initcode(sol_file_path, updated_initcode):
    with open(sol_file_path, 'r') as sol_file:
        content = sol_file.read()

    initcode_pattern = r"""
        \s*(function\s+initcode\s*\(([^)]*)\)\s+internal\s+pure\s+returns\s*\(\s*bytes\s+memory\s*\)\s*\{\s*\n)  # function definition, with optional parameters
        (.*?)   # Match any content in the function body
        (\})    # Closing brace
    """

    updated_content = re.sub(
        initcode_pattern,
        updated_initcode,
        content,
        flags=re.DOTALL | re.VERBOSE | re.MULTILINE
    )

    with open(sol_file_path, 'w') as sol_file:
        sol_file.write(updated_content)

    print(f"Updated initcode in {sol_file_path}")


def generate_solidity_initcode(json_file_path):
    with open(json_file_path, 'r') as json_file:
        json_data = json.load(json_file)

    bytecode = json_data["bytecode"]["object"][2:]
    link_references = json_data["bytecode"]["linkReferences"]
    solidity_parts = []
    parameter_names = []
    current_pos = 0

    if not link_references:
        # No link references, use the bytecode directly in a single string return
        generated_code = f"""\
        
        function initcode() internal pure returns (bytes memory) {{
            return hex'{bytecode}';
        }}"""
    else:
        # Process link references if they exist
        for file_path, links in link_references.items():
            for contract_name, locations in links.items():
                for location in locations:
                    start = location["start"] * 2  # Convert to hex position
                    length = location["length"] * 2  # Convert to hex length
                    placeholder = bytecode[start:start + length]

                    # Check if placeholder matches expected format __$...$__
                    if not re.match(r"^__\$[0-9a-f]{34}\$__$", placeholder):
                        raise ValueError(
                            f"Invalid placeholder format found: {placeholder}")

                    # Add the segment before the placeholder to the parts list
                    solidity_parts.append(
                        f"hex'{bytecode[current_pos:start]}'")
                    address_param = f"{contract_name}"
                    parameter_names.append(address_param)
                    # Add address parameter to the parts list
                    solidity_parts.append(address_param)
                    current_pos = start + length  # Move position after the placeholder

        # Add remaining part of bytecode after the last placeholder
        solidity_parts.append(f"hex'{bytecode[current_pos:]}'")

        # Prepare function parameters list
        parameters = ", ".join(
            [f"address {param}" for param in parameter_names])

        # Use abi.encodePacked to join all parts together
        concat_code = "abi.encodePacked(" + ", ".join(solidity_parts) + ")"

        generated_code = f"""\
        
        function initcode({parameters}) internal pure returns (bytes memory) {{
            return {concat_code};
        }}"""

    # Ensure correct indentation for the generated code
    indented_code = textwrap.indent(textwrap.dedent(generated_code), "    ")
    return indented_code


# Since multiple contracts with the same name can exist, search for source file specified in metadata.settings.compilationTarget
def search_matching_initcode_json(json_directory, json_file_name, src_file_path):
    for json_root, json_dirs, json_files in os.walk(json_directory):
        for json_file in json_files:
            if json_file == json_file_name:
                json_file_path = os.path.join(json_root, json_file)
                try:
                    # Open and read the JSON file
                    with open(json_file_path, 'r') as f:
                        data = json.load(f)

                    # Extract metadata.settings.compilationTarget
                    compilation_target = data.get('metadata', {}).get(
                        'settings', {}).get('compilationTarget', {})

                    # Compare the extracted value
                    if next(iter(compilation_target), None) == src_file_path:
                        return json_file_path
                except Exception as e:
                    raise RuntimeError(f"Error processing {json_file_name}: {e}")
    
    raise ValueError("Source contract not found in any compilationTarget")


def extract_source_contract_path(deployer_file_path):
    """
    Extracts the source contract path from the comments in a deployer Solidity file.
    """
    try:
        with open(deployer_file_path, 'r') as f:
            content = f.read()

        # Regular expression to match the source contract path in the comment
        pattern = r"@notice This initcode is generated from the following contract:\s*\* - Source Contract: (.+)"
        match = re.search(pattern, content)

        if match:
            source_contract_path = match.group(1)
            return source_contract_path
        else:
            raise ValueError(
                f"Source contract path not found in the deployer script.")
    except Exception as e:
        raise RuntimeError(f"Error processing {deployer_file_path}: {e}")


def process_directory(src_directory, json_directory):
    for root, dirs, files in os.walk(src_directory):
        for file in files:
            if file.endswith('Deployer.sol'):
                class_name = file.replace('Deployer.sol', '')
                json_file_name = f'{class_name}.json'
                deployer_file_path = os.path.join(root, file)

                # Get source file path from notice in Deployer
                try:
                    print(f"Searching JSON file containing initcode for {file} in {json_directory}")
                    src_file_path = extract_source_contract_path(deployer_file_path)
                    json_file_path = search_matching_initcode_json(
                        json_directory, json_file_name, src_file_path)

                    print(f"Processing {file} with bytecode from {json_file_path}")
                    deployer_file_path = os.path.join(root, file)

                    updated_initcode = generate_solidity_initcode(
                        json_file_path)
                    update_initcode(deployer_file_path, updated_initcode)
                except Exception as e:
                    print(
                        f"Error while processing initcode for {file}: {e} \nSkipping {file}")


if __name__ == "__main__":
    src_directory = sys.argv[1]
    json_directory = sys.argv[2]

    process_directory(src_directory, json_directory)
