#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
Q_EXTRACT="${DOTFILES_ROOT}/bin/q-extract"

pass_count=0
skip_count=0

assert_file_exists() {
  local path="$1"

  if [[ ! -f "$path" ]]; then
    echo "assert_file_exists failed: '$path'" >&2
    exit 1
  fi
}

assert_file_not_exists() {
  local path="$1"

  if [[ -e "$path" ]]; then
    echo "assert_file_not_exists failed: '$path'" >&2
    exit 1
  fi
}

assert_eq() {
  local actual="$1"
  local expected="$2"

  if [[ "$actual" != "$expected" ]]; then
    printf "assert_eq failed\nexpected: %s\nactual: %s\n" "$expected" "$actual" >&2
    exit 1
  fi
}

require_commands() {
  local cmd

  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      return 1
    fi
  done

  return 0
}

pass_test() {
  local name="$1"

  pass_count=$((pass_count + 1))
  printf 'PASS: %s\n' "$name"
}

skip_test() {
  local name="$1"
  local reason="$2"

  skip_count=$((skip_count + 1))
  printf 'SKIP: %s (%s)\n' "$name" "$reason"
}

make_sample_file() {
  local dir="$1"

  mkdir -p "$dir"
  printf 'hello\n' > "${dir}/sample.txt"
}

run_single_file_case() {
  local format="$1"
  local create_cmd="$2"
  local archive_name="$3"
  local source_name="$4"

  local tmpdir
  local archive_dir
  local output_dir
  local output_file

  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN

  archive_dir="${tmpdir}/archive"
  output_dir="${tmpdir}/out"
  make_sample_file "$archive_dir"
  mkdir -p "$output_dir"

  (
    cd "$archive_dir"
    eval "$create_cmd"
    rm -f "$source_name"
  )

  "${Q_EXTRACT}" "${archive_dir}/${archive_name}" --output_dir "$output_dir" >/dev/null

  output_file="${output_dir}/${source_name}"
  assert_file_exists "$output_file"
  assert_file_not_exists "${archive_dir}/${source_name}"
  assert_eq "$(cat "$output_file")" "hello"

  trap - RETURN
  rm -rf "$tmpdir"
  pass_test "$format"
}

run_archive_case() {
  local format="$1"
  local create_cmd="$2"
  local archive_name="$3"

  local tmpdir
  local archive_dir
  local output_dir
  local output_file

  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN

  archive_dir="${tmpdir}/archive"
  output_dir="${tmpdir}/out"
  make_sample_file "$archive_dir"
  mkdir -p "$output_dir"

  (
    cd "$archive_dir"
    eval "$create_cmd"
  )

  "${Q_EXTRACT}" "${archive_dir}/${archive_name}" --output_dir "$output_dir" >/dev/null

  output_file="${output_dir}/sample.txt"
  assert_file_exists "$output_file"
  assert_eq "$(cat "$output_file")" "hello"

  trap - RETURN
  rm -rf "$tmpdir"
  pass_test "$format"
}

test_tar_bz2() {
  if ! require_commands tar; then
    skip_test "tar.bz2" "tar not installed"
    return
  fi
  run_archive_case "tar.bz2" "tar -cjf sample.tar.bz2 sample.txt" "sample.tar.bz2"
}

test_tbz2() {
  if ! require_commands tar; then
    skip_test "tbz2" "tar not installed"
    return
  fi
  run_archive_case "tbz2" "tar -cjf sample.tbz2 sample.txt" "sample.tbz2"
}

test_tar_gz() {
  if ! require_commands tar; then
    skip_test "tar.gz" "tar not installed"
    return
  fi
  run_archive_case "tar.gz" "tar -czf sample.tar.gz sample.txt" "sample.tar.gz"
}

test_tgz() {
  if ! require_commands tar; then
    skip_test "tgz" "tar not installed"
    return
  fi
  run_archive_case "tgz" "tar -czf sample.tgz sample.txt" "sample.tgz"
}

test_tar_xz() {
  if ! require_commands tar; then
    skip_test "tar.xz" "tar not installed"
    return
  fi
  run_archive_case "tar.xz" "tar -cJf sample.tar.xz sample.txt" "sample.tar.xz"
}

test_txz() {
  if ! require_commands tar; then
    skip_test "txz" "tar not installed"
    return
  fi
  run_archive_case "txz" "tar -cJf sample.txz sample.txt" "sample.txz"
}

test_tar() {
  if ! require_commands tar; then
    skip_test "tar" "tar not installed"
    return
  fi
  run_archive_case "tar" "tar -cf sample.tar sample.txt" "sample.tar"
}

test_bz2() {
  if ! require_commands bzip2 bunzip2; then
    skip_test "bz2" "bzip2/bunzip2 not installed"
    return
  fi
  run_single_file_case "bz2" "bzip2 -zk sample.txt" "sample.txt.bz2" "sample.txt"
}

test_rar() {
  if ! require_commands rar; then
    skip_test "rar" "rar not installed"
    return
  fi
  run_archive_case "rar" "rar a -idq sample.rar sample.txt" "sample.rar"
}

test_gz() {
  if ! require_commands gzip gunzip; then
    skip_test "gz" "gzip/gunzip not installed"
    return
  fi
  run_single_file_case "gz" "gzip -k sample.txt" "sample.txt.gz" "sample.txt"
}

test_zip() {
  if ! require_commands zip unzip; then
    skip_test "zip" "zip/unzip not installed"
    return
  fi
  run_archive_case "zip" "zip -q sample.zip sample.txt" "sample.zip"
}

test_jar() {
  if ! require_commands jar unzip; then
    skip_test "jar" "jar/unzip not installed"
    return
  fi
  run_archive_case "jar" "jar --create --file sample.jar sample.txt >/dev/null" "sample.jar"
}

test_Z() {
  if ! require_commands compress uncompress; then
    skip_test "Z" "compress/uncompress not installed"
    return
  fi
  run_single_file_case "Z" "compress -k sample.txt" "sample.txt.Z" "sample.txt"
}

test_7z() {
  if ! require_commands 7z; then
    skip_test "7z" "7z not installed"
    return
  fi
  run_archive_case "7z" "7z a -bd -y sample.7z sample.txt >/dev/null" "sample.7z"
}

tests=(
  test_tar_bz2
  test_tbz2
  test_tar_gz
  test_tgz
  test_tar_xz
  test_txz
  test_tar
  test_bz2
  test_rar
  test_gz
  test_zip
  test_jar
  test_Z
  test_7z
)

for test_name in "${tests[@]}"; do
  "$test_name"
done

printf 'SUMMARY: %d passed, %d skipped\n' "$pass_count" "$skip_count"
