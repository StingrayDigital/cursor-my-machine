#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

github_origin_url="${GITHUB_ORIGIN_URL:-https://github.com/StingrayDigital/cursor-my-machine}"
github_branch="${GITHUB_BRANCH:-main}"

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

remove_local_files() {
  if git -C "$script_dir" clean -ffdx >/dev/null 2>&1; then
    return
  fi

  warn "Normal git clean could not remove every local file; retrying with WSL root."

  if clean_checkout_as_wsl_root; then
    return
  fi

  warn "Could not remove all local files; continuing."
}

clean_checkout_as_wsl_root() {
  local distro_name="${WSL_DISTRO_NAME:-}"

  [[ -n "$distro_name" ]] || return 1
  command -v wsl.exe >/dev/null 2>&1 || return 1

  wsl.exe -d "$distro_name" -u root -- git -c "safe.directory=$script_dir" -C "$script_dir" clean -ffdx >/dev/null 2>&1
}

clean_checkout() {
  remove_local_files
}

main() {
  verify_github_checkout

  write_section "Restoring GitHub checkout for script development"
  git -C "$script_dir" remote set-url --push origin "$github_origin_url"
  git -C "$script_dir" fetch origin
  git -C "$script_dir" reset --hard "origin/$github_branch"
  clean_checkout

  write_section "Checkout status"
  if ! git -C "$script_dir" status --short --ignored; then
    warn "Could not read checkout status; continuing."
  fi
}

main "$@"
