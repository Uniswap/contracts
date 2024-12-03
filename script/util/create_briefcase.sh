#!/bin/bash -e

dir=${1:-src/briefcase/protocols}
rm -rf $dir
tmp_dir="$(mktemp -q -d -t "$(basename "$0").XXXXXX")"

replace_pragma_solidity() {
  local file=$1
  local version=$2
  local temp_file=$(mktemp)
  awk -v version="$version" '/pragma solidity/{if($3 != ">=0.5.0;") {print "pragma solidity " version ";"; next}}1' "$file" > "$temp_file"
  mv "$temp_file" "$file"
}

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
    relative_path=$(echo "$sol_file" | sed -E "s|$input_dir||")
    output_file="$output_dir$relative_path"

    echo "Flattening $sol_file"
    $flatten_command "$sol_file" -o "$output_file"

  if [[ "$input_dir" == *"interface"* || "$input_dir" == *"types"* ]]; then
      replace_pragma_solidity "$output_file" ">=0.6.2"
    fi
  done

  echo ""
}

forge clean
forge build --skip script --skip "src/briefcase/**"

# flatten packages
pkgs=$(ls src/pkgs/);
for pkg in $pkgs
do
    subpaths=$(find src/pkgs/$pkg -type d \( -path "src/pkgs/$pkg/lib" -o -path "src/pkgs/$pkg/test" \) -prune -o \( -name "interface" -o -name "interfaces" -o -name "libraries" -o -name "types" -o -name "base" \) -print | sed "s|src/pkgs/$pkg/||")
    for subpath in $subpaths
    do
      compile_and_flatten "src/pkgs" "$pkg" "$subpath"
    done
done

echo "Inserting current initcode into deployers"
python3 script/util/insert_initcode.py "src/briefcase/deployers" "out" 

echo "Processing source files for briefcase"
python3 script/util/process_briefcase_files.py "$tmp_dir"

echo "Copying files from temporary directory to briefcase"
rsync -ah "$tmp_dir/" "$dir/" --delete
rm -rf "$tmp_dir"
forge fmt "src/briefcase"
# build the generated files
forge build