#!/bin/bash
# Script to generate test environments and measure ls/find performance
set -eu

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

N_FILES=100000
FILE_SIZE_MB=5
TEST_ROOT="test_env"
ENV_A="$TEST_ROOT/A"
ENV_B="$TEST_ROOT/B"
REPORT="test-report.md"

get_cpu_count() {
  if command -v getconf >/dev/null 2>&1; then
    getconf _NPROCESSORS_ONLN
  elif [ -f /proc/cpuinfo ]; then
    grep -c '^processor' /proc/cpuinfo
  else
    echo 1
  fi
}

NPROC=$(get_cpu_count)

setup() {
  log "Initializing test environments..."
  rm -rf "$ENV_A" "$ENV_B"
  mkdir -p "$ENV_A" "$ENV_B"
}

create_env_a() {
  log "Creating environment A: ${N_FILES} files of ${FILE_SIZE_MB}MB each"
  seq 1 "$N_FILES" | xargs -n1 -P "$NPROC" bash -c 'dd if=/dev/urandom of="$1/file_$2.dat" bs=1M count="$3" status=none' _ "$ENV_A" "{}" "$FILE_SIZE_MB"
  log "Environment A created."
}

create_env_b() {
  log "Creating environment B: ${N_FILES} directories each with a ${FILE_SIZE_MB}MB file"
  seq 1 "$N_FILES" | xargs -n1 -P "$NPROC" bash -c 'dir="$1/dir_$2"; mkdir -p "$dir"; dd if=/dev/urandom of="$dir/file.dat" bs=1M count="$3" status=none' _ "$ENV_B" "{}" "$FILE_SIZE_MB"
  log "Environment B created."
}

parse_metrics() {
  local log_file=$1
  real=$(grep 'Elapsed (wall clock) time' "$log_file" | awk '{print $8}')
  user=$(grep 'User time (seconds)' "$log_file" | awk '{print $4}')
  sys=$(grep 'System time (seconds)' "$log_file" | awk '{print $4}')
  cpu=$(grep 'Percent of CPU this job got' "$log_file" | awk '{print $8}')
  mem=$(grep 'Maximum resident set size' "$log_file" | awk '{print $6}')
  echo "$real;$user;$sys;$cpu;$mem"
}

measure_command() {
  local label=$1; shift
  log "Running $label..."
  local log_file="${label// /_}.log"
  /usr/bin/time -v "$@" > /dev/null 2> "$log_file"
  metrics=$(parse_metrics "$log_file")
  IFS=";" read -r real user sys cpu mem <<< "$metrics"
  printf '| %s | %s | %s | %s | %s | %s |\n' "$label" "$real" "$user" "$sys" "$cpu" "$mem" >> "$REPORT"
  rm -f "$log_file"
}

run_tests() {
  log "Running benchmarks..."
  echo "# Test Report" > "$REPORT"
  echo "| Test | Elapsed | User | System | CPU % | Max RSS (KB) |" >> "$REPORT"
  echo "| --- | --- | --- | --- | --- | --- |" >> "$REPORT"
  measure_command "ls A" ls "$ENV_A"
  measure_command "ls B" ls "$ENV_B"
  measure_command "find A" find "$ENV_A" -name "file_50000.dat"
  measure_command "find B" find "$ENV_B" -path "$ENV_B/dir_50000/file.dat"
  log "Benchmarks complete. Report generated at $REPORT"
}

main() {
  log "Starting file system performance tests"
  setup
  create_env_a
  create_env_b
  run_tests
  log "All tests completed."
}

main "$@"
