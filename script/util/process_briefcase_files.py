import os
import re
import sys


def parse_flattened_file(file_path):
    with open(file_path, "r") as file:
        lines = file.readlines()

    main_pragma_version = None

    for line in lines:
        # First specified Solidity Version is used for all blocks by default
        if line.startswith("pragma solidity"):
            if not main_pragma_version:
                main_pragma_version = line.strip()
                break

    code_blocks = []
    current_block = {"source": None, "content": "", "pragma": main_pragma_version}

    for line in lines:
        if (
            line.startswith("import {")
            or line.startswith('import "')
            or line.startswith("import '")
        ):
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

        # Flatten currently produces buggy lines (when processing "/// @inheritdoc" statements), delete those until fixed
        if line.strip() == "///":
            continue

        if line.startswith("// src/") or line.startswith("// lib/"):
            if current_block["source"]:
                code_blocks.append(current_block)
                current_block = {
                    "source": line.strip(),
                    "content": "",
                    "pragma": main_pragma_version,
                    "imports": [],
                }
            else:
                current_block["source"] = line.strip()

            continue

        current_block["content"] += line

    code_blocks.append(current_block)

    return code_blocks


def get_pragma_and_license_from_source_file(source_file):
    pragma_version_pattern = re.compile(r"^\s*pragma\s+solidity\s+[^;]+;")
    pragma_additional_pattern = re.compile(r"^\s*pragma\s+(?!solidity\s)[^;]+;")
    license_pattern = re.compile(r"^\s*//\s*SPDX-License-Identifier:\s*([^\s]+)")

    pragma_version_line = None
    pragma_additional_lines = []
    license = None

    with open(source_file, "r") as file:
        for line in file:
            if license_pattern.match(line):
                license = line.strip()
            if pragma_version_pattern.match(line):
                pragma_version_line = line.strip()
            if pragma_additional_pattern.match(line):
                pragma_additional_lines.append(line.strip())

    return pragma_version_line, pragma_additional_lines, license


def remove_comments_and_assembly(code):
    # Remove single-line comments
    code = re.sub(r"//.*", "", code)
    # Remove multi-line comments
    code = re.sub(r"/\*.*?\*/", "", code, flags=re.DOTALL)

    # Pattern to find assembly blocks (with optional annotation like ("memory-safe"))
    # Since Python allows no recursive regex, we need to be greedy for the last '}' it can find and find the correct end of block ourselves
    assembly_pattern = r"assembly\s*\(?.*?\)?\s*\{(.*\n?)*\}"
    match = re.search(assembly_pattern, code, re.DOTALL)

    while match:
        # Now we need to handle nested curly braces inside assembly code
        assembly_code = match.group(0)
        open_braces = 0
        start_idx = match.start()
        end_idx = match.end()

        # Traverse the matched assembly block to handle nested braces
        for i in range(start_idx, end_idx):
            if code[i] == "{":
                open_braces += 1
            elif code[i] == "}":
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


def get_imported_identifiers_from_code(code):
    # Regular expression to match import statements with curly braces
    import_with_braces_regex = r"import\s*{([^}]+)}\s*from\s*['\"]([^'\"]+)['\"]\s*;"

    # Regular expression to match import statements without curly braces
    import_without_braces_regex = r"import\s*['\"]([^'\"]+\.sol)['\"]\s*;"

    imported_identifiers = []

    matches_with_braces = re.findall(import_with_braces_regex, code)

    for match in matches_with_braces:
        identifiers = match[0].split(",")
        identifiers = [identifier.strip() for identifier in identifiers]
        imported_identifiers.extend(identifiers)

    matches_without_braces = re.findall(import_without_braces_regex, code)

    for match in matches_without_braces:
        filename = os.path.basename(match)
        class_name = filename.replace(".sol", "")
        class_name = class_name[0].upper() + class_name[1:]
        imported_identifiers.append(class_name)

    return imported_identifiers


def get_imported_identifiers_in_source_file(source_file):
    with open(source_file, "r") as file:
        sol_content = file.read()
        imported_identifiers = get_imported_identifiers_from_code(sol_content)

    return imported_identifiers


def parse_content_for_identifier_definitions(content):
    identifiers = []
    functions = []
    # Define regex patterns for contracts, structs, interfaces, and libraries
    identifier_pattern = r"\b(?:interface|contract|type|library|struct)\s+(\w+)\b"
    function_pattern = r"\b(?:function)\s+(\w+)\b"
    # Remove comments
    content = remove_comments_and_assembly(content)

    # Initialize scope level
    scope_level = 0

    for line in content.splitlines():
        # Only handle top-level definitions
        if scope_level == 0 and line:
            identifier_match = re.search(identifier_pattern, line, re.MULTILINE)
            function_match = re.search(
                function_pattern,
                line,
                re.MULTILINE,
            )
            if identifier_match:
                identifiers.append(identifier_match.group(1))
                identifier_match = re.search(
                    identifier_pattern,
                    line,
                    re.MULTILINE,
                )
            if function_match:
                functions.append(function_match.group(1))

        for char in line:
            if char == "{":
                scope_level += 1
            elif char == "}":
                scope_level -= 1

    return identifiers, functions


def get_used_identifiers(code, identifiers):
    code = remove_comments_and_assembly(code)

    self_declared_identifiers, _ = parse_content_for_identifier_definitions(code)
    # It's possible an identifier was declared twice in flattened file, it shouldn't try to import a contract with its own name
    identifiers = [
        identifier
        for identifier in identifiers
        if identifier not in self_declared_identifiers
    ]

    identifiers_pattern = "|".join(re.escape(identifier) for identifier in identifiers)
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
    if not relative_path.startswith("."):
        relative_path = os.path.join(".", relative_path)
    return relative_path


def write_file(
    path, code_block, license, pragma, identifiers, functions, imports, overwrite=False
):
    if not overwrite and os.path.exists(path):
        return

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as file:
        if license:
            file.write(license + "\n")
        file.write(pragma + "\n\n")

        for dest_path in identifiers:
            if dest_path != path:
                identifier_names = identifiers[dest_path]
                used_identifiers = get_used_identifiers(code_block, identifier_names)

                used_functions = list(set(functions[dest_path]).intersection(imports))
                if used_functions:
                    used_identifiers += used_functions

                if used_identifiers:
                    relative_path = get_relative_path(dest_path, path)
                    import_statement = create_import_statement(
                        used_identifiers, relative_path
                    )
                    file.write(import_statement)

        file.write("\n" + code_block.strip())


def create_import_statement(identifier_names, relative_path):
    return f'import {{{", ".join(identifier_names)}}} from "{relative_path}";\n'


def check_if_should_overwrite_pragma(flattened_file_path):
    if re.match(r"(.*)/(interface|interfaces|types)/(.*)", flattened_file_path):
        return True

    flattened_file_name = os.path.basename(flattened_file_path)
    if re.match(r"^I[A-Z]", flattened_file_name):
        return True

    return False


# Normalize pragma version statement for potential whitespace so comparison is safer
def normalize_pragma_version(pragma_version):
    match = re.match(r"^\s*pragma\s+solidity\s+([^;]+);", pragma_version)
    return f"pragma solidity {match.group(1)};" if match else pragma_version


def process_file(flattened_file, contracts_dir, target_dir):
    code_blocks = parse_flattened_file(flattened_file)
    pragma = {}
    license = {}
    identifier_definitions = {}
    function_definitions = {}
    imports_in_source_file = {}
    blocks = {}

    # get packages under src/pkgs
    pkgs_dir = os.path.join(contracts_dir, "src", "pkgs")
    available_packages = [
        pkg
        for pkg in os.listdir(pkgs_dir)
        if os.path.isdir(os.path.join(pkgs_dir, pkg))
    ]

    for block in code_blocks:
        if block["source"]:
            source_file = block["source"].replace("// ", "")
        else:
            break

        # if a package in src/pkgs is part of a lib, use the main src instead
        path_parts = source_file.split(os.sep)
        for i in range(len(path_parts) - 1, -1, -1):
            if path_parts[i] in available_packages:
                path_parts = path_parts[i:]
                break

        if source_file.startswith("src/pkgs"):
            source_file = os.path.join("src", "pkgs", *path_parts)

        interface_match = re.match(
            r"src/pkgs/(.*)/(src|contracts)/(interface|interfaces)/(.*)", source_file
        )
        lib_types_match = re.match(
            r"src/pkgs/(.*)/(src|contracts)/(libraries|types)/(.*)", source_file
        )
        external_lib_match = re.match(r"(.*?)lib/(.*)", source_file)
        other_match = re.match(r"src/pkgs/(.*)/(src|contracts)/(.*)", source_file)

        if interface_match:
            package_name = interface_match.group(1)
            subdir = "interfaces"
            rest_of_path = interface_match.group(4)
        elif lib_types_match:
            package_name = lib_types_match.group(1)
            subdir = lib_types_match.group(3)
            rest_of_path = lib_types_match.group(4)
        elif external_lib_match:
            package_name = ""
            subdir = "lib-external"
            rest_of_path = external_lib_match.group(2)
        elif other_match:
            package_name = other_match.group(1)
            subdir = ""
            rest_of_path = other_match.group(3)
        else:
            continue

        content = block["content"]

        dest_path = os.path.join(
            contracts_dir, target_dir, package_name, subdir, rest_of_path
        )

        identifier_definitions[dest_path], function_definitions[dest_path] = (
            parse_content_for_identifier_definitions(content)
        )

        imports_in_source_file[dest_path] = get_imported_identifiers_in_source_file(
            os.path.join(contracts_dir, source_file)
        )

        pragma_version, additional_pragma, license_from_source = (
            get_pragma_and_license_from_source_file(
                os.path.join(contracts_dir, source_file)
            )
        )

        license[dest_path] = license_from_source

        overwrite_pragma = check_if_should_overwrite_pragma(dest_path)

        # If source flattened file is interface or type, we want to make sure pragma version gets overwritten
        if overwrite_pragma:
            if normalize_pragma_version(pragma_version) != "pragma solidity >=0.5.0;":
                pragma_version = "pragma solidity >=0.6.2;"

        pragma[dest_path] = "\n".join([pragma_version] + additional_pragma)
        blocks[dest_path] = content

    for dest_path, block in blocks.items():
        write_file(
            dest_path,
            block,
            license[dest_path],
            pragma[dest_path],
            identifier_definitions,
            function_definitions,
            imports_in_source_file[dest_path],
            overwrite_pragma,
        )


def process_all_files_in_directory(flattened_dir, contracts_dir, target_dir):
    print(f"Writing briefcase files to {os.path.join(contracts_dir, target_dir)}")
    for root, _, files in os.walk(flattened_dir):
        for file in files:
            if file.endswith(".sol"):
                filepath = os.path.join(root, file)
                process_file(filepath, contracts_dir, target_dir)


if __name__ == "__main__":
    flattened_dir = sys.argv[1]
    contracts_dir = sys.argv[2]
    target_dir = sys.argv[3]
    if not flattened_dir.endswith("/"):
        flattened_dir += "/"
    if not contracts_dir.endswith("/"):
        contracts_dir += "/"
    if not target_dir.endswith("/"):
        target_dir += "/"

    process_all_files_in_directory(flattened_dir, contracts_dir, target_dir)
