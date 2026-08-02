#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
skill_file="$repo_root/skills/pohuy/SKILL.md"
command_file="$repo_root/commands/pohuy.md"
eval_file="$repo_root/evals/evals.json"
trigger_file="$repo_root/evals/triggers.json"
setup_file="$repo_root/setup.sh"
gitignore_file="$repo_root/.gitignore"

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

for ignored_path in \
  '.agents/' \
  '.claude/' \
  '.codex/' \
  '.local/' \
  '.task-board/' \
  '.temp/' \
  'AGENTS.md' \
  'agents-attachments-manifest.json' \
  'task-board.config.json'; do
  grep -Fxq "$ignored_path" "$gitignore_file" || \
    fail ".gitignore must ignore task-local artifact: $ignored_path"
done

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
expected_budget = {
    "skill_md_max_bytes": 3500,
    "skill_md_max_lines": 80,
    "mandatory_reference_loads": 0,
    "calibration_examples_max": 1,
}
for field, expected in expected_budget.items():
    actual = budget.get(field)
    assert actual == expected, f"context_budget.{field} must be {expected}, found {actual!r}"

thresholds = evals["quality_thresholds"]
required_threshold_fields = (
    "facts",
    "required_actions",
    "tone",
    "severity",
    "safety",
    "total",
    "material_factual_errors",
)
missing_thresholds = [field for field in required_threshold_fields if field not in thresholds]
assert not missing_thresholds, f"quality_thresholds is missing fields: {missing_thresholds}"

cases = evals["evals"]
assert isinstance(cases, list), "evals.evals must be a list of eval cases"
assert len(cases) >= 5, f"evals.evals must contain at least 5 cases, found {len(cases)}"
required_case_fields = (
    "id",
    "prompt",
    "required_facts",
    "required_actions",
    "tone",
    "must_not",
)
case_ids = []
for case_index, case in enumerate(cases):
    assert isinstance(case, dict), f"eval case at index {case_index} must be an object"
    missing = [field for field in required_case_fields if field not in case]
    assert not missing, f"eval case {case.get('id', '?')} is missing fields: {missing}"
    assert isinstance(case["id"], str) and case["id"], "eval case id must be a non-empty string"
    assert isinstance(case["prompt"], str) and case["prompt"], f"{case['id']}: prompt must be non-empty"
    assert isinstance(case["tone"], str) and case["tone"], f"{case['id']}: tone must be non-empty"
    for field in ("required_facts", "required_actions", "must_not"):
        value = case[field]
        assert isinstance(value, list) and value, f"{case['id']}: {field} must be a non-empty list"
        assert all(isinstance(item, str) and item for item in value), f"{case['id']}: {field} entries must be non-empty strings"
    case_ids.append(case["id"])
assert len(case_ids) == len(set(case_ids)), "eval case ids must be unique"

for trigger_group in ("should_activate", "should_not_activate"):
    values = triggers[trigger_group]
    assert isinstance(values, list) and values, f"{trigger_group} must be a non-empty list"
    assert all(isinstance(value, str) and value for value in values), f"{trigger_group} entries must be non-empty strings"

serialized = json.dumps(evals, ensure_ascii=False).lower()
for forbidden in ("new dictionary", "new idiom", "словаря v2", "идиома из"):
    assert forbidden not in serialized, f"phrasebook-coupled expectation remains: {forbidden}"
PY

printf 'check-skill-contract: ok (%s bytes, %s lines, zero mandatory references)\n' \
  "$skill_bytes" "$skill_lines"
