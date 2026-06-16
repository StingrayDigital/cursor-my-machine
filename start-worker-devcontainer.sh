#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

github_origin_url="${GITHUB_ORIGIN_URL:-https://github.com/StingrayDigital/cursor-my-machine}"
private_workbench_repo_url="${PRIVATE_WORKBENCH_REPO_URL:-git@gitlab.stingray-tooling.com:frontend-html5/cursor-my-machine.git}"
private_workbench_ref="${PRIVATE_WORKBENCH_REF:-master}"

print_usage() {
  cat <<'USAGE'
Usage: ./start-worker-devcontainer.sh [launcher-options]

Syncs the private workbench into this GitHub checkout, disables accidental
GitHub pushes, then starts the Cursor My Machines worker inside the repo
devcontainer.

Any launcher options are forwarded to:
  ./start-cursor-my-machine-devcontainer.sh

Environment overrides:
  GITHUB_ORIGIN_URL, PRIVATE_WORKBENCH_REPO_URL, PRIVATE_WORKBENCH_REF
USAGE
}

write_section() {
  printf '\n=== %s ===\n' "$1"
}

fail() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

warn() {
  printf 'Warning: %s\n' "$1" >&2
}

normalize_git_url() {
  local url="$1"
  printf '%s\n' "${url%.git}"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 is required."
}

verify_github_checkout() {
  local actual_origin_url

  [[ -d "$script_dir/.git" ]] || fail "Run this script from the GitHub worker checkout."

  actual_origin_url="$(git -C "$script_dir" remote get-url origin)"
  [[ "$(normalize_git_url "$actual_origin_url")" == "$(normalize_git_url "$github_origin_url")" ]] || fail "Unexpected origin '$actual_origin_url'. Expected '$github_origin_url'."
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
    --filter='- /README.md' \
    --filter='- /.gitignore' \
    --filter='- /start-worker.sh' \
    --filter='- /start-worker-devcontainer.sh' \
    --filter='- /reset-worker-checkout.sh' \
    "$private_clone_dir/" "$script_dir/"
}

disable_github_push() {
  write_section "Disabling accidental GitHub pushes"
  git -C "$script_dir" remote set-url --push origin DISABLED
}

start_devcontainer_worker() {
  local launcher_path="$script_dir/start-cursor-my-machine-devcontainer.sh"

  [[ -x "$launcher_path" ]] || fail "Synced devcontainer launcher is missing or not executable: $launcher_path"

  write_section "Starting Cursor My Machines devcontainer worker"
  "$launcher_path" --workbench-path "$script_dir" "$@"
}

repair_generated_artifact_ownership() {
  local generated_path
  local user_group

  user_group="$(id -gn)"

  for generated_path in "$script_dir/.agent-workspaces" "$script_dir/.playwright-mcp"; do
    [[ -e "$generated_path" ]] || continue

    if chown -R "$USER:$user_group" "$generated_path" 2>/dev/null; then
      continue
    fi

    if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null && sudo -n chown -R "$USER:$user_group" "$generated_path" 2>/dev/null; then
      continue
    fi

    warn "Could not repair ownership for ${generated_path#"$script_dir"/}; continuing."
  done
}

configure_docker_host() {
  local rancher_desktop_socket="/mnt/wsl/rancher-desktop/run/docker.sock"

  if [[ -z "${DOCKER_HOST:-}" && ! -S /var/run/docker.sock && -S "$rancher_desktop_socket" ]]; then
    export DOCKER_HOST="unix://$rancher_desktop_socket"
  fi
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    print_usage
    exit 0
  fi

  require_command git
  require_command rsync
  require_command docker

  configure_docker_host
  verify_github_checkout
  sync_private_workbench
  disable_github_push
  trap repair_generated_artifact_ownership EXIT
  start_devcontainer_worker "$@"
}

main "$@"
