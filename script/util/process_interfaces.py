import os
from pathlib import Path
import re
import shutil


def parse_code_file(file_path):
    with open(file_path, 'r') as file:
        lines = file.readlines()

    code_blocks = []
    current_block = {'content': ''}
    in_block = True

    for line in lines:
        if line.startswith("// src") or line.startswith("// lib"):
            if in_block:
                code_blocks.append(current_block)
            in_block = True
            current_block = {'source': line.strip(), 'content': ''}
        elif in_block:
            current_block['content'] += line

    if in_block:
        code_blocks.append(current_block)

    return code_blocks


def get_relative_path(src_path, dest_path):
    return os.path.join(".", os.path.relpath(src_path, os.path.dirname(dest_path)))


def create_import_statement(class_name, relative_path):
    return f'import {{{class_name}}} from "{relative_path}";\n'

def process_file(interface_file, root_directory):
    interface_dir = "interfaces"
    library_dir = "libraries"
    type_dir = "types"

    code_blocks = parse_code_file(interface_file)
    imports = []
    own_blocks = []

    for i, block in enumerate(code_blocks):
        if i==0:
            pragma = block['content']
            continue

        source_path = block['source'].replace("// ", "")
        subdir = None

        match = re.match(
            r'src/pkgs/(.*?)/(src|contracts)/(interface|interfaces)/(.*)', source_path)
        lib_match = re.match(
            r'src/pkgs/(.*?)/(src|contracts)/(libraries|types)/(.*)', source_path)
        if match:
            subdir = "interfaces"
            package_name = match.group(1)
            rest_of_path = match.group(4)
        elif lib_match:
            subdir = lib_match.group(3)
            package_name = lib_match.group(1)
            rest_of_path = lib_match.group(4)
            
        content = block['content']

        if not subdir or os.path.join(root_directory, package_name, interface_dir, rest_of_path) == interface_file:
            own_blocks.append(content)
        else:
            if subdir == "libraries":
                dest_path = os.path.join(
                    root_directory, package_name, library_dir, rest_of_path)
                os.makedirs(os.path.dirname(dest_path), exist_ok=True)
                shutil.copyfile(source_path, dest_path)
            elif subdir == "types":
                dest_path = os.path.join(
                    root_directory, package_name, type_dir, rest_of_path)
                os.makedirs(os.path.dirname(dest_path), exist_ok=True)
                shutil.copyfile(source_path, dest_path)
            else:
                dest_path = os.path.join(
                    root_directory, package_name, interface_dir, rest_of_path)

            relative_path = get_relative_path(dest_path, interface_file)
            class_name = Path(rest_of_path).name.replace(".sol", "")
            imports.append(create_import_statement(class_name, relative_path))

    with open(interface_file, 'w') as file:
        file.write(pragma)
        for imp in imports:
            file.write(imp)
        for block in own_blocks:
            file.write(block)


def process_all_files_in_directory(directory):
    for root, _, files in os.walk(directory):
        for file in files:
            if file.endswith('.sol'):
                filepath = os.path.join(root, file)
                process_file(filepath, directory)


if __name__ == "__main__":
    process_all_files_in_directory('tmp')
