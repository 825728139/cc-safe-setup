#!/bin/bash
# permission-confirm.sh — Route permission requests to Windows popup
#
# TRIGGER: PermissionRequest
# MATCHER: ""
#
# When Claude Code asks "Allow this action? (y/n)", this hook
# intercepts and sends the request to Windows for confirmation.

INPUT=$(cat)

# ---- HTTP 远程弹窗确认 ----
REMOTE_CONFIRM_HOST="${CC_REMOTE_CONFIRM_HOST:-192.168.21.22}"
REMOTE_CONFIRM_PORT="${CC_REMOTE_CONFIRM_PORT:-9800}"
REMOTE_CONFIRM_TIMEOUT="${CC_REMOTE_CONFIRM_TIMEOUT:-200}"
REMOTE_CONFIRM_ENABLED="${CC_REMOTE_CONFIRM_ENABLED:-1}"

if [ "$REMOTE_CONFIRM_ENABLED" != "1" ]; then
    exit 0
fi

# Extract tool info
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
TOOL_INPUT=$(printf '%s' "$INPUT" | jq -r '.tool_input // empty' 2>/dev/null)

# Build description for popup
DESCRIPTION="Tool: ${TOOL_NAME}"
if [ -n "$TOOL_INPUT" ]; then
    # Extract command or file_path for display
    COMMAND=$(printf '%s' "$TOOL_INPUT" | jq -r '.command // .file_path // empty' 2>/dev/null)
    if [ -n "$COMMAND" ]; then
        # Truncate long commands
        if [ ${#COMMAND} -gt 200 ]; then
            COMMAND="${COMMAND:0:200}..."
        fi
        DESCRIPTION="${DESCRIPTION}\nCommand: ${COMMAND}"
    fi
fi

# Send to Windows popup
escaped_desc=$(printf '%s' "$DESCRIPTION" | jq -Rs . 2>/dev/null)
if [ -z "$escaped_desc" ]; then
    escaped_desc="\"${DESCRIPTION}\""
fi

response=$(curl -s --max-time "$REMOTE_CONFIRM_TIMEOUT" \
    -X POST "http://${REMOTE_CONFIRM_HOST}:${REMOTE_CONFIRM_PORT}/confirm" \
    -H "Content-Type: application/json" \
    -d "{\"command\": ${escaped_desc}, \"type\": \"permission\"}" \
    2>/dev/null)

if [ -z "$response" ]; then
    # Service unreachable — let Claude Code handle normally (show prompt)
    exit 0
fi

exit_code=$(printf '%s' "$response" | jq -r '.exit // -1' 2>/dev/null)

if [ "$exit_code" = "0" ]; then
    # User approved — auto-allow
    jq -n '{
        hookSpecificOutput: {
            hookEventName: "PermissionRequest",
            decision: {
                behavior: "allow"
            }
        }
    }'
    exit 0
else
    # User denied — exit 2 to block (same as clicking No in Claude)
    echo "BLOCKED: 用户在 Windows 弹窗中拒绝了此操作。" >&2
    exit 2
fi
