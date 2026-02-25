#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  bench.sh  –  Time the Objective-C Python interpreter vs. native Python 3
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT="tests/benchmark.py"
OC_BIN="./pyinterp"
RUNS=3

# ── Colours ──────────────────────────────────────────────────────────────────
BOLD='\033[1m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RESET='\033[0m'

header() { printf "\n${BOLD}${CYAN}╔══════════════════════════════════════════════════╗${RESET}\n"
           printf   "${BOLD}${CYAN}║  %-48s║${RESET}\n" "$1"
           printf   "${BOLD}${CYAN}╚══════════════════════════════════════════════════╝${RESET}\n"; }

separator() { printf "${CYAN}────────────────────────────────────────────────────${RESET}\n"; }

# ── Check binaries ────────────────────────────────────────────────────────────
if [[ ! -x "$OC_BIN" ]]; then
    printf "${YELLOW}⚠  $OC_BIN not found. Building first…${RESET}\n"
    make || { printf "\nBuild failed.\n"; exit 1; }
fi

PYTHON3=$(command -v python3 || command -v python)
if [[ -z "$PYTHON3" ]]; then
    printf "${YELLOW}⚠  python3 not found in PATH.${RESET}\n"
    exit 1
fi

# ── Helper: run N times, print each, return best (seconds, 3 decimals) ────────
time_runs() {
    local label="$1"; local cmd="$2"; shift 2
    local best=99999 total=0
    printf "  ${BOLD}%s${RESET}\n" "$label"
    for run in $(seq 1 $RUNS); do
        local t_start t_end elapsed
        t_start=$(date +%s%N 2>/dev/null || gdate +%s%N 2>/dev/null || python3 -c "import time;print(int(time.time()*1e9))")
        eval "$cmd" > /dev/null 2>&1
        local exit_code=$?
        t_end=$(date +%s%N 2>/dev/null || gdate +%s%N 2>/dev/null || python3 -c "import time;print(int(time.time()*1e9))")
        if [[ $exit_code -ne 0 ]]; then
            printf "    Run %d: ${YELLOW}FAILED (exit %d)${RESET}\n" "$run" "$exit_code"
            continue
        fi
        elapsed=$(( (t_end - t_start) ))
        local secs=$(echo "$elapsed" | awk '{printf "%.3f", $1/1000000000}')
        printf "    Run %d: %s s\n" "$run" "$secs"
        # Track best
        local ms=$(( elapsed / 1000000 ))
        if (( ms < best )); then best=$ms; fi
        total=$(( total + ms ))
    done
    local avg=$(( total / RUNS ))
    printf "  ${GREEN}  Best: %s ms   Avg: %s ms${RESET}\n\n" "$best" "$avg"
    # Export for comparison
    export LAST_BEST_MS=$best
    export LAST_AVG_MS=$avg
}

# ── Sanity-check: show outputs ────────────────────────────────────────────────
header "Output correctness check"
printf "\n  ${BOLD}→ ObjC interpreter output:${RESET}\n"
$OC_BIN "$SCRIPT" 2>&1 | sed 's/^/    /'
printf "\n  ${BOLD}→ Python 3 output:${RESET}\n"
$PYTHON3 "$SCRIPT" 2>&1 | sed 's/^/    /'

# ── Timing ───────────────────────────────────────────────────────────────────
header "Timing benchmark ($RUNS runs each)"
printf "\n  Script: ${BOLD}%s${RESET}\n\n" "$SCRIPT"
separator

time_runs "ObjC Python Interpreter" "$OC_BIN $SCRIPT"
OC_BEST=$LAST_BEST_MS
OC_AVG=$LAST_AVG_MS

time_runs "CPython ($PYTHON3)" "$PYTHON3 $SCRIPT"
PY_BEST=$LAST_BEST_MS
PY_AVG=$LAST_AVG_MS

# ── Summary ───────────────────────────────────────────────────────────────────
header "Results Summary"
printf "\n"
printf "  %-32s %8s ms   %8s ms\n" "" "Best" "Avg"
separator
printf "  %-32s %8s ms   %8s ms\n" "ObjC Interpreter" "$OC_BEST" "$OC_AVG"
printf "  %-32s %8s ms   %8s ms\n" "CPython" "$PY_BEST" "$PY_AVG"
separator

if (( PY_BEST > 0 && OC_BEST > 0 )); then
    ratio=$(awk "BEGIN {printf \"%.1f\", $OC_BEST / $PY_BEST}")
    if (( OC_BEST <= PY_BEST )); then
        printf "\n  ${GREEN}${BOLD}✨  ObjC interpreter is %.1fx FASTER than CPython!${RESET}\n" "$(awk "BEGIN {printf \"%.1f\", $PY_BEST/$OC_BEST}")"
    else
        printf "\n  ${YELLOW}${BOLD}📊  CPython is %.1fx faster than the ObjC interpreter${RESET}\n" "$ratio"
        printf "  ${YELLOW}     (Expected — CPython has decades of optimisation!)${RESET}\n"
    fi
fi

printf "\n  ${CYAN}Note: The ObjC interpreter is a tree-walking interpreter built from${RESET}\n"
printf "  ${CYAN}scratch. CPython uses bytecode compilation + a highly tuned VM.${RESET}\n\n"
