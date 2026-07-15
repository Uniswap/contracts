#!/bin/bash -e

target_dir=${1:-src/briefcase/protocols}
rm -rf $target_dir
tmp_dir="$(mktemp -q -d -t "$(basename "$0").XXXXXX")"

# flatten worker count; benchmarks show no gain above the core count (flatten
# is CPU-bound), override with BRIEFCASE_JOBS to tune for a specific machine
jobs=${BRIEFCASE_JOBS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu)}
work_list="$tmp_dir/.flatten_work_list"
: > "$work_list"

# queues one flatten job (null-separated sol_file, input_dir, output_dir) per
# source file; all queued jobs run in a single global worker pool afterwards
compile_and_flatten() {
  local source_path=$1
  local project=$2
  local subpath=$3

  local input_dir="$source_path/$project/$subpath"

  local output_dir="$tmp_dir/$project/${subpath##*/}"

  echo "queueing $project/$subpath"

  find "$input_dir" -type f -name "*.sol" -print0 | while IFS= read -r -d '' sol_file; do
    printf '%s\0%s\0%s\0' "$sol_file" "$input_dir" "$output_dir" >> "$work_list"
  done
}

# forge flatten spends most of its runtime re-resolving the project graph, so
# flattening in parallel gives a near-linear speedup; one pool across all
# packages keeps every worker busy regardless of per-directory file counts
run_flatten_jobs() {
  [ -s "$work_list" ] || return 0
  xargs -0 -n 3 -P "$jobs" bash -c '
    sol_file="$1"
    input_dir="$2"
    output_dir="$3"
    relative_path="${sol_file#"$input_dir"/}"
    echo "Flattening $sol_file"
    forge flatten "$sol_file" -o "$output_dir$relative_path"
  ' _ < "$work_list"
}

# flattening and briefcase processing only read sources, not build artifacts,
# so this build is skipped for speed; re-enable for a fail-fast compile check
# forge clean
# forge build --skip script --skip "src/briefcase/**"

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

echo "Flattening $(tr -cd '\0' < "$work_list" | wc -c | awk '{print $1/3}') files with $jobs parallel jobs"
run_flatten_jobs

echo "Processing source files and writing to briefcase"
python3 script/util/process_briefcase_files.py "$tmp_dir" "$(pwd)" "$target_dir"

# clean and build again, when compiling with skipped scripts and briefcase above it compiles some contracts with a different compiler version, so we need to clean and build again so they don't end up in the deployer init codes
forge clean
forge build

echo "Inserting current initcode into deployers"
if ! python3 script/util/insert_initcode.py "src/briefcase/deployers" "out"; then
  rm -rf "$tmp_dir"
  forge fmt "src/briefcase" > /dev/null 2>&1
  exit 1
fi

rm -rf "$tmp_dir"
forge fmt "src/briefcase"
# build the generated files; only src/briefcase/** changed since the last
# build, so an incremental build suffices; re-enable the clean if compiler
# version bleed ever shows up in the generated artifacts
# forge clean
forge build
