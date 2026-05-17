#!/bin/bash
# Tests for skill-description-drop-detector.sh
# Hook addresses issue #59921 (silent SKILL.md description drops).
set -euo pipefail

HOOK="$(dirname "$0")/../examples/skill-description-drop-detector.sh"
PASS=0
FAIL=0

TMP=$(mktemp -d /tmp/test-skill-drop.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# --- Test 1: empty skill dirs produce no output ---
mkdir -p "$TMP/empty"
output=$(echo '{}' | CC_SKILL_DESC_DIRS="$TMP/empty" bash "$HOOK")
if [ -z "$output" ]; then
    echo "  PASS: empty skill dir produces no output"
    PASS=$((PASS + 1))
else
    echo "  FAIL: empty dir should produce no output"
    FAIL=$((FAIL + 1))
fi

# --- Test 2: skills below threshold produce no output ---
mkdir -p "$TMP/small/skill1" "$TMP/small/skill2"
cat > "$TMP/small/skill1/SKILL.md" <<'EOF'
---
name: skill1
description: A short description.
---
EOF
cat > "$TMP/small/skill2/SKILL.md" <<'EOF'
---
name: skill2
description: Another short description.
---
EOF
output=$(echo '{}' | CC_SKILL_DESC_THRESHOLD=10000 CC_SKILL_DESC_DIRS="$TMP/small" bash "$HOOK")
if [ -z "$output" ]; then
    echo "  PASS: below threshold produces no output"
    PASS=$((PASS + 1))
else
    echo "  FAIL: below threshold should produce no output: $output"
    FAIL=$((FAIL + 1))
fi

# --- Test 3: skills above threshold produce JSON warning ---
mkdir -p "$TMP/large"
for i in $(seq 1 5); do
    mkdir -p "$TMP/large/skill$i"
    # Each skill has ~1000 char description to push total above threshold quickly
    long_desc=$(printf 'A skill that does %.0s' {1..50})
    cat > "$TMP/large/skill$i/SKILL.md" <<EOF
---
name: skill$i
description: $long_desc
---
EOF
done
output=$(echo '{}' | CC_SKILL_DESC_THRESHOLD=500 CC_SKILL_DESC_DIRS="$TMP/large" bash "$HOOK")
if echo "$output" | grep -q "SKILL DESCRIPTION CUMULATIVE-SIZE WARNING"; then
    echo "  PASS: above threshold emits warning"
    PASS=$((PASS + 1))
else
    echo "  FAIL: above threshold should emit warning: $output"
    FAIL=$((FAIL + 1))
fi

# --- Test 4: JSON output is valid ---
if echo "$output" | jq -e '.hookSpecificOutput.additionalContext' > /dev/null 2>&1; then
    echo "  PASS: output is valid JSON"
    PASS=$((PASS + 1))
else
    echo "  FAIL: output not valid JSON"
    FAIL=$((FAIL + 1))
fi

# --- Test 5: hookEventName is SessionStart ---
event=$(echo "$output" | jq -r '.hookSpecificOutput.hookEventName // "MISSING"')
if [ "$event" = "SessionStart" ]; then
    echo "  PASS: hookEventName is SessionStart"
    PASS=$((PASS + 1))
else
    echo "  FAIL: hookEventName should be SessionStart, got: $event"
    FAIL=$((FAIL + 1))
fi

# --- Test 6: skill count is reported ---
if echo "$output" | jq -r '.hookSpecificOutput.additionalContext' | grep -q "Found 5 SKILL.md"; then
    echo "  PASS: skill count is reported correctly (5)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: skill count not reported correctly"
    FAIL=$((FAIL + 1))
fi

# --- Test 7: non-existent dir handled gracefully ---
output=$(echo '{}' | CC_SKILL_DESC_DIRS="$TMP/does-not-exist" bash "$HOOK")
if [ -z "$output" ]; then
    echo "  PASS: non-existent dir handled gracefully"
    PASS=$((PASS + 1))
else
    echo "  FAIL: non-existent dir produced output: $output"
    FAIL=$((FAIL + 1))
fi

# --- Test 8: skill without description doesn't crash ---
mkdir -p "$TMP/no-desc/skill1"
cat > "$TMP/no-desc/skill1/SKILL.md" <<'EOF'
---
name: skill-without-description
---

This skill has no description field in frontmatter.
EOF
output=$(echo '{}' | CC_SKILL_DESC_THRESHOLD=10000 CC_SKILL_DESC_DIRS="$TMP/no-desc" bash "$HOOK")
if [ -z "$output" ]; then
    echo "  PASS: skill without description handled (below threshold)"
    PASS=$((PASS + 1))
else
    echo "  FAIL: skill without description should be below threshold"
    FAIL=$((FAIL + 1))
fi

# --- Test 9: skills_without_description is counted ---
mkdir -p "$TMP/mixed/with" "$TMP/mixed/without"
cat > "$TMP/mixed/with/SKILL.md" <<'EOF'
---
name: with-desc
description: This has a description.
---
EOF
cat > "$TMP/mixed/without/SKILL.md" <<'EOF'
---
name: no-desc
---
EOF
# Add a skill with long description to push total over threshold
mkdir -p "$TMP/mixed/big"
big_desc=$(printf 'X%.0s' {1..1500})
cat > "$TMP/mixed/big/SKILL.md" <<EOF
---
name: big
description: $big_desc
---
EOF
output=$(echo '{}' | CC_SKILL_DESC_THRESHOLD=500 CC_SKILL_DESC_DIRS="$TMP/mixed" bash "$HOOK")
if echo "$output" | jq -r '.hookSpecificOutput.additionalContext' | grep -q "Skills with description: 2"; then
    echo "  PASS: with-description count is 2"
    PASS=$((PASS + 1))
else
    echo "  FAIL: with-description count incorrect"
    FAIL=$((FAIL + 1))
fi

if echo "$output" | jq -r '.hookSpecificOutput.additionalContext' | grep -q "Skills without description: 1"; then
    echo "  PASS: without-description count is 1"
    PASS=$((PASS + 1))
else
    echo "  FAIL: without-description count incorrect"
    FAIL=$((FAIL + 1))
fi

# --- Test 10: quoted descriptions are stripped of quotes ---
mkdir -p "$TMP/quoted/skill"
cat > "$TMP/quoted/skill/SKILL.md" <<'EOF'
---
name: quoted
description: "A quoted description with quotes."
---
EOF
mkdir -p "$TMP/quoted/big"
big_desc=$(printf 'Y%.0s' {1..1500})
cat > "$TMP/quoted/big/SKILL.md" <<EOF
---
name: big
description: "$big_desc"
---
EOF
output=$(echo '{}' | CC_SKILL_DESC_THRESHOLD=500 CC_SKILL_DESC_DIRS="$TMP/quoted" bash "$HOOK")
if echo "$output" | jq -r '.hookSpecificOutput.additionalContext' | grep -q "Skills with description: 2"; then
    echo "  PASS: quoted descriptions counted"
    PASS=$((PASS + 1))
else
    echo "  FAIL: quoted descriptions not counted correctly"
    FAIL=$((FAIL + 1))
fi

# --- Test 11: idempotent ---
mkdir -p "$TMP/idem/skill"
desc=$(printf 'Z%.0s' {1..600})
cat > "$TMP/idem/skill/SKILL.md" <<EOF
---
name: idem
description: $desc
---
EOF
out1=$(echo '{}' | CC_SKILL_DESC_THRESHOLD=500 CC_SKILL_DESC_DIRS="$TMP/idem" bash "$HOOK")
out2=$(echo '{}' | CC_SKILL_DESC_THRESHOLD=500 CC_SKILL_DESC_DIRS="$TMP/idem" bash "$HOOK")
if [ "$out1" = "$out2" ]; then
    echo "  PASS: hook is idempotent"
    PASS=$((PASS + 1))
else
    echo "  FAIL: hook not idempotent"
    FAIL=$((FAIL + 1))
fi

# --- Test 12: multiple directories scanned ---
mkdir -p "$TMP/multi1/s1" "$TMP/multi2/s2"
cat > "$TMP/multi1/s1/SKILL.md" <<EOF
---
description: $(printf 'A%.0s' {1..400})
---
EOF
cat > "$TMP/multi2/s2/SKILL.md" <<EOF
---
description: $(printf 'B%.0s' {1..400})
---
EOF
output=$(echo '{}' | CC_SKILL_DESC_THRESHOLD=500 CC_SKILL_DESC_DIRS="$TMP/multi1:$TMP/multi2" bash "$HOOK")
if echo "$output" | jq -r '.hookSpecificOutput.additionalContext' | grep -q "Found 2 SKILL.md"; then
    echo "  PASS: multiple directories scanned"
    PASS=$((PASS + 1))
else
    echo "  FAIL: multiple directories not scanned correctly"
    FAIL=$((FAIL + 1))
fi

# --- Summary ---
echo ""
echo "=================================="
echo "Tests passed: $PASS"
echo "Tests failed: $FAIL"
echo "=================================="

[ "$FAIL" -eq 0 ]
