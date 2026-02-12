#!/bin/bash

# Configuration
HOST="http://openqaworker15.qe.prg3.suse.org"

# Variables with defaults (can be overridden by environment)
BRANCH=${BRANCH:-testapi_stress}
LO_TEST_TYPE=${LO_TEST_TYPE:-stress}
LO_OUTPUT_SIZE=${LO_OUTPUT_SIZE:-1024}
LO_OUTPUT_SCALE=${LO_OUTPUT_SCALE:-10000}
LO_OUTPUT_LOOPS=${LO_OUTPUT_LOOPS:-10}
LO_OUTPUT_SLEEP=${LO_OUTPUT_SLEEP:-10}
LO_REPRO_SIZE=${LO_REPRO_SIZE:-10485760} # 10MB
LO_COLLECT_TERM_INFO=${LO_COLLECT_TERM_INFO:-1}

# Check for Job ID argument
JOB_ID=$1

if [[ -z "$JOB_ID" ]]; then
    #echo "--- Preparing Git ---"
    #git add tests/longouput.pm
    #git commit --amend --no-edit
    #git push --force-with-lease origin "$BRANCH"

    echo "--- Triggering openQA Job ($LO_TEST_TYPE mode) ---"
    RESPONSE=$(openqa-cli api --host "$HOST" -X POST isos \
        DISTRI=sle \
        VERSION=15-SP6 \
        FLAVOR=HanaSrDev-Azure-Byos \
        ARCH=x86_64 \
        YAML_SCHEDULE=schedule/longoutput.yaml \
        CASEDIR="https://github.com/mpagot/os-autoinst-distri-opensuse.git#$BRANCH" \
        LO_TEST_TYPE="$LO_TEST_TYPE" \
        LO_OUTPUT_SIZE="$LO_OUTPUT_SIZE" \
        LO_OUTPUT_SCALE="$LO_OUTPUT_SCALE" \
        LO_OUTPUT_LOOPS="$LO_OUTPUT_LOOPS" \
        LO_OUTPUT_SLEEP="$LO_OUTPUT_SLEEP" \
        LO_REPRO_SIZE="$LO_REPRO_SIZE" \
        LO_COLLECT_TERM_INFO="$LO_COLLECT_TERM_INFO")
    echo "Response: $RESPONSE"

    # Extract job ID
    JOB_ID=$(echo "$RESPONSE" | jq -r '.ids[0]')

    if [[ -z "$JOB_ID" || "$JOB_ID" == "null" ]]; then
        echo "Failed to trigger job or parse job ID."
        exit 1
    fi
    echo "Waiting 5 seconds before monitoring..."
    sleep 5
else
    echo "Using provided Job ID: $JOB_ID (skipping git/trigger)"
fi

echo "Target Job ID: $JOB_ID"
echo "URL: $HOST/t$JOB_ID"

# Loop waiting for completion
echo "--- Monitoring Job Status ---"
while true; do
    STATUS_JSON=$(curl -s "$HOST/api/v1/experimental/jobs/$JOB_ID/status")
    STATE=$(echo "$STATUS_JSON" | jq -r '.state')
    RESULT=$(echo "$STATUS_JSON" | jq -r '.result')
    
    # \033[K clears the line from the cursor to the end
    echo -ne "\rCurrent State: $STATE, Result: $RESULT\033[K"
    
    # Exit loop if state is not scheduled, assigned, or running
    if [[ "$STATE" != "scheduled" && "$STATE" != "assigned" && "$STATE" != "running" ]]; then
        echo -e "\nJob finished!"
        echo "Final Result: $RESULT"
        break
    fi
    sleep 10
done

echo "--- Downloading autoinst-log.txt ---"
LOG_URL="$HOST/tests/$JOB_ID/file/autoinst-log.txt"
if curl -s -f -o autoinst-log.txt "$LOG_URL"; then
    echo "Log downloaded successfully to autoinst-log.txt"
else
    echo "Failed to download log from $LOG_URL"
fi
