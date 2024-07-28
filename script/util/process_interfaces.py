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
    relative_path = os.path.relpath(src_path, os.path.dirname(dest_path))
    if not relative_path.startswith('.'):
        relative_path = os.path.join(".", relative_path)
    return relative_path


def write_file(path, pragma, imports, block):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as file:
        file.write(pragma)
        for class_name, dest_path in imports.items():
            if class_name in block and dest_path != path:
                relative_path = get_relative_path(dest_path, path)
                import_statement = create_import_statement(
                    class_name, relative_path)
                file.write(import_statement)

        file.write(block)


def create_import_statement(class_name, relative_path):
    return f'import {{{class_name}}} from "{relative_path}";\n'

def process_file(interface_file, root_directory):
    interface_dir = "interfaces"
    library_dir = "libraries"
    type_dir = "types"
    ext_lib_dir = "external_libs"

    code_blocks = parse_code_file(interface_file)
    imports = {}
    blocks = {}

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
        rest_match = re.match(r'lib/(.*)', source_path)
        if match:
            subdir = "interfaces"
            package_name = match.group(1)
            rest_of_path = match.group(4)
        elif lib_match:
            subdir = lib_match.group(3)
            package_name = lib_match.group(1)
            rest_of_path = lib_match.group(4)
        elif rest_match:
            subdir = "external_libs"
            rest_of_path = rest_match.group(1)

            
        content = block['content']

        if subdir == "libraries":
            dest_path = os.path.join(
                root_directory, package_name, library_dir, rest_of_path)
        elif subdir == "types":
            dest_path = os.path.join(
                root_directory, package_name, type_dir, rest_of_path)
        elif subdir == "external_libs":
            dest_path = os.path.join(
                root_directory, ext_lib_dir, rest_of_path)
        else:
            dest_path = os.path.join(
                root_directory, package_name, interface_dir, rest_of_path)
            
        class_name = Path(rest_of_path).name.replace(".sol", "")
        imports[class_name] = dest_path

        # Other interfaces already have an own file and will be processed separatly
        if subdir == "interfaces" and dest_path != interface_file:
            continue
        
        blocks[dest_path] = content

    for dest_path, block in blocks.items():
        write_file(dest_path, pragma, imports, block)

def process_all_files_in_directory(directory):
    for root, _, files in os.walk(directory):
        for file in files:
            if file.endswith('.sol'):
                filepath = os.path.join(root, file)
                process_file(filepath, directory)


if __name__ == "__main__":
    process_all_files_in_directory('tmp')
