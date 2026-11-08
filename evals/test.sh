#!/usr/bin/env bash
# evals/test.sh: prove check_cases.py red on the broken fixtures, then green on the real set.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="${SLUICE_PY:-python3}"

echo "== red: evals/fixtures/red (must exit 1)"
"$PY" -I "$here/check_cases.py" --cases-dir "$here/fixtures/red" --min-per-task 1; red=$?
echo "== green: evals/cases (must exit 0)"
"$PY" -I "$here/check_cases.py"; green=$?

if [ "$red" -ne 1 ]; then echo "RESULT: FAIL (red fixtures exited $red, wanted 1)"; exit 1; fi
if [ "$green" -ne 0 ]; then echo "RESULT: FAIL (real set exited $green, wanted 0)"; exit 1; fi
echo "RESULT: PASS"
