#!/bin/bash -e

./build.sh

dir=${1:-tmp/}
rm -rf "$dir"
mkdir -p "$dir"

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

  local output_dir="$dir/$project/interfaces"

  local flatten_command="forge flatten"

  echo "processing $project"
  echo ""

  find "$input_dir" -type f -name "*.sol" | while read -r sol_file; do
    relative_path=$(echo "$sol_file" | sed -E "s|$input_dir||")
    output_file="$output_dir$relative_path"

    echo "flattening $sol_file"
    $flatten_command "$sol_file" -o "$output_file"
    replace_pragma_solidity "$output_file" ">=0.6.2"
  done

  echo ""
}

compile_and_flatten_deployers() {
  local source_path=$1

  local input_dir="$source_path"

  local output_dir="$dir/deployers"

  local flatten_command="forge flatten"

  echo "processing deployers"
  echo ""

  find "$input_dir" -type f -name "*.sol" | while read -r sol_file; do
    relative_path=$(echo "$sol_file" | sed -E "s|$input_dir||")
    output_file="$output_dir$relative_path"

    echo "flattening $sol_file"
    $flatten_command "$sol_file" -o "$output_file"
  done

  echo ""
}

# packages
pkgs=$(ls src/pkgs/);
for pkg in $pkgs
do
    interface_subpath=$(find src/pkgs/$pkg -type d \( -path "src/pkgs/$pkg/lib" -prune \) -o \( -name "interface" -o -name "interfaces" \) -print | sed "s|src/pkgs/$pkg/||")
    compile_and_flatten "src/pkgs" "$pkg" "$interface_subpath"
done

# deployers
compile_and_flatten_deployers "src/main/deployers"

python3 script/util/process_interfaces.py "$dir"

cp out/ "$dir"/bytecode -r