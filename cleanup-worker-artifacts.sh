#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

github_origin_url="${GITHUB_ORIGIN_URL:-https://github.com/StingrayDigital/cursor-my-machine}"

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

verify_github_checkout() {
  local actual_origin_url

  [[ -d "$script_dir/.git" ]] || fail "Run this script from the GitHub worker checkout."

  actual_origin_url="$(git -C "$script_dir" remote get-url origin)"
  [[ "$(normalize_git_url "$actual_origin_url")" == "$(normalize_git_url "$github_origin_url")" ]] || fail "Unexpected origin '$actual_origin_url'. Expected '$github_origin_url'."
}

cleanup_artifacts() {
  local artifact_path
  local artifact_paths=(
    "$script_dir/.agent-workspaces"
    "$script_dir/.playwright-mcp"
  )

  for artifact_path in "${artifact_paths[@]}"; do
    [[ -e "$artifact_path" ]] || continue

    if rm -rf "$artifact_path" 2>/dev/null; then
      continue
    fi

    if remove_artifact_as_wsl_root "$artifact_path"; then
      continue
    fi

    warn "Could not remove ${artifact_path#"$script_dir"/}; fix ownership or remove it manually."
  done
}

remove_artifact_as_wsl_root() {
  local artifact_path="$1"
  local distro_name="${WSL_DISTRO_NAME:-}"

  [[ -n "$distro_name" ]] || return 1
  command -v wsl.exe >/dev/null 2>&1 || return 1

  wsl.exe -d "$distro_name" -u root -- rm -rf "$artifact_path" >/dev/null 2>&1
}

main() {
  verify_github_checkout

  write_section "Cleaning generated worker artifacts"
  cleanup_artifacts

  write_section "Checkout status"
  git -C "$script_dir" status --short --ignored
}

main "$@"
