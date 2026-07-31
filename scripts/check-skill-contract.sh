#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
skill_file="$repo_root/skills/pohuy/SKILL.md"
command_file="$repo_root/commands/pohuy.md"
eval_file="$repo_root/evals/evals.json"
trigger_file="$repo_root/evals/triggers.json"
setup_file="$repo_root/setup.sh"

fail() {
  printf 'check-skill-contract: %s\n' "$1" >&2
  exit 1
}

skill_bytes="$(wc -c < "$skill_file" | tr -d '[:space:]')"
skill_lines="$(wc -l < "$skill_file" | tr -d '[:space:]')"

(( skill_bytes <= 3500 )) || fail "SKILL.md is ${skill_bytes} bytes; budget is 3500"
(( skill_lines <= 80 )) || fail "SKILL.md is ${skill_lines} lines; budget is 80"

grep -Fq 'Explicit opt-in' "$skill_file" || fail "frontmatter must require explicit opt-in"
grep -Fq 'Never activate from incidental profanity' "$skill_file" || fail "incidental profanity guard is missing"
grep -Fq 'Do not preload supplemental references' "$command_file" || fail "command must forbid automatic reference loading"
grep -Fq 'relux-works/relux-agents-infra.git' "$setup_file" || fail "setup must reference the shared agent runtime"
# shellcheck disable=SC2016 # Match the literal setup variable expression.
grep -Fq '$runtime_home/.agents/skills' "$setup_file" || fail "setup must use the external-skill area"
[[ -x "$setup_file" ]] || fail "setup must be executable"
bash -n "$setup_file"

if grep -Eq 'references/|slovar\.md|sceny\.md|ontologia\.md' "$skill_file" "$command_file"; then
  fail "runtime instructions must not require or name supplemental reference files"
fi

example_count="$(grep -Eic 'calibration example' "$skill_file" || true)"
(( example_count <= 1 )) || fail "runtime instructions contain more than one calibration example"

python3 -m json.tool "$eval_file" >/dev/null
python3 -m json.tool "$trigger_file" >/dev/null

python3 - "$eval_file" "$trigger_file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    evals = json.load(handle)
with open(sys.argv[2], encoding="utf-8") as handle:
    triggers = json.load(handle)

budget = evals["context_budget"]
assert budget["skill_md_max_bytes"] == 3500
assert budget["mandatory_reference_loads"] == 0
assert budget["calibration_examples_max"] == 1
assert len(evals["evals"]) >= 5
assert triggers["should_activate"] and triggers["should_not_activate"]

serialized = json.dumps(evals, ensure_ascii=False).lower()
for forbidden in ("new dictionary", "new idiom", "словаря v2", "идиома из"):
    assert forbidden not in serialized, f"phrasebook-coupled expectation remains: {forbidden}"
PY

printf 'check-skill-contract: ok (%s bytes, %s lines, zero mandatory references)\n' \
  "$skill_bytes" "$skill_lines"
