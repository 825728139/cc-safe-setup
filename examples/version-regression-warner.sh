#!/bin/bash
# ================================================================
# version-regression-warner.sh — Surface known silent regressions
# for the currently-running Claude Code version on SessionStart
# ================================================================
# PURPOSE:
#   Some Claude Code minor versions ship documented or community-
#   reported silent regressions that operators cannot detect from
#   within a session. By the time an operator notices the regression,
#   they've often spent significant time on a workflow that was
#   broken at startup.
#
#   This hook checks the current `claude --version` against a small
#   table of known-bad versions and surfaces the relevant regression
#   set at SessionStart, with mitigation guidance per regression.
#
#   The table is small on purpose. The bar for inclusion is
#   "documented silent failure with no in-session error or warning"
#   — the operator's worst class of bug.
#
# TRIGGER: SessionStart
# MATCHER: (none)
#
# CURRENT KNOWN-BAD VERSIONS (2026-05-17):
#
#   v2.1.143:
#     - Issue #59918: --resume with -p containing full history
#       returns empty response. Mitigation: downgrade to v2.1.138,
#       or pass only the latest user message in -p on resume.
#     - Issue #59921: SKILL.md description fields silently dropped
#       above cumulative-size threshold. Mitigation: shorten
#       descriptions or split skills into smaller plugin groups.
#     - Issue #59942: OTel `query_source` attribute silently empty
#       since 2026-05-13 in both claude-code CLI and Cowork.
#       Mitigation: monitor per-attribute empty-rate metrics for
#       sudden jumps.
#
#   v2.1.141:
#     - Issue #59042: streaming-stall regression after v2.1.140 fix.
#     - Issue #59047: unhandled-case banner on every conversational
#       turn.
#
# CONFIGURATION:
#   CC_VERSION_WARNER_DISABLE — set to 1 to disable entirely
#   CC_VERSION_WARNER_VERSION — override detected version (testing)
#
# RELATED ISSUES:
#   https://github.com/anthropics/claude-code/issues/59918
#   https://github.com/anthropics/claude-code/issues/59921
#   https://github.com/anthropics/claude-code/issues/59942
#   https://github.com/anthropics/claude-code/issues/59042
#   https://github.com/anthropics/claude-code/issues/59047
# ================================================================

set -u

[ "${CC_VERSION_WARNER_DISABLE:-0}" = "1" ] && exit 0

# Detect the running Claude Code version. Allow override for tests.
if [ -n "${CC_VERSION_WARNER_VERSION:-}" ]; then
    VERSION="$CC_VERSION_WARNER_VERSION"
else
    if ! command -v claude >/dev/null 2>&1; then
        exit 0
    fi
    # `claude --version` typically outputs something like
    # "2.1.143 (Claude Code)" or "claude-code v2.1.143". We just
    # want the semver. Strip everything that is not [0-9.] and
    # take the first match.
    VERSION=$(claude --version 2>/dev/null \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' \
        | head -n 1)
fi

[ -z "$VERSION" ] && exit 0

# Build the warning text only if the version matches a known-bad
# version. Add new entries here as silent regressions are documented.
WARNING=""

case "$VERSION" in
    "2.1.143")
        WARNING="===== KNOWN SILENT REGRESSIONS IN v2.1.143 =====
You are running Claude Code v2.1.143, which has three documented
silent regressions that operators cannot detect from within a
session. Each is listed with its mitigation.

1. Issue #59918 — \`--resume\` with full \`-p\` history returns
   empty response. No error, just finish_reason:stop with empty
   delta. Mitigation: downgrade to v2.1.138, or pass only the
   latest user message in -p on resume (not full history).

2. Issue #59921 — SKILL.md description fields silently dropped
   from the available-skills system reminder when cumulative
   description size exceeds an internal threshold. Mitigation:
   if you have >100 skills, shorten descriptions or split into
   smaller plugin groups. Cross-check installed-vs-visible
   descriptions in your system prompt.

3. Issue #59942 — OTel \`query_source\` attribute silently empty
   on \`api_request\` events and \`cost.usage\` / \`token.usage\`
   counter metrics since 2026-05-13, in both claude-code CLI and
   Cowork. Same shape as the v2.1.122 \`cost_usd\` drop. If you
   rely on \`query_source\` for cost allocation, monitor your
   pipeline's per-attribute empty-rate.

These regressions do not surface in-session. If your workflow
touches resume + -p, large skill collections, or OTel-based cost
allocation, verify behavior before relying on it.
===== END WARNING ====="
        ;;
    "2.1.141")
        WARNING="===== KNOWN REGRESSIONS IN v2.1.141 =====
You are running Claude Code v2.1.141, shipped a few hours after
v2.1.140's documented silent-failure fixes. Two regressions of the
same shape surfaced immediately:

1. Issue #59042 — streaming-stall regression.

2. Issue #59047 — unhandled-case banner on every conversational
   turn.

Consider upgrading to a later patch version or pinning v2.1.138 if
this version's behavior blocks your workflow.
===== END WARNING ====="
        ;;
    *)
        # No known-bad regressions for this version.
        exit 0
        ;;
esac

[ -z "$WARNING" ] && exit 0

jq -n \
    --arg ctx "$WARNING" \
    '{
        hookSpecificOutput: {
            hookEventName: "SessionStart",
            additionalContext: $ctx
        }
    }'

exit 0
