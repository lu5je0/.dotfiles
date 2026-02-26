#!/usr/bin/env bash

set -euo pipefail

runs=10
warmups=1
keep_logs=0
workdir=""

usage() {
  cat <<'USAGE'
Usage: benchmark-nvim-startup.sh [-n runs] [-w warmups] [-k] [-C dir]

Benchmark Neovim startup time using: nvim --headless --startuptime <file> +qa

Options:
  -n runs     Number of measured runs (default: 10)
  -w warmups  Number of warmup runs before measurement (default: 1)
  -k          Keep per-run startup log files in a temp directory
  -C dir      Run benchmark from the given directory
  -h          Show this help
USAGE
}

while getopts ":n:w:kC:h" opt; do
  case "$opt" in
    n)
      runs="$OPTARG"
      ;;
    w)
      warmups="$OPTARG"
      ;;
    k)
      keep_logs=1
      ;;
    C)
      workdir="$OPTARG"
      ;;
    h)
      usage
      exit 0
      ;;
    :)
      echo "Missing argument for -$OPTARG" >&2
      usage >&2
      exit 1
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! [[ "$runs" =~ ^[0-9]+$ ]] || [ "$runs" -lt 1 ]; then
  echo "-n runs must be a positive integer" >&2
  exit 1
fi

if ! [[ "$warmups" =~ ^[0-9]+$ ]]; then
  echo "-w warmups must be a non-negative integer" >&2
  exit 1
fi

if ! command -v nvim >/dev/null 2>&1; then
  echo "nvim not found in PATH" >&2
  exit 1
fi

if [ -n "$workdir" ]; then
  cd "$workdir"
fi

log_dir="$(mktemp -d)"
trap 'rm -rf "$log_dir"' EXIT

echo "Neovim: $(nvim --version | head -n 1)"
echo "PWD: $(pwd)"
echo "Warmup runs: $warmups"
echo "Measured runs: $runs"

run_once() {
  local idx="$1"
  local log_file="$log_dir/run-${idx}.log"

  nvim --headless --startuptime "$log_file" +qa >/dev/null 2>&1

  awk '/--- NVIM STARTED ---/ { print $1; found=1; exit } END { if (!found) exit 1 }' "$log_file"
}

for i in $(seq 1 "$warmups"); do
  run_once "warmup-${i}" >/dev/null
done

times_file="$log_dir/times.txt"
for i in $(seq 1 "$runs"); do
  t="$(run_once "$i")"
  printf '%s\n' "$t" | tee -a "$times_file" >/dev/null
  printf 'run %02d: %s ms\n' "$i" "$t"
done

sorted_file="$log_dir/times-sorted.txt"
sort -n "$times_file" > "$sorted_file"

summary="$(awk '
  {
    a[NR]=$1
    sum+=$1
  }
  END {
    if (NR == 0) exit 1
    n=NR
    min=a[1]
    max=a[n]
    if (n % 2 == 1) {
      median=a[(n + 1) / 2]
    } else {
      median=(a[n / 2] + a[n / 2 + 1]) / 2
    }
    avg=sum/n
    printf "min=%.3f median=%.3f avg=%.3f max=%.3f", min, median, avg, max
  }
' "$sorted_file")"

echo "$summary"

if [ "$keep_logs" -eq 1 ]; then
  trap - EXIT
  echo "Startup logs kept at: $log_dir"
fi
