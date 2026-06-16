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

remove_generated_artifacts() {
  local generated_path
  local user_group

  user_group="$(id -gn)"

  for generated_path in "$script_dir/.agent-workspaces" "$script_dir/.playwright-mcp"; do
    [[ -e "$generated_path" ]] || continue

    chown -R "$USER:$user_group" "$generated_path" 2>/dev/null || true
    if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
      sudo -n chown -R "$USER:$user_group" "$generated_path" 2>/dev/null || true
    fi

    if ! rm -rf "$generated_path" 2>/dev/null; then
      warn "Could not remove generated artifacts at ${generated_path#"$script_dir"/}; continuing. Fix ownership with: sudo chown -R \"\$USER\":\"\$USER\" \"${generated_path#"$script_dir"/}\""
    fi
  done
}

clean_checkout() {
  remove_generated_artifacts

  if ! git -C "$script_dir" clean -fdx -e .agent-workspaces/ -e .playwright-mcp/; then
    warn "Some untracked files could not be removed; continuing."
  fi
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
