#!/bin/bash
# parse_openqa_stress_log.sh

STATS_MODE=0
LOG_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --stats)
            STATS_MODE=1
            shift
            ;;
        *)
            LOG_FILE=$1
            shift
            ;;
    esac
done

if [[ -z "$LOG_FILE" || ! -f "$LOG_FILE" ]]; then
    echo "Usage: $0 [--stats] <path_to_log_file>"
    exit 1
fi

if [[ $STATS_MODE -eq 1 ]]; then
    echo -e "Iter\tSize(MB)\tPhase\t\t\tLoops\t\tDur(s)\t\tRate(MB/s)\tStatus"
    echo -e "------------------------------------------------------------------------------------------------------------------------"
else
    echo -e "Timestamp\t\t\tPID\tLoops\tDur/Time\tEvent/Command"
    echo -e "------------------------------------------------------------------------------------------------------------------------"
fi


# AWK script acts as a state machine that processes log line-by-line. It switches behavior based on the -v stats variable
awk -v stats="$STATS_MODE" '
# Initialization (BEGIN block) runs once at the start. It defines ANSI color codes and initializes the "Global State":
#   - current_i / current_size: Keeps track of which iteration/data size the test is currently processing.
#   - current_phase: Remembers the last testapi function called (e.g., script_run_cat vs terminal_flood)
#     to be able to attribute backend metrics to the correct test action.
BEGIN {
    RED = "\033[31m"
    GREEN = "\033[32m"
    YELLOW = "\033[33m"
    BLUE = "\033[34m"
    BOLDRED = "\033[1;31m"
    RESET = "\033[0m"
    IN_BACKTRACE = 0
    
    current_i = "-"
    current_size = 0
    current_phase = "init"
}

# Context Tracking (State Updates):  These patterns update the state without printing anything immediately:
#   - Iteration Tracker: Matches the custom echo commands in longouput.pm. It uses match() and substr() to extract
#     the iteration ID and byte size into variables.
#   - Phase Tracker: Matches <<< testapi::... lines. When it sees a call to cat or head, it updates current_phase
#     so the script knows "the next backend match belongs to this command."
/<<< testapi::script_run\(cmd="echo .i:[0-9]+ size:[0-9]+/ {
    if (match($0, /i:([0-9]+) size:([0-9]+)/)) {
        t = substr($0, RSTART, RLENGTH)
        match(t, /i:[0-9]+/)
        current_i = substr(t, RSTART+2, RLENGTH-2)
        match(t, /size:[0-9]+/)
        current_size = substr(t, RSTART+5, RLENGTH-5)
    }
}

# Capture Phase information
/<<< testapi::script_run\(cmd="cat / { current_phase = "script_run_cat" }
/<<< testapi::script_output/ { current_phase = "script_output_cat" }
/<<< testapi::script_retry/ { current_phase = "script_retry_cat" }
/<<< testapi::script_run\(cmd="echo .STILL STANDING. / { current_phase = "guard_command" }
/<<< testapi::script_run\(cmd="head -c / { current_phase = "terminal_flood" }
/<<< testapi::record_info\(title="SUT Stats/ { current_phase = "sut_stats" }

# Backend Metrics Processing (Matched output from SUT)
# When the backend finds a string, it logs a line containing loop counts and duration:
#   - Extraction: It uses match() with regex /in ([0-9]+) loops/ and /& ([0-9.]+) seconds/ to reliably pull numbers
#     regardless of where they appear in the line.
#   - Load Analysis: It compares the loop count against thresholds (10k, 50k, 200k) to assign a status_label like [CRITICAL LOAD].
#   - Branching Output:
#       * Stats Mode: Prints a single row in a tab-separated table, calculating the MB/s rate if the phase involves a cat command.
#       * Normal Mode: Prints a detailed, color-coded line showing the exact time, PID, and the matched command.
/Matched output from SUT/ {
    loops = "0"
    duration = "0"
    if (match($0, /in ([0-9]+) loops/)) {
        loops = substr($0, RSTART + 3, RLENGTH - 9)
    }
    if (match($0, /& ([0-9.]+) seconds/)) {
        duration = substr($0, RSTART + 2, RLENGTH - 10)
    }
    match($0, /seconds: /)
    cmd = substr($0, RSTART + 9)
    status_label = ""
    if (loops + 0 > 200000) status_label = "[CRITICAL LOAD]"
    else if (loops + 0 > 50000) status_label = "[HEAVY LOAD]"
    else if (loops + 0 > 10000) status_label = "[HIGH LOAD]"

    if (stats) {
        size_mb = current_size / 1024 / 1024
        rate = "-"
        if (duration > 0.1 && size_mb > 0 && current_phase ~ /cat/) {
            rate = sprintf("%.2f", size_mb / duration)
        }
        color = (status_label != "") ? RED : ""
        printf "%s\t%-10.2f\t%-20s\t%-10s\t%-10s\t%-10s\t%s%s%s\n", current_i, size_mb, current_phase, loops, duration, rate, color, status_label, RESET
    } else {
        ts = substr($1, 2, length($1)-2);
        pid = substr($3, 6, length($3)-6);
        if (length(cmd) > 100) cmd = substr(cmd, 1, 97) "...";
        color = (status_label != "") ? BOLDRED : ""
        printf "%-30s\t%-6s\t%s\t%ss\t%sMATCH: %s %s%s\n", ts, pid, loops, duration, color, cmd, status_label, RESET;
    }
    next
}

# Standard formatting if not in stats mode (!stats block):
# This block is active only when --stats is not used. It convert the log into a timeline:
#   - Catches Set PIPE_SZ (infrastructure) and Ring buffer overflow (potential data loss).
#   - Formats <<< (calls) and >>> (results) with indentation.
#   - Parses record_info calls, extracting the title and handling multi-line output
#   - Errors & Backtraces: Uses an IN_BACKTRACE flag. When an "ERROR" or "Test died" line is found,
#     it switches state to capture all subsequent lines until it hits a new timestamp,
#     formatting them in yellow to stand out as a stack trace.
!stats {
    if ($0 ~ /Set PIPE_SZ/) {
        ts = substr($1, 2, length($1)-2);
        pid = substr($3, 6, length($3)-6);
        match($0, /Set PIPE_SZ .*/);
        printf "%-30s\t%-6s\t-\t-\t\t%sINFO: %s%s\n", ts, pid, BLUE, substr($0, RSTART), RESET
    }
    else if ($0 ~ /Ring buffer overflow/) {
        ts = substr($1, 2, length($1)-2);
        pid = substr($3, 6, length($3)-6);
        match($0, /Ring buffer overflow: .*/);
        printf "%-30s\t%-6s\t-\t-\t\t%sWARNING: %s%s\n", ts, pid, YELLOW, substr($0, RSTART), RESET
    }
    else if ($0 ~ /<<< testapi::record_info/) {
        ts = substr($1, 2, length($1)-2);
        pid = substr($3, 6, length($3)-6);
        title = "UNKNOWN";
        if (match($0, /title="([^"]*)"/)) title = substr($0, RSTART+7, RLENGTH-8);
        out_val = "";
        if (match($0, /output="([^"]*)"/)) {
            out_val = substr($0, RSTART+8, RLENGTH-9);
            gsub(/\\n/, "\n\t\t\t\t\t\t\t  ", out_val);
        }
        printf "%-30s\t%-6s\t-\t-\t\t%sINFO: [%s]%s %s\n", ts, pid, BLUE, title, RESET, out_val;
    }
    else if ($0 ~ /<<< /) {
        ts = substr($1, 2, length($1)-2);
        pid = substr($3, 6, length($3)-6);
        match($0, /<<< .*/);
        call = substr($0, RSTART + 4);
        if (length(call) > 120) call = substr(call, 1, 117) "...";
        printf "%-30s\t%-6s\t-\t-\t\tCALL: %s\n", ts, pid, call;
    }
    else if ($0 ~ />>> /) {
        ts = substr($1, 2, length($1)-2);
        pid = substr($3, 6, length($3)-6);
        match($0, />>> .*/);
        res = substr($0, RSTART + 4);
        color = (res ~ /fail/) ? RED : (res ~ /ok/ ? GREEN : "");
        printf "%-30s\t%-6s\t-\t-\t\t%sRESULT: %s%s\n", ts, pid, color, res, RESET;
    }
    else if ($0 ~ /Test died|timed out/) {
        ts = substr($1, 2, length($1)-2);
        pid = substr($3, 6, length($3)-6);
        match($0, /::: .*/);
        msg = (RSTART > 0) ? substr($0, RSTART + 4) : $0;
        sub(/^basetest::runtest: # /, "", msg);
        printf "%-30s\t%-6s\t-\t-\t\t%sERROR: %s%s\n", ts, pid, BOLDRED, msg, RESET;
        IN_BACKTRACE = 1;
    }
    else if (IN_BACKTRACE) {
        if ($0 ~ /^\[[0-9]{4}-/ || $0 ~ /^$/) {
            IN_BACKTRACE = 0;
        } else {
            gsub(/^\s+/, "", $0);
            printf "%-30s\t%-6s\t-\t-\t\t%s  at %s%s\n", "", "", YELLOW, $0, RESET;
        }
    }
}
' "$LOG_FILE"
