#!/usr/bin/env bash
set -euo pipefail

# Relux Agents Infra is a shared runtime for Claude Code and Codex. This setup
# keeps pohuy in its external-skill area and lets the runtime fan out symlinks.
skill_name="pohuy"
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_dir="$repo_dir/skills/$skill_name"
infra_repo_url="${RELUX_AGENTS_INFRA_REPO:-https://github.com/relux-works/relux-agents-infra.git}"
runtime_home="${POHUY_RUNTIME_HOME:-$HOME}"
data_root="${XDG_DATA_HOME:-$runtime_home/.local/share}"
infra_checkout="${RELUX_AGENTS_INFRA_DIR:-$data_root/relux-agents-infra}"
agents_skills_dir="$runtime_home/.agents/skills"
installed_dir="$agents_skills_dir/$skill_name"
claude_command="$runtime_home/.claude/commands/pohuy.md"

fail() {
  printf 'setup: %s\n' "$1" >&2
  exit 1
}

for dependency in git rsync; do
  command -v "$dependency" >/dev/null 2>&1 || fail "$dependency is required"
done

[[ -d "$source_dir" ]] || fail "skill source is missing: $source_dir"
[[ ! -L "$installed_dir" ]] || fail "refusing to replace symlinked install: $installed_dir"
if [[ -e "$claude_command" && ! -L "$claude_command" ]]; then
  fail "refusing to replace non-symlink command: $claude_command"
fi

if [[ ! -e "$infra_checkout" ]]; then
  mkdir -p "$(dirname "$infra_checkout")"
  printf 'Installing Relux Agents Infra from %s\n' "$infra_repo_url"
  git clone --depth 1 "$infra_repo_url" "$infra_checkout"
elif [[ ! -d "$infra_checkout/.git" ]]; then
  fail "$infra_checkout exists but is not a git checkout"
else
  infra_origin="$(git -C "$infra_checkout" config --get remote.origin.url || true)"
  if [[ "$infra_origin" != *"relux-works/relux-agents-infra"* &&
        "$infra_origin" != *"relux-works/relux-agents-infra.git"* &&
        "$infra_origin" != "$infra_repo_url" ]]; then
    fail "$infra_checkout has an unexpected origin: $infra_origin"
  fi
  printf 'Reusing Relux Agents Infra checkout: %s\n' "$infra_checkout"
fi

[[ -x "$infra_checkout/setup.sh" ]] || fail "$infra_checkout/setup.sh is not executable"

mkdir -p "$installed_dir"
rsync -a --delete "$source_dir/" "$installed_dir/"
mkdir -p "$installed_dir/commands"
install -m 0644 "$repo_dir/commands/pohuy.md" "$installed_dir/commands/pohuy.md"
install -m 0644 "$repo_dir/LICENSE" "$installed_dir/LICENSE"

# Idempotent: agents-infra owns and refreshes the Claude/Codex skill symlinks.
if command -v agents-infra >/dev/null 2>&1; then
  agents-infra setup global --source-dir "$infra_checkout" --home-dir "$runtime_home"
else
  [[ "$runtime_home" == "$HOME" ]] || fail "isolated install requires an existing agents-infra command"
  "$infra_checkout/setup.sh"
fi

mkdir -p "$(dirname "$claude_command")"
rm -f "$claude_command"
ln -s "$installed_dir/commands/pohuy.md" "$claude_command"

printf 'Installed pohuy once and exposed it through Relux Agents Infra:\n'
printf '  Source:  %s\n' "$installed_dir"
printf '  Claude:  %s\n' "$runtime_home/.claude/skills/$skill_name"
printf '  Codex:   %s\n' "$runtime_home/.codex/skills/$skill_name"
printf '  Command: %s\n' "$claude_command"
