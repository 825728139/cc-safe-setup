#!/bin/bash
# ================================================================
# skill-description-drop-detector.sh — Detect silent SKILL.md
# description drops above cumulative-size threshold
# ================================================================
# PURPOSE:
#   Issue #59921 documents Claude Code v2.1.143 silently dropping
#   the `description:` field from individual SKILL.md entries in
#   the available-skills section of the system prompt when the
#   cumulative size of all skill descriptions exceeds an internal
#   threshold. The skill name stays in the list, but the description
#   is replaced with nothing — silently degrading auto-trigger
#   precision for the affected skills.
#
#   The reporter verified the drop is cumulative: editing one
#   SKILL.md to add ~800 chars caused a different skill's
#   description to silently disappear.
#
#   Operators have no way to detect this from outside the session.
#   The skill appears installed; the model just stops triggering
#   it correctly.
#
# DETECTION:
#   At SessionStart, count the SKILL.md files in the user's
#   ~/.claude/skills/ and any plugin SKILL.md directories. Compute
#   the cumulative size of `description:` fields. If the total
#   exceeds a threshold (default 50000 chars, matching reporter's
#   ~153 skill threshold), emit a warning to operator surfaces.
#
# TRIGGER: SessionStart
# MATCHER: (none)
#
# OUTPUT:
#   When threshold exceeded: a system-reminder via
#   hookSpecificOutput.additionalContext warning the model that
#   some skill descriptions may have been silently dropped and
#   advising it to verify auto-trigger behavior.
#
# CONFIGURATION:
#   CC_SKILL_DESC_THRESHOLD     — total description size threshold
#                                 in chars (default: 50000).
#   CC_SKILL_DESC_DIRS          — colon-separated list of directories
#                                 to scan. Default scans
#                                 ~/.claude/skills/ plus any
#                                 directory in ~/.claude/plugins/
#                                 containing a SKILL.md.
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/59921
# ================================================================

set -u

THRESHOLD="${CC_SKILL_DESC_THRESHOLD:-50000}"

# Discover skill directories. Default scans:
# 1. ~/.claude/skills/*/SKILL.md
# 2. ~/.claude/plugins/*/SKILL.md (plugin-shipped skills)
if [ -n "${CC_SKILL_DESC_DIRS:-}" ]; then
    IFS=':' read -ra SKILL_DIRS <<< "$CC_SKILL_DESC_DIRS"
else
    SKILL_DIRS=()
    [ -d "$HOME/.claude/skills" ] && SKILL_DIRS+=("$HOME/.claude/skills")
    [ -d "$HOME/.claude/plugins" ] && SKILL_DIRS+=("$HOME/.claude/plugins")
fi

[ ${#SKILL_DIRS[@]} -eq 0 ] && exit 0

# Find every SKILL.md across the directories.
SKILL_FILES=()
for dir in "${SKILL_DIRS[@]}"; do
    [ -d "$dir" ] || continue
    while IFS= read -r f; do
        SKILL_FILES+=("$f")
    done < <(find "$dir" -name "SKILL.md" -type f 2>/dev/null)
done

[ ${#SKILL_FILES[@]} -eq 0 ] && exit 0

SKILL_COUNT=${#SKILL_FILES[@]}
TOTAL_DESC_SIZE=0
SKILLS_WITH_DESC=0
SKILLS_WITHOUT_DESC=0

# For each SKILL.md, extract the description: field from YAML
# frontmatter and sum the lengths.
for f in "${SKILL_FILES[@]}"; do
    # Extract description: field. It can be a single-line or
    # folded-block. Single-line case is most common.
    desc=$(awk '
        /^---$/ { count++; next }
        count == 1 && /^description:/ {
            sub(/^description:[ \t]*/, "")
            sub(/^"/, ""); sub(/"$/, "")
            sub(/^'\''/, ""); sub(/'\''$/, "")
            print
            exit
        }
    ' "$f" 2>/dev/null)

    if [ -n "$desc" ]; then
        SKILLS_WITH_DESC=$((SKILLS_WITH_DESC + 1))
        len=${#desc}
        TOTAL_DESC_SIZE=$((TOTAL_DESC_SIZE + len))
    else
        SKILLS_WITHOUT_DESC=$((SKILLS_WITHOUT_DESC + 1))
    fi
done

# Below threshold. No warning.
if [ "$TOTAL_DESC_SIZE" -lt "$THRESHOLD" ]; then
    exit 0
fi

# Above threshold. Emit a warning via hookSpecificOutput.
WARNING="===== SKILL DESCRIPTION CUMULATIVE-SIZE WARNING =====
Found ${SKILL_COUNT} SKILL.md file(s) totaling ${TOTAL_DESC_SIZE} chars in
description fields (threshold: ${THRESHOLD}).

Per Issue #59921, Claude Code v2.1.143 silently drops the description: field
from individual skill entries in the available-skills section when the
cumulative description size exceeds an internal threshold. The skill name
stays visible; the description is replaced with nothing. Auto-trigger
precision degrades for affected skills, but the operator has no visible
signal that this is happening.

Recommended verification:
  1. Inspect the available-skills section of this session's system prompt.
  2. For each skill name without a description, read the corresponding
     SKILL.md file directly and confirm description: is well-formed.
  3. If well-formed descriptions are silently empty in the prompt, you are
     hitting the threshold. Mitigation: shorten descriptions of less-used
     skills, or split into smaller plugin groups.

Skills with description: ${SKILLS_WITH_DESC}
Skills without description: ${SKILLS_WITHOUT_DESC}
===== END WARNING ====="

jq -n \
    --arg ctx "$WARNING" \
    '{
        hookSpecificOutput: {
            hookEventName: "SessionStart",
            additionalContext: $ctx
        }
    }'

exit 0
