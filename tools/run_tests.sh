#!/usr/bin/env bash
# Runs every tests/*_regression.gd with a time limit and prints a summary table.
#
#   tools/run_tests.sh [timeout-seconds] [name-filter]
#
# GODOT         Godot binary (default: godot).
# GODOT_RUNNER  Command to use instead, called as: <runner> <timeout> <godot args>.
#               Parallel workers set it to their run_godot.sh wrapper.
# TEST_LOG_DIR  Where each test's output goes (default: work/test_logs).
#
# A test that fails inside _init never quits, so a timeout usually means a failed assert: the reason column shows it.
# Exit code 0 proves nothing in Godot, so the output is searched as well. Exits 1 unless every test passed.
set -u
cd "$(dirname "$0")/.." || exit 2

limit=${1:-300}
filter=${2:-}
logs=${TEST_LOG_DIR:-work/test_logs}
mkdir -p "$logs"
error_lines='SCRIPT ERROR|Parse Error|Failed to load script'

run_one() {
	if [ -n "${GODOT_RUNNER:-}" ]; then
		$GODOT_RUNNER "$limit" --headless --path . --script "$1"
	elif command -v timeout > /dev/null; then
		timeout "$limit" "${GODOT:-godot}" --headless --path . --script "$1"
	else
		perl -e 'alarm shift; exec @ARGV' "$limit" "${GODOT:-godot}" --headless --path . --script "$1"
	fi
}

summary=$(mktemp)
passed=0
failed=0
timed_out=0
for test in tests/*"$filter"*_regression.gd; do
	name=$(basename "$test" .gd)
	start=$SECONDS
	run_one "$test" > "$logs/$name.log" 2>&1
	code=$?
	took=$((SECONDS - start))
	reason=$(grep -m1 -E "$error_lines" "$logs/$name.log" | cut -c1-100)
	if [ "$code" -eq 124 ] || [ "$code" -eq 142 ]; then
		result=TIMEOUT
		timed_out=$((timed_out + 1))
	elif [ "$code" -ne 0 ] || [ -n "$reason" ]; then
		result=FAIL
		failed=$((failed + 1))
		[ -n "$reason" ] || reason=$(grep -m1 'ERROR' "$logs/$name.log" | cut -c1-100)
		[ -n "$reason" ] || reason="exit code $code"
	else
		result=PASS
		passed=$((passed + 1))
	fi
	printf '%-8s %5ss  %s\n' "$result" "$took" "$name"
	printf '%-8s %5ss  %-48s %s\n' "$result" "$took" "$name" "$reason" >> "$summary"
done

echo
sort "$summary"
echo
echo "$passed passed, $failed failed, $timed_out timed out. Logs: $logs"
rm -f "$summary"
[ "$failed" -eq 0 ] && [ "$timed_out" -eq 0 ]
