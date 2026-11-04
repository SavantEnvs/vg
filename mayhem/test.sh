#!/usr/bin/env bash
#
# mayhem/test.sh — runs vg's built-in Catch suites and golden-output checks on the vg binary that
# mayhem/build.sh left in build-tests/vg (built with vg's normal flags). It never compiles.
# Emits a CTRF summary (file + `CTRF {...}` stdout marker); exit 0 iff nothing failed.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SRC:=/mayhem}"
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

VG="$SRC/build-tests/vg"
[ -x "$VG" ] || { echo "missing $VG — mayhem/build.sh must build it" >&2; emit_ctrf "vg" 0 1 0; exit 1; }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
GFA="$SRC/mayhem/test/bubble.gfa"
passed=0; failed=0

# Catch suites: each must print its own "All tests passed (N assertions in M test cases)" summary,
# so a neutered binary (no output) fails.
for tag in gfa path alignment zipcode vg handle snarls; do
  out="$("$VG" test "[$tag]" 2>&1)"
  if grep -Eq '^All tests passed \([0-9]+ assertions in [0-9]+ test cases\)' <<<"$out"; then
    passed=$((passed+1))
  else
    failed=$((failed+1)); echo "FAIL: vg test [$tag]" >&2; tail -5 <<<"$out" >&2
  fi
done

# Golden-output checks on a known graph: a bubble 1 -> {2,3} -> 4 with path x through 1,2,4.
check() {  # check <name> <expected> <actual>
  if [ "$2" == "$3" ]; then passed=$((passed+1)); else
    failed=$((failed+1)); echo "FAIL: $1" >&2; echo "--- expected" >&2; echo "$2" >&2; echo "--- actual" >&2; echo "$3" >&2
  fi
}

STATS=$'nodes\t4\nedges\t4\nlength\t12'
check "stats" "$STATS" "$("$VG" stats -zl "$GFA" 2>/dev/null)"

ROUNDTRIP=$'H\tVN:Z:1.1\nS\t1\tGATTA\nS\t2\tC\nS\t3\tG\nS\t4\tTTAGA\nL\t1\t+\t3\t+\t0M\nL\t1\t+\t2\t+\t0M\nL\t2\t+\t4\t+\t0M\nL\t3\t+\t4\t+\t0M\nP\tx\t1+,2+,4+\t*'
check "gfa roundtrip" "$ROUNDTRIP" "$("$VG" convert -g "$GFA" -f 2>/dev/null)"

check "paths list" "x" "$("$VG" paths -x "$GFA" -L 2>/dev/null)"

SUBGRAPH=$'H\tVN:Z:1.1\nS\t1\tGATTA\nS\t2\tC\nS\t4\tTTAGA\nL\t1\t+\t2\t+\t0M\nL\t2\t+\t4\t+\t0M\nP\tx\t1+,2+,4+\t*'
check "subgraph around node 2" "$SUBGRAPH" "$("$VG" find -x "$GFA" -n 2 -c 1 2>/dev/null)"

"$VG" convert -g "$GFA" -x > "$WORK/bubble.xg" 2>/dev/null
check "xg stats" "$STATS" "$("$VG" stats -zl "$WORK/bubble.xg" 2>/dev/null)"

emit_ctrf "vg" "$passed" "$failed" 0
