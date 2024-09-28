import os
import json
import re
import sys

def update_initcode(sol_file_path, bytecode):
    with open(sol_file_path, 'r') as sol_file:
        content = sol_file.read()

    new_initcode = f"""
    function initcode() internal pure returns (bytes memory) {{
        return hex'{bytecode[2:]}';
    }}
    """

    updated_content = re.sub(
        r'function initcode\(\) internal pure returns \(bytes memory\) \{[^}]*\}',
        new_initcode,
        content
    )

    with open(sol_file_path, 'w') as sol_file:
        sol_file.write(updated_content)
    print(f"Updated initcode in {sol_file_path}")


def get_bytecode(json_file_path):
    with open(json_file_path, 'r') as json_file:
        data = json.load(json_file)
        return data.get('bytecode', {}).get('object', '')


def process_directory(src_directory, json_directory):
    for root, dirs, files in os.walk(src_directory):
        for file in files:
            if file.endswith('Deployer.sol'):
                class_name = file.replace('Deployer.sol', '')
                json_file_subdirectory = f'{class_name}.sol'
                json_file_name = f'{class_name}.json'
                json_file_path = os.path.join(
                    json_directory, json_file_subdirectory, json_file_name)

                if os.path.exists(json_file_path):
                    print(f"Processing {file} with {json_file_name}")
                    bytecode = get_bytecode(json_file_path)

                    sol_file_path = os.path.join(root, file)
                    update_initcode(sol_file_path, bytecode)
                else:
                    print(f"JSON file {json_file_name} not found for {file}")


if __name__ == "__main__":
    src_directory = sys.argv[1]
    json_directory = sys.argv[2]

    process_directory(src_directory, json_directory)
