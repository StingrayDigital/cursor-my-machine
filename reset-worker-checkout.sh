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

verify_github_checkout() {
  local actual_origin_url

  [[ -d "$script_dir/.git" ]] || fail "Run this script from the GitHub worker checkout."

  actual_origin_url="$(git -C "$script_dir" remote get-url origin)"
  [[ "$actual_origin_url" == "$github_origin_url" ]] || fail "Unexpected origin '$actual_origin_url'. Expected '$github_origin_url'."
}

main() {
  verify_github_checkout

  write_section "Restoring GitHub checkout for script development"
  git -C "$script_dir" remote set-url --push origin "$github_origin_url"
  git -C "$script_dir" fetch origin
  git -C "$script_dir" reset --hard "origin/$github_branch"
  git -C "$script_dir" clean -fdx

  write_section "Checkout status"
  git -C "$script_dir" status --short --ignored
}

main "$@"
