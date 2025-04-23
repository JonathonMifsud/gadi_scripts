#!/bin/bash

# =============================================================================
# Wrapper Testing Script (JM2025)
# -----------------------------------------------------------------------------
# Iterates over all Singularity wrapper scripts and runs them with --help.
# Logs results to console and to a timestamped file.
# =============================================================================

# Config
BIN_DIR="/g/data/fo27/software/singularity/bin"
LOG_FILE="/g/data/fo27/software/singularity/test_wrapper_log_$(date +%Y%m%d_%H%M%S).txt"

# Results tracking
total=0
passed=0
failed=0
skipped=0

echo -e "🔍 Testing wrapper scripts in: $BIN_DIR"
echo -e "📄 Logging output to: $LOG_FILE"
echo "===================================================" | tee -a "$LOG_FILE"

# Iterate over wrapper scripts
for wrapper in "$BIN_DIR"/run_*.sh; do
    ((total++))
    wrapper_name=$(basename "$wrapper")
    software_name="${wrapper_name#run_}"
    software_name="${software_name%.sh}"

    echo -e "\n🧪 Testing: $wrapper_name" | tee -a "$LOG_FILE"
    echo "---------------------------------------------------" | tee -a "$LOG_FILE"

    if [[ ! -x "$wrapper" ]]; then
        echo "⚠️  Skipping $wrapper_name (not executable)" | tee -a "$LOG_FILE"
        ((skipped++))
        continue
    fi

    # Run with --help and capture output/errors
    output=$("$wrapper" --help 2>&1)
    exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        echo -e "✅ PASS: $wrapper_name ran successfully with --help" | tee -a "$LOG_FILE"
        echo "$output" >> "$LOG_FILE"
        ((passed++))
    else
        echo -e "❌ FAIL: $wrapper_name exited with code $exit_code" | tee -a "$LOG_FILE"
        echo "$output" | tee -a "$LOG_FILE"
        ((failed++))
    fi
done

# Summary
echo -e "\n===================================================" | tee -a "$LOG_FILE"
echo -e "✅ PASSED: $passed"       | tee -a "$LOG_FILE"
echo -e "❌ FAILED: $failed"       | tee -a "$LOG_FILE"
echo -e "⚠️  SKIPPED: $skipped"    | tee -a "$LOG_FILE"
echo -e "📊 TOTAL TESTED: $total" | tee -a "$LOG_FILE"
echo "===================================================" | tee -a "$LOG_FILE"

echo -e "\n🎉 Done. Detailed log saved to: $LOG_FILE"