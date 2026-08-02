#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch_root="$(mktemp -d "${TMPDIR:-/tmp}/pohuy-contract-tests.XXXXXX")"
trap 'rm -rf "$scratch_root"' EXIT

fail() {
  printf 'test-skill-contract: %s\n' "$1" >&2
  exit 1
}

make_case_copy() {
  local case_name="$1"
  local case_dir="$scratch_root/$case_name"
  mkdir -p "$case_dir"
  rsync -a --exclude='.git' "$repo_root/" "$case_dir/"
  printf '%s\n' "$case_dir"
}

expect_contract_failure() {
  local case_dir="$1"
  local expected="$2"
  local output_file="$case_dir/contract-output.log"

  if "$case_dir/scripts/check-skill-contract.sh" >"$output_file" 2>&1; then
    fail "contract unexpectedly passed for $(basename "$case_dir")"
  fi
  grep -Fq "$expected" "$output_file" || {
    sed -n '1,120p' "$output_file" >&2
    fail "missing expected failure for $(basename "$case_dir"): $expected"
  }
  printf '  ok: %s -> %s\n' "$(basename "$case_dir")" "$expected"
}

for dependency in cmp git python3 rsync; do
  command -v "$dependency" >/dev/null 2>&1 || fail "$dependency is required"
done

"$repo_root/scripts/check-skill-contract.sh"

for reference_file in ontologia.md sceny.md slovar.md; do
  [[ -f "$repo_root/skills/pohuy/references/$reference_file" ]] || \
    fail "optional upstream reference is missing: $reference_file"
done
printf '  ok: optional upstream references are present\n'

type_case="$(make_case_copy eval-list-type)"
python3 - "$type_case/evals/evals.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    payload = json.load(handle)
payload["evals"] = {}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
expect_contract_failure "$type_case" "evals.evals must be a list of eval cases"

count_case="$(make_case_copy eval-case-count)"
python3 - "$count_case/evals/evals.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    payload = json.load(handle)
payload["evals"] = []
with open(path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
expect_contract_failure "$count_case" "evals.evals must contain at least 5 cases, found 0"

schema_case="$(make_case_copy eval-case-schema)"
python3 - "$schema_case/evals/evals.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    payload = json.load(handle)
del payload["evals"][0]["tone"]
with open(path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
expect_contract_failure "$schema_case" "eval case deploy-crash is missing fields: ['tone']"

case_type_case="$(make_case_copy eval-case-type)"
python3 - "$case_type_case/evals/evals.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    payload = json.load(handle)
payload["evals"][0] = "not-an-object"
with open(path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
expect_contract_failure "$case_type_case" "eval case at index 0 must be an object"

budget_metadata_case="$(make_case_copy context-budget-metadata)"
python3 - "$budget_metadata_case/evals/evals.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    payload = json.load(handle)
payload["context_budget"]["skill_md_max_lines"] = 81
with open(path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
expect_contract_failure "$budget_metadata_case" \
  "context_budget.skill_md_max_lines must be 80, found 81"

budget_case="$(make_case_copy context-budget)"
python3 - "$budget_case/skills/pohuy/SKILL.md" <<'PY'
import sys

with open(sys.argv[1], "a", encoding="utf-8") as handle:
    handle.write("x" * 3501)
PY
expect_contract_failure "$budget_case" "SKILL.md is"

ignore_case="$(make_case_copy task-local-ignore)"
python3 - "$ignore_case/.gitignore" <<'PY'
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    lines = handle.readlines()
with open(path, "w", encoding="utf-8") as handle:
    handle.writelines(line for line in lines if line.rstrip("\n") != ".temp/")
PY
expect_contract_failure "$ignore_case" ".gitignore must ignore task-local artifact: .temp/"

fake_infra="$scratch_root/fake-infra"
runtime_home="$scratch_root/runtime-home"
stub_bin="$scratch_root/bin"
mkdir -p "$fake_infra" "$runtime_home" "$stub_bin"
git -C "$fake_infra" init -q
git -C "$fake_infra" remote add origin \
  'https://github.com/relux-works/relux-agents-infra-evil.git'

printf '#!/usr/bin/env bash\nexit 0\n' >"$fake_infra/setup.sh"
chmod +x "$fake_infra/setup.sh"

if PATH="$stub_bin:$PATH" \
  POHUY_RUNTIME_HOME="$runtime_home" \
  RELUX_AGENTS_INFRA_DIR="$fake_infra" \
  "$repo_root/setup.sh" >"$scratch_root/evil-origin.log" 2>&1; then
  fail "lookalike infra origin was accepted"
fi
grep -Fq 'has an unexpected origin' "$scratch_root/evil-origin.log" || \
  fail "lookalike origin rejection was not descriptive"
[[ ! -e "$runtime_home/.agents/skills/pohuy" ]] || \
  fail "lookalike origin mutated the runtime before rejection"
printf '  ok: lookalike origin rejected before runtime mutation\n'

cat >"$stub_bin/agents-infra" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

runtime_home=""
while (( $# > 0 )); do
  if [[ "$1" == "--home-dir" ]]; then
    runtime_home="$2"
    shift 2
  else
    shift
  fi
done
[[ -n "$runtime_home" ]]
mkdir -p "$runtime_home/.claude/skills" "$runtime_home/.codex/skills"
ln -sfn "$runtime_home/.agents/skills/pohuy" "$runtime_home/.claude/skills/pohuy"
ln -sfn "$runtime_home/.agents/skills/pohuy" "$runtime_home/.codex/skills/pohuy"
STUB
chmod +x "$stub_bin/agents-infra"

git -C "$fake_infra" remote set-url origin \
  'https://github.com/relux-works/relux-agents-infra.git'
for run_number in 1 2; do
  PATH="$stub_bin:$PATH" \
    POHUY_RUNTIME_HOME="$runtime_home" \
    RELUX_AGENTS_INFRA_DIR="$fake_infra" \
    "$repo_root/setup.sh" >"$scratch_root/trusted-origin-$run_number.log" 2>&1
done

cmp -s "$repo_root/skills/pohuy/SKILL.md" \
  "$runtime_home/.agents/skills/pohuy/SKILL.md" || \
  fail "installed SKILL.md differs from source"
[[ "$(readlink "$runtime_home/.claude/skills/pohuy")" == \
   "$runtime_home/.agents/skills/pohuy" ]] || fail "Claude skill link is incorrect"
[[ "$(readlink "$runtime_home/.codex/skills/pohuy")" == \
   "$runtime_home/.agents/skills/pohuy" ]] || fail "Codex skill link is incorrect"
printf '  ok: exact trusted origin and idempotent Claude/Codex install\n'

printf 'test-skill-contract: ok (schema, budget, ignores, exact origin, idempotent install)\n'
