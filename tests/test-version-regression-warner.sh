#!/bin/bash
# Tests for version-regression-warner.sh
# Hook addresses issues #59918, #59921, #59942, #59042, #59047.
set -euo pipefail

HOOK="$(dirname "$0")/../examples/version-regression-warner.sh"
PASS=0
FAIL=0

# --- Test 1: disabled flag suppresses output ---
output=$(echo '{}' | CC_VERSION_WARNER_DISABLE=1 CC_VERSION_WARNER_VERSION=2.1.143 bash "$HOOK")
if [ -z "$output" ]; then
    echo "  PASS: disabled flag suppresses output"
    PASS=$((PASS + 1))
else
    echo "  FAIL: disabled flag should suppress output"
    FAIL=$((FAIL + 1))
fi

# --- Test 2: unknown version produces no warning ---
output=$(echo '{}' | CC_VERSION_WARNER_VERSION=99.99.99 bash "$HOOK")
if [ -z "$output" ]; then
    echo "  PASS: unknown version produces no warning"
    PASS=$((PASS + 1))
else
    echo "  FAIL: unknown version should produce no warning: $output"
    FAIL=$((FAIL + 1))
fi

# --- Test 3: v2.1.143 produces warning with all 3 issues ---
output=$(echo '{}' | CC_VERSION_WARNER_VERSION=2.1.143 bash "$HOOK")
if echo "$output" | grep -q "v2.1.143"; then
    echo "  PASS: v2.1.143 produces warning"
    PASS=$((PASS + 1))
else
    echo "  FAIL: v2.1.143 should produce warning"
    FAIL=$((FAIL + 1))
fi

ctx=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')
if echo "$ctx" | grep -q "Issue #59918"; then
    echo "  PASS: #59918 is mentioned"
    PASS=$((PASS + 1))
else
    echo "  FAIL: #59918 not mentioned"
    FAIL=$((FAIL + 1))
fi

if echo "$ctx" | grep -q "Issue #59921"; then
    echo "  PASS: #59921 is mentioned"
    PASS=$((PASS + 1))
else
    echo "  FAIL: #59921 not mentioned"
    FAIL=$((FAIL + 1))
fi

if echo "$ctx" | grep -q "Issue #59942"; then
    echo "  PASS: #59942 is mentioned"
    PASS=$((PASS + 1))
else
    echo "  FAIL: #59942 not mentioned"
    FAIL=$((FAIL + 1))
fi

# --- Test 4: mitigation is included for each issue ---
if echo "$ctx" | grep -q "Mitigation:"; then
    echo "  PASS: mitigation guidance is included"
    PASS=$((PASS + 1))
else
    echo "  FAIL: mitigation guidance not included"
    FAIL=$((FAIL + 1))
fi

# --- Test 5: JSON output is valid ---
if echo "$output" | jq -e '.hookSpecificOutput.additionalContext' > /dev/null 2>&1; then
    echo "  PASS: JSON output is valid"
    PASS=$((PASS + 1))
else
    echo "  FAIL: JSON output not valid"
    FAIL=$((FAIL + 1))
fi

# --- Test 6: hookEventName is SessionStart ---
event=$(echo "$output" | jq -r '.hookSpecificOutput.hookEventName // "MISSING"')
if [ "$event" = "SessionStart" ]; then
    echo "  PASS: hookEventName is SessionStart"
    PASS=$((PASS + 1))
else
    echo "  FAIL: hookEventName should be SessionStart, got: $event"
    FAIL=$((FAIL + 1))
fi

# --- Test 7: v2.1.141 produces separate warning ---
output_141=$(echo '{}' | CC_VERSION_WARNER_VERSION=2.1.141 bash "$HOOK")
if echo "$output_141" | grep -q "v2.1.141"; then
    echo "  PASS: v2.1.141 produces warning"
    PASS=$((PASS + 1))
else
    echo "  FAIL: v2.1.141 should produce warning"
    FAIL=$((FAIL + 1))
fi

ctx_141=$(echo "$output_141" | jq -r '.hookSpecificOutput.additionalContext')
if echo "$ctx_141" | grep -q "Issue #59042"; then
    echo "  PASS: v2.1.141 mentions #59042"
    PASS=$((PASS + 1))
else
    echo "  FAIL: v2.1.141 should mention #59042"
    FAIL=$((FAIL + 1))
fi

# --- Test 8: v2.1.138 (safe version) produces no warning ---
output=$(echo '{}' | CC_VERSION_WARNER_VERSION=2.1.138 bash "$HOOK")
if [ -z "$output" ]; then
    echo "  PASS: safe v2.1.138 produces no warning"
    PASS=$((PASS + 1))
else
    echo "  FAIL: safe version should produce no warning"
    FAIL=$((FAIL + 1))
fi

# --- Test 9: v2.1.143 and v2.1.141 produce DIFFERENT warnings ---
out_143=$(echo '{}' | CC_VERSION_WARNER_VERSION=2.1.143 bash "$HOOK")
out_141=$(echo '{}' | CC_VERSION_WARNER_VERSION=2.1.141 bash "$HOOK")
if [ "$out_143" != "$out_141" ]; then
    echo "  PASS: v2.1.143 and v2.1.141 produce different warnings"
    PASS=$((PASS + 1))
else
    echo "  FAIL: v2.1.143 and v2.1.141 should differ"
    FAIL=$((FAIL + 1))
fi

# --- Test 10: idempotent ---
out1=$(echo '{}' | CC_VERSION_WARNER_VERSION=2.1.143 bash "$HOOK")
out2=$(echo '{}' | CC_VERSION_WARNER_VERSION=2.1.143 bash "$HOOK")
if [ "$out1" = "$out2" ]; then
    echo "  PASS: hook is idempotent"
    PASS=$((PASS + 1))
else
    echo "  FAIL: hook not idempotent"
    FAIL=$((FAIL + 1))
fi

# --- Test 11: empty CC_VERSION_WARNER_VERSION falls through to claude detection ---
# We can't easily mock `claude --version` without altering PATH. We test that
# the hook does not produce output when CC_VERSION_WARNER_VERSION is set to an
# obviously-non-bad version. (Empty would cause the env to be unset by bash, so
# we set a benign version string instead.)
output=$(echo '{}' | CC_VERSION_WARNER_VERSION=0.0.0 bash "$HOOK")
if [ -z "$output" ]; then
    echo "  PASS: benign version produces no warning"
    PASS=$((PASS + 1))
else
    echo "  FAIL: benign version should produce no warning"
    FAIL=$((FAIL + 1))
fi

# --- Summary ---
echo ""
echo "=================================="
echo "Tests passed: $PASS"
echo "Tests failed: $FAIL"
echo "=================================="

[ "$FAIL" -eq 0 ]
