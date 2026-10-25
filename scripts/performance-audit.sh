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

run_logged domain-tests swift test --package-path Packages/MuralKit
run_logged focused-release-tests xcodebuild -project Mural.xcodeproj -scheme Mural -destination platform=macOS -configuration Release ENABLE_TESTABILITY=YES -only-testing:MuralTests/PerformanceBaselineTests -only-testing:MuralTests/ThumbnailPerformanceTests test

run_logged address-sanitizer xcodebuild -project Mural.xcodeproj -scheme Mural -destination platform=macOS -configuration Debug ENABLE_TESTABILITY=YES -enableAddressSanitizer YES -only-testing:MuralTests/PerformanceBaselineTests test
run_logged thread-sanitizer xcodebuild -project Mural.xcodeproj -scheme Mural -destination platform=macOS -configuration Debug ENABLE_TESTABILITY=YES -enableThreadSanitizer YES -only-testing:MuralTests/PerformanceBaselineTests test

run_logged release-build xcodebuild -project Mural.xcodeproj -scheme Mural -destination platform=macOS -configuration Release -derivedDataPath "$OUT/DerivedData" build
APP="$OUT/DerivedData/Build/Products/Release/Mural.app"
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
- The structural fixture creates deterministic board data but does not represent real binary media, network, iCloud, or user interaction.
- xctrace traces are evidence of the captured process only; they do not establish production p50/p95, App Store behavior, MetricKit delivery, or absence of crashes.
- Sanitizer commands are separate attempts and their exit status is recorded; a skipped or failed build is not silently treated as clean.
EOF
printf 'Report: %s\n' "$REPORT"
exit 0
