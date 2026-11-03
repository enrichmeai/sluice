#!/usr/bin/env bash
# validators/test.sh: prove every validator red, then green.
# For each check: fixtures/<check>/red must exit 1 and fixtures/<check>/green must exit 0.
# A check that exits 2 on both is reported NOT RUN, which is not a pass.
# Exit: 0 all checks pass both fixtures; 1 any mismatch; 2 no mismatch but something not run.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
checks=(dbt_lint dbt_parse dag_import container dbt_sandbox)

mismatch=0; notrun=0
for c in "${checks[@]}"; do
  for want in red green; do
    fx="$here/fixtures/$c/$want"
    if [ ! -d "$fx" ]; then
      printf '%-12s %-6s MISSING fixture %s\n' "$c" "$want" "$fx"; mismatch=1; continue
    fi
    out="$("$here/$c.sh" "$fx" 2>&1)"; code=$?
    case "$want:$code" in
      red:1)   printf '%-12s %-6s ok   (fails as it should)\n' "$c" "$want" ;;
      green:0) printf '%-12s %-6s ok   (passes)\n' "$c" "$want" ;;
      *:2)     printf '%-12s %-6s NOT RUN: %s\n' "$c" "$want" "$(printf '%s\n' "$out" | grep -m1 SLUICE_RESULT | sed 's/^SLUICE_RESULT=not_run //')"; notrun=1 ;;
      *)       printf '%-12s %-6s MISMATCH: exit %s, wanted %s\n%s\n' "$c" "$want" "$code" "$([ "$want" = red ] && echo 1 || echo 0)" "$out"; mismatch=1 ;;
    esac
  done
done

if [ "$mismatch" = 1 ]; then echo "RESULT: FAIL"; exit 1; fi
if [ "$notrun" = 1 ]; then echo "RESULT: NOT RUN for at least one check (not a pass)"; exit 2; fi
echo "RESULT: PASS"; exit 0
