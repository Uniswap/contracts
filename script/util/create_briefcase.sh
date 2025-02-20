#!/bin/bash -e

target_dir=${1:-src/briefcase/protocols}
rm -rf $target_dir
tmp_dir="$(mktemp -q -d -t "$(basename "$0").XXXXXX")"

compile_and_flatten() {
  local source_path=$1
  local project=$2
  local subpath=$3

  local input_dir="$source_path/$project/$subpath"

  local output_dir="$tmp_dir/$project/${subpath##*/}"

  local flatten_command="forge flatten"

  echo "processing $project/$subpath"
  echo ""

  find "$input_dir" -type f -name "*.sol" | while read -r sol_file; do
    relative_path=$(echo "$sol_file" | sed -E "s|^$input_dir/||")
    output_file="$output_dir$relative_path"

    echo "Flattening $sol_file"
    $flatten_command "$sol_file" -o "$output_file"
  done

  echo ""
}

forge clean
forge build --skip script --skip "src/briefcase/**"

# flatten packages
pkgs=$(ls src/pkgs/);
for pkg in $pkgs
do
    subpaths=$(find src/pkgs/$pkg -type d \( -path "src/pkgs/$pkg/lib" -o -path "src/pkgs/$pkg/test" \) -prune -o \( -name "interface" -o -name "interfaces" -o -name "libraries" -o -name "types" -o -name "util" -o -name "utils" \) -print | sed "s|src/pkgs/$pkg/||")
    for subpath in $subpaths
    do
      compile_and_flatten "src/pkgs" "$pkg" "$subpath"
    done
done

echo "Inserting current initcode into deployers"
python3 script/util/insert_initcode.py "src/briefcase/deployers" "out" 

echo "Processing source files and writing to briefcase"
python3 script/util/process_briefcase_files.py "$tmp_dir" "$(pwd)" "$target_dir"

rm -rf "$tmp_dir"
forge fmt "src/briefcase"
# build the generated files
forge build
