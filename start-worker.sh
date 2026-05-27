#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

github_origin_url="${GITHUB_ORIGIN_URL:-https://github.com/StingrayDigital/cursor-my-machine}"
private_workbench_repo_url="${PRIVATE_WORKBENCH_REPO_URL:-git@gitlab.stingray-tooling.com:frontend-html5/cursor-my-machine.git}"
private_workbench_ref="${PRIVATE_WORKBENCH_REF:-master}"
worker_name="${WORKER_NAME:-cursor-my-machine-github}"

write_section() {
  printf '\n=== %s ===\n' "$1"
}

fail() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 is required."
}

verify_github_checkout() {
  local actual_origin_url

  [[ -d "$script_dir/.git" ]] || fail "Run this script from the GitHub worker checkout."

  actual_origin_url="$(git -C "$script_dir" remote get-url origin)"
  [[ "$actual_origin_url" == "$github_origin_url" ]] || fail "Unexpected origin '$actual_origin_url'. Expected '$github_origin_url'."
}

sync_private_workbench() {
  local temp_dir
  local private_clone_dir

  temp_dir="$(mktemp -d)"
  private_clone_dir="$temp_dir/private-workbench"

  cleanup() {
    rm -rf "$temp_dir"
  }
  trap cleanup RETURN

  write_section "Cloning private workbench"
  git clone --quiet --depth 1 --branch "$private_workbench_ref" "$private_workbench_repo_url" "$private_clone_dir"
  rm -rf "$private_clone_dir/.git"

  write_section "Syncing workbench files into GitHub worker checkout"
  rsync -a --delete \
    --filter='P /.git/***' \
    --filter='P /README.md' \
    --filter='P /.gitignore' \
    --filter='P /start-worker.sh' \
    "$private_clone_dir/" "$script_dir/"
}

disable_github_push() {
  write_section "Disabling accidental GitHub pushes"
  git -C "$script_dir" remote set-url --push origin DISABLED
}

start_worker() {
  local launcher_path="$script_dir/start-cursor-my-machine.sh"

  [[ -x "$launcher_path" ]] || fail "Synced launcher is missing or not executable: $launcher_path"

  write_section "Starting Cursor My Machines worker"
  "$launcher_path" --workbench-path "$script_dir" --worker-name "$worker_name"
}

main() {
  require_command git
  require_command rsync

  verify_github_checkout
  sync_private_workbench
  disable_github_push
  start_worker
}

main "$@"
