#!/bin/sh
# Auditoria local, best-effort e explícita de performance, memória e crashes.
# Uso: scripts/performance-audit.sh [diretório-de-saída]
set -u

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
STAMP=$(date +%Y%m%d-%H%M%S)
OUT=${1:-${MURAL_PERFORMANCE_AUDIT_DIR:-/tmp/mural-performance-audit-$STAMP}}
mkdir -p "$OUT"
START_MARKER="$OUT/audit-start"
touch "$START_MARKER"
REPORT="$OUT/report.md"
STATUS="$OUT/status.tsv"
: > "$STATUS"
LAST_RUN_CODE=0

record() {
    name=$1
    result=$2
    printf '%s\t%s\n' "$name" "$result" >> "$STATUS"
}

run_logged() {
    name=$1
    shift
    log="$OUT/$name.log"
    printf '### %s\n\n' "$name" >> "$REPORT"
    printf '\$' >> "$REPORT"
    for arg in "$@"; do printf ' %s' "$arg" >> "$REPORT"; done
    printf '\n\n' >> "$REPORT"
    (cd "$ROOT" && "$@") >"$log" 2>&1
    code=$?
    LAST_RUN_CODE=$code
    if [ "$code" -eq 0 ]; then result=verified; else result=inconclusive; fi
    record "$name" "$result"
    printf '%s (exit %s; %s): [%s](%s)\n\n' "$name" "$code" "$result" "$(basename "$log")" "$log" >> "$REPORT"
    return 0
}

run_capture_process() {
    name=$1
    pid=$2
    shift 2
    log="$OUT/$name.log"
    ( "$@" "$pid" ) >"$log" 2>&1
    code=$?
    if [ "$code" -eq 0 ]; then result=verified; else result=inconclusive; fi
    record "$name" "$result"
    printf '%s (exit %s; %s): [%s](%s)\n\n' "$name" "$code" "$result" "$(basename "$log")" "$log" >> "$REPORT"
}

cat > "$REPORT" <<EOF
# Mural performance audit

- Started: $(date -u '+%Y-%m-%dT%H:%M:%SZ')
- Repository: $ROOT
- Artifact directory: $OUT
- Scenario: Release app, \`-manualTesting -performanceFixture\`
- Interpretation: \`verified\` means the command exited zero; \`inconclusive\` means the environment, permissions, or tool prevented a conclusion. A green build is not runtime evidence.

## Worktree snapshot

EOF
(cd "$ROOT" && git status --short --branch) > "$OUT/worktree-status.txt" 2>&1
record worktree-status verified
printf '[worktree-status.txt](%s)\n\n' "$OUT/worktree-status.txt" >> "$REPORT"
{
    printf 'Commit: '
    (cd "$ROOT" && git rev-parse HEAD)
    printf 'Architecture: '
    uname -m
    printf 'Hardware: '
    sysctl -n hw.model
    printf 'Memory bytes: '
    sysctl -n hw.memsize
    sw_vers
    xcrun xcodebuild -version
} > "$OUT/environment.txt" 2>&1
record environment verified
printf '[environment.txt](%s)\n\n' "$OUT/environment.txt" >> "$REPORT"

run_logged domain-tests swift test --package-path Packages/MuralKit

# Performance must be measured in Release without sanitizer overhead. Every lane gets its
# own DerivedData so a stale shared module cache cannot turn a dependency issue into a false
# source-code failure.
run_logged focused-release-tests \
    mobilebuildmcp --style minimal macos test \
    --scheme Mural --configuration Release \
    --derived-data-path "$OUT/DerivedData-Release-Tests" \
    --extra-args ENABLE_TESTABILITY=YES \
    '-only-testing:MuralTests/PerformanceBaselineTests' \
    '-only-testing:MuralTests/ThumbnailPerformanceTests'

# UI automation can be unavailable in a headless/TCC-limited session. Its result remains
# explicitly inconclusive while the build, log and generated XCTest metrics are preserved.
run_logged ui-test-idle-check scripts/check-tests-idle.sh ui
run_logged ui-performance-tests \
    mobilebuildmcp --style minimal macos test \
    --scheme Mural --configuration Release \
    --derived-data-path "$OUT/DerivedData-UI-Performance" \
    --extra-args ENABLE_TESTABILITY=YES \
    '-only-testing:MuralUITests/MuralUITests/testPerformanceFixtureScrollAndZoom'
UI_TEST_CODE=$LAST_RUN_CODE

# MobileBuildMCP reports the result bundle outside DerivedData. Preserve both the
# machine-readable XCTest data and a compact table that can be compared between runs.
UI_RESULT=$(grep -Eo '(~|/)[^[:space:]]+\.xcresult' "$OUT/ui-performance-tests.log" 2>/dev/null | tail -n 1 || true)
case "$UI_RESULT" in
    "~/"*) UI_RESULT="$HOME/${UI_RESULT#\~/}" ;;
esac
if [ -n "$UI_RESULT" ] && [ -d "$UI_RESULT" ]; then
    xcrun xcresulttool get test-results summary --path "$UI_RESULT" --compact \
        >"$OUT/ui-performance-summary.json" 2>"$OUT/ui-performance-summary-error.log"
    summary_code=$?
    xcrun xcresulttool get test-results metrics --path "$UI_RESULT" --compact \
        >"$OUT/ui-performance-metrics.json" 2>"$OUT/ui-performance-metrics-error.log"
    metrics_code=$?
    if [ "$UI_TEST_CODE" -eq 0 ] && [ "$summary_code" -eq 0 ] && [ "$metrics_code" -eq 0 ]; then
        metrics_result=verified
    else
        metrics_result=inconclusive
    fi
    record ui-performance-metrics "$metrics_result"
    printf 'UI xcresult (summary exit %s; metrics exit %s; %s): [summary JSON](%s); [metrics JSON](%s)\n\n' \
        "$summary_code" "$metrics_code" "$metrics_result" \
        "$OUT/ui-performance-summary.json" "$OUT/ui-performance-metrics.json" >> "$REPORT"

    if [ "$metrics_code" -eq 0 ] && command -v jq >/dev/null 2>&1; then
        {
            printf '#### UI performance measurements\n\n'
            printf 'Five Release iterations. Values are local to this Mac and this exact fixture.\n\n'
            printf '| Metric | Average | Minimum | Maximum | Unit |\n'
            printf '| --- | ---: | ---: | ---: | --- |\n'
            jq -r '
                def rounded: (. * 100 | round) / 100;
                .[] | .testRuns[] | .metrics[] | . as $metric |
                ($metric.measurements | add / length | rounded) as $average |
                ($metric.measurements | min | rounded) as $minimum |
                ($metric.measurements | max | rounded) as $maximum |
                "| \($metric.displayName) | \($average) | \($minimum) | \($maximum) | \($metric.unitOfMeasurement) |"
            ' "$OUT/ui-performance-metrics.json"
            printf '\n'
        } > "$OUT/ui-performance-metrics.md"
        cat "$OUT/ui-performance-metrics.md" >> "$REPORT"
    fi
else
    record ui-performance-metrics inconclusive
    printf 'The UI result bundle was not found in the test log; process metrics are inconclusive.\n\n' >> "$REPORT"
fi

# Sanitizers deliberately exercise functional suites rather than performance baselines:
# their instrumentation changes CPU, memory and time enough to invalidate benchmark values.
run_logged address-sanitizer \
    mobilebuildmcp --style minimal macos test \
    --scheme Mural --configuration Debug \
    --derived-data-path "$OUT/DerivedData-ASan" \
    --extra-args ENABLE_TESTABILITY=YES -enableAddressSanitizer YES \
    '-only-testing:MuralTests/BoardModelTests' \
    '-only-testing:MuralTests/AppLaunchTests'
run_logged thread-sanitizer \
    mobilebuildmcp --style minimal macos test \
    --scheme Mural --configuration Debug \
    --derived-data-path "$OUT/DerivedData-TSan" \
    --extra-args ENABLE_TESTABILITY=YES -enableThreadSanitizer YES \
    '-only-testing:MuralTests/AppLaunchTests' \
    '-only-testing:MuralTests/MuralMetricKitProbeTests' \
    '-only-testing:MuralTests/CloudSyncControllerTests'

run_logged release-build \
    mobilebuildmcp --style minimal macos build \
    --scheme Mural --configuration Release \
    --derived-data-path "$OUT/DerivedData-Release-App"
APP="$OUT/DerivedData-Release-App/Build/Products/Release/Mural.app"
if [ -d "$APP" ]; then
    record release-app verified
    printf 'Release app: [Mural.app](%s) (verified)\n\n' "$APP" >> "$REPORT"
else
    record release-app inconclusive
    printf 'Release app was not produced (inconclusive).\n\n' >> "$REPORT"
fi

PID=""
if [ -d "$APP" ]; then
    open -n "$APP" --args -manualTesting -performanceFixture -disableOnDeviceModel >"$OUT/launch.log" 2>&1
    sleep 5
    PID=$(pgrep -n -f "$APP/Contents/MacOS/Mural" 2>/dev/null || true)
fi

cat >> "$REPORT" <<EOF
## Runtime profiling

EOF
if [ -n "$PID" ]; then
    printf 'Attached process PID: `%s`\n\n' "$PID" >> "$REPORT"
    for instrument in "Time Profiler" Allocations Leaks; do
        slug=$(printf '%s' "$instrument" | tr '[:upper:] ' '[:lower:]-')
        trace="$OUT/$slug.trace"
        log="$OUT/$slug-record.log"
        xcrun xctrace record --instrument "$instrument" --attach "$PID" --time-limit 15s --no-prompt --output "$trace" >"$log" 2>&1
        code=$?
        if [ "$code" -eq 0 ] && [ -e "$trace" ]; then result=verified; else result=inconclusive; fi
        record "xctrace-$slug" "$result"
        printf '%s (exit %s; %s): [%s](%s); trace: [%s](%s)\n\n' "$instrument" "$code" "$result" "$(basename "$log")" "$log" "$(basename "$trace")" "$trace" >> "$REPORT"
        if [ -e "$trace" ]; then
            xcrun xctrace toc --input "$trace" >"$OUT/$slug-toc.txt" 2>&1 || true
        fi
        if [ "$instrument" = "Time Profiler" ] && [ -e "$trace" ]; then
            track="Mural ($PID)"
            xcrun xctrace show --input "$trace" --track "$track" \
                --summary 'Summary: CPU Usage' >"$OUT/time-profiler-cpu-summary.txt" 2>&1
            summary_code=$?
            if [ "$summary_code" -eq 0 ]; then summary_result=verified; else summary_result=inconclusive; fi
            record time-profiler-cpu-summary "$summary_result"
            printf 'Time Profiler CPU summary (exit %s; %s): [time-profiler-cpu-summary.txt](%s)\n\n' \
                "$summary_code" "$summary_result" "$OUT/time-profiler-cpu-summary.txt" >> "$REPORT"

            xcrun xctrace show --input "$trace" --track "$track" --calltree Profile \
                --format markdown --function invert-calltree --hide-node-ids \
                --hide-heaviest-stack >"$OUT/time-profiler-calltree.md" 2>&1
            calltree_code=$?
            if [ "$calltree_code" -eq 0 ]; then calltree_result=verified; else calltree_result=inconclusive; fi
            record time-profiler-calltree "$calltree_result"
            printf 'Time Profiler call tree (exit %s; %s): [time-profiler-calltree.md](%s)\n\n' \
                "$calltree_code" "$calltree_result" "$OUT/time-profiler-calltree.md" >> "$REPORT"
        fi
    done
    run_capture_process leaks "$PID" leaks
    run_capture_process heap "$PID" heap
    run_capture_process vmmap "$PID" vmmap -summary
    log show --last 10m --style compact --predicate 'process == "Mural"' >"$OUT/mural-log-show.txt" 2>&1
    code=$?
    if [ "$code" -eq 0 ]; then result=verified; else result=inconclusive; fi
    record unified-log "$result"
    printf 'Unified log capture (exit %s; %s): [mural-log-show.txt](%s)\n\n' "$code" "$result" "$OUT/mural-log-show.txt" >> "$REPORT"
    cat >> "$REPORT" <<EOF
### Runtime observations

These are direct excerpts from the process diagnostics; they are not normalized benchmarks:

EOF
    grep -E 'Physical footprint|leaks for|All zones: [0-9]+ nodes|Writable regions:' "$OUT/leaks.log" "$OUT/heap.log" "$OUT/vmmap.log" >> "$REPORT" 2>/dev/null || true
    if [ -s "$OUT/time-profiler-cpu-summary.txt" ]; then
        printf '\nTime Profiler CPU summary:\n\n' >> "$REPORT"
        cat "$OUT/time-profiler-cpu-summary.txt" >> "$REPORT"
    fi
    printf '\n' >> "$REPORT"
    kill "$PID" 2>/dev/null || true
else
    record runtime-profile inconclusive
    printf 'The Release fixture app did not yield a process PID; Time Profiler, Allocations, Leaks, heap, vmmap and runtime logs are inconclusive.\n\n' >> "$REPORT"
fi

find "$HOME/Library/Logs/DiagnosticReports" -maxdepth 1 -type f -name 'Mural*' -newer "$START_MARKER" -print >"$OUT/recent-crash-reports.txt" 2>/dev/null || true
record crash-report-scan verified
printf 'Recent DiagnosticReports listing: [recent-crash-reports.txt](%s). An empty file means no matching report was found after audit start.\n\n' "$OUT/recent-crash-reports.txt" >> "$REPORT"

cat >> "$REPORT" <<EOF
## Result matrix

| Step | Result |
| --- | --- |
EOF
while IFS='	' read -r name result; do
    printf '| %s | %s |\n' "$name" "$result" >> "$REPORT"
done < "$STATUS"

cat >> "$REPORT" <<EOF

## Limitations

- This run is local and best-effort. TCC, an existing Instruments package lock, no usable app process, or unavailable devices can make runtime steps inconclusive.
- The structural fixture creates deterministic board data but does not represent real binary media, network, or iCloud. The UI lane measures a fixed scroll/zoom interaction only when UI automation is available.
- xctrace traces are evidence of the captured process only; they do not establish production p50/p95, App Store behavior, MetricKit delivery, or absence of crashes.
- Sanitizer commands run separate functional suites because sanitizer overhead invalidates performance numbers. Their exit status is recorded; a skipped or failed build is not silently treated as clean.
- Power Profiler is not part of this macOS audit: Apple's current Power Profiler workflow targets physical iPhone and iPad devices. macOS evidence comes from XCTest process metrics, Time Profiler, Energy gauge observations and distribution telemetry.
EOF
printf 'Report: %s\n' "$REPORT"
exit 0
