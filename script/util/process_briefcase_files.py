import os
import re
import sys


def parse_flattened_file(file_path):
    with open(file_path, 'r') as file:
        lines = file.readlines()

    main_pragma_version = None

    for line in lines:
        # First specified Solidity Version is used for all blocks by default
        if line.startswith("pragma solidity"):
            if not main_pragma_version:
                main_pragma_version = line.strip()
                break

    code_blocks = []
    current_block = {'source': None, 'content': '',
                     'pragma': main_pragma_version}

    for line in lines:
        # Some files are not flattened correctly and still have (unnecessary) import statements, ignore those
        if line.startswith("import {") or line.startswith("import \"") or line.startswith("import '"):
            continue

        # License is taken from source file, so can be ignored
        if line.startswith("// SPDX-License-Identifier:"):
            continue

        # Block has a specified solidity version
        if line.startswith("pragma solidity"):
            current_block["pragma"] = line.strip()
            continue

        # Additional pragma lines are also taken from source file, so can be ignored
        if line.startswith("pragma"):
            continue

        if line.startswith("// src/") or line.startswith("// lib/"):
            if current_block["source"]:
                code_blocks.append(current_block)
                current_block = {
                    'source': line.strip(), 'content': '', 'pragma': main_pragma_version}
            else:
                current_block['source'] = line.strip()

            continue

        current_block['content'] += line

    code_blocks.append(current_block)

    return code_blocks


def get_pragma_and_license_from_source_file(source_file, parse_pragma_versions=False):
    if parse_pragma_versions:
        pragma_pattern = re.compile(r"^\s*pragma\s+[^;]+;")
    else:
        pragma_pattern = re.compile(r"^\s*pragma\s+(?!solidity)[^;]+;")

    license_pattern = re.compile(
        r"^\s*//\s*SPDX-License-Identifier:\s*([^\s]+)")

    additional_pragma_lines = []
    license = None

    with open(source_file, 'r') as file:
        for line in file:
            if license_pattern.match(line):
                license = line.strip()
            if pragma_pattern.match(line):
                additional_pragma_lines.append(line.strip())

    return additional_pragma_lines, license


def remove_comments_and_assembly(code):
    # Remove single-line comments
    code = re.sub(r'//.*', '', code)
    # Remove multi-line comments
    code = re.sub(r'/\*.*?\*/', '', code, flags=re.DOTALL)

    # Pattern to find assembly blocks (with optional annotation like ("memory-safe"))
    # Since Python allows no recursive regex, we need to be greedy for the last '}' it can find and find the correct end of block ourselves
    assembly_pattern = r'assembly\s*\(?.*?\)?\s*\{(.*\n?)*\}'
    match = re.search(assembly_pattern, code, re.DOTALL)

    while match:
        # Now we need to handle nested curly braces inside assembly code
        assembly_code = match.group(0)
        open_braces = 0
        start_idx = match.start()
        end_idx = match.end()

        # Traverse the matched assembly block to handle nested braces
        for i in range(start_idx, end_idx):
            if code[i] == '{':
                open_braces += 1
            elif code[i] == '}':
                open_braces -= 1
                if open_braces == 0:
                    # Found the matching closing brace
                    end_idx = i + 1
                    break

        # Remove the full assembly block from the code
        code = code[:start_idx] + code[end_idx:]

        # Search for the next assembly block
        match = re.search(assembly_pattern, code, re.DOTALL)

    return code


def get_imported_identifiers_in_source_file(source_file):
    # Regular expression to match import statements with curly braces
    import_with_braces_regex = r"import\s*{([^}]+)}\s*from\s*['\"]([^'\"]+)['\"]\s*;"

    # Regular expression to match import statements without curly braces
    import_without_braces_regex = r"import\s*['\"]([^'\"]+\.sol)['\"]\s*;"

    imported_identifiers = []

    with open(source_file, 'r') as file:
        sol_content = file.read()

        matches_with_braces = re.findall(import_with_braces_regex, sol_content)

        for match in matches_with_braces:
            identifiers = match[0].split(',')
            identifiers = [identifier.strip() for identifier in identifiers]
            imported_identifiers.extend(identifiers)

        matches_without_braces = re.findall(
            import_without_braces_regex, sol_content)

        for match in matches_without_braces:
            filename = os.path.basename(match)
            class_name = filename.replace('.sol', '')
            class_name = class_name[0].upper() + class_name[1:]
            imported_identifiers.append(class_name)

    return imported_identifiers


def parse_content_for_identifier_definitions(content):
    identifiers = []
    functions = []
    # Define regex patterns for contracts, structs, interfaces, and libraries
    identifier_pattern = r'\b(?:interface|contract|type|library|struct)\s+(\w+)\b'
    function_pattern = r'\b(?:function)\s+(\w+)\b'
    # Remove comments
    content = remove_comments_and_assembly(content)

    # Initialize scope level
    scope_level = 0

    for line in content.splitlines():
        # Only handle top-level definitions
        if scope_level == 0 and line:
            identifier_match = re.search(
                identifier_pattern, line, re.MULTILINE)
            function_match = re.search(function_pattern, line, re.MULTILINE,)
            if identifier_match:
                identifiers.append(identifier_match.group(1))
                identifier_match = re.search(
                    identifier_pattern, line, re.MULTILINE,)
            if function_match:
                functions.append(function_match.group(1))

        for char in line:
            if char == '{':
                scope_level += 1
            elif char == '}':
                scope_level -= 1

    return identifiers, functions


def get_used_identifiers(code, identifiers):
    code = remove_comments_and_assembly(code)

    identifiers_pattern = '|'.join(re.escape(identifier)
                                   for identifier in identifiers)
    pattern = rf"(?<![\w.])({identifiers_pattern})(?!\w)"
    # Compile with verbose mode to make the pattern easier to read
    pattern_compiled = re.compile(pattern, re.VERBOSE | re.DOTALL)
    # Find all matches of identifier
    matches = pattern_compiled.findall(code)
    # Collect unique identifier names from matches
    used_identifiers = set()
    for match in matches:
        if match in identifiers:
            used_identifiers.add(match)

    return list(used_identifiers)


def get_relative_path(src_path, dest_path):
    relative_path = os.path.relpath(src_path, os.path.dirname(dest_path))
    if not relative_path.startswith('.'):
        relative_path = os.path.join(".", relative_path)
    return relative_path


def write_file(path, code_block, license, pragma, identifiers, functions, imports):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as file:
        if license:
            file.write(license + "\n")
        file.write(pragma + "\n\n")

        for dest_path in identifiers:
            if dest_path != path:
                identifier_names = identifiers[dest_path]
                used_identifiers = get_used_identifiers(
                    code_block, identifier_names)

                used_functions = list(
                    set(functions[dest_path]).intersection(imports))
                if used_functions:
                    used_identifiers += used_functions

                if used_identifiers:
                    relative_path = get_relative_path(dest_path, path)
                    import_statement = create_import_statement(
                        used_identifiers, relative_path)
                    file.write(import_statement)

        file.write("\n" + code_block.strip())


def create_import_statement(identifier_names, relative_path):
    return f'import {{{", ".join(identifier_names)}}} from "{relative_path}";\n'


def process_file(flattened_file, root_directory):
    code_blocks = parse_flattened_file(flattened_file)
    pragma = {}
    license = {}
    identifier_definitions = {}
    function_definitions = {}
    imports_in_source_file = {}
    blocks = {}

    flattened_file_match = re.match(
        r'(.*)/(interface|interfaces|types)/(.*)', flattened_file)

    for block in code_blocks:
        if block['source']:
            source_file = block['source'].replace("// ", "")
        else:
            break

        interface_match = re.match(
            r'src/pkgs/(.*)/(src|contracts)/(interface|interfaces)/(.*)', source_file)
        lib_types_match = re.match(
            r'src/pkgs/(.*)/(src|contracts)/(libraries|types)/(.*)', source_file)
        external_lib_match = re.match(r'(.*?)lib/(.*)', source_file)
        other_match = re.match(
            r'src/pkgs/(.*)/(src|contracts)/(.*)', source_file)

        if interface_match:
            package_name = interface_match.group(1)
            subdir = "interfaces"
            rest_of_path = interface_match.group(4)
        elif lib_types_match:
            package_name = lib_types_match.group(1)
            subdir = lib_types_match.group(3)
            rest_of_path = lib_types_match.group(4)
        elif external_lib_match:
            package_name = ''
            subdir = "lib-external"
            rest_of_path = external_lib_match.group(2)
        elif other_match:
            package_name = other_match.group(1)
            subdir = ''
            rest_of_path = other_match.group(3)
        else:
            continue

        content = block['content']

        dest_path = os.path.join(
            root_directory, package_name, subdir, rest_of_path)

        identifier_definitions[dest_path], function_definitions[dest_path] = parse_content_for_identifier_definitions(
            content)

        imports_in_source_file[dest_path] = get_imported_identifiers_in_source_file(
            source_file)

        if flattened_file_match:
            additional_pragma_from_source, license[dest_path] = get_pragma_and_license_from_source_file(
                source_file, parse_pragma_versions=False)
            pragma[dest_path] = block['pragma'] + '\n' + \
                '\n'.join(additional_pragma_from_source)
        else:
            complete_pragma_from_source, license[dest_path] = get_pragma_and_license_from_source_file(
                source_file, parse_pragma_versions=True)
            pragma[dest_path] = '\n'.join(complete_pragma_from_source)

        # if the current file isn't the recognized source file, it will be/has been processed separately (guaranteed)
        if interface_match and dest_path != flattened_file:
            continue

        blocks[dest_path] = content

    for dest_path, block in blocks.items():
        write_file(dest_path, block, license[dest_path],
                   pragma[dest_path], identifier_definitions, function_definitions, imports_in_source_file[dest_path])


def process_all_files_in_directory(directory):
    for root, _, files in os.walk(directory):
        for file in files:
            if file.endswith('.sol'):
                filepath = os.path.join(root, file)
                process_file(filepath, directory)


if __name__ == "__main__":
    directory = sys.argv[1]
    if not directory.endswith('/'):
        directory += '/'

    process_all_files_in_directory(directory)
