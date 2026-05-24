#!/bin/bash
# scope-guard.sh — Block file operations outside the project directory
#
# Solves: Claude Code deleting files on Desktop, in ~/Applications,
# or anywhere outside the working directory (#36233, #36339)
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/scope-guard.sh" }]
#     }]
#   }
# }
#
# TRIGGER: PreToolUse  MATCHER: "Bash"

INPUT=$(cat)
# ==== HTTP CONFIRM START ====
# ---- HTTP 远程弹窗确认（Linux → Windows） ----
REMOTE_CONFIRM_HOST="${CC_REMOTE_CONFIRM_HOST:-192.168.21.22}"
REMOTE_CONFIRM_PORT="${CC_REMOTE_CONFIRM_PORT:-9800}"
REMOTE_CONFIRM_TIMEOUT="${CC_REMOTE_CONFIRM_TIMEOUT:-200}"
REMOTE_CONFIRM_ENABLED="${CC_REMOTE_CONFIRM_ENABLED:-1}"

_http_confirm() {
    local reason="$1"
    if [ "$REMOTE_CONFIRM_ENABLED" != "1" ]; then
        echo "BLOCKED: $reason" >&2
        exit 2
    fi
    local escaped_cmd
    escaped_cmd=$(printf '%s' "$CMD" | jq -Rs . 2>/dev/null) || true
    if [ -z "$escaped_cmd" ]; then
        escaped_cmd='"'"$( printf '%s' "$CMD" | sed 's/\\/\\\\/g; s/"/\\"/g' )""'"
    fi
    local response
    response=$(curl -s --max-time "$REMOTE_CONFIRM_TIMEOUT" \
        -X POST "http://${REMOTE_CONFIRM_HOST}:${REMOTE_CONFIRM_PORT}/confirm" \
        -H "Content-Type: application/json" \
        -d "{\"command\": ${escaped_cmd}}" \
        2>/dev/null)
    if [ -z "$response" ]; then
        echo "BLOCKED: $reason — Windows 弹窗服务不可达 (curl 超时)，默认拦截。如需放行，请先在 Windows 启动弹窗服务: python server.py" >&2
        exit 2
    fi
    local exit_code
    exit_code=$(printf '%s' "$response" | jq -r '.exit // 2' 2>/dev/null)
    [ -z "$exit_code" ] && exit_code=2
    if [ "$exit_code" = "0" ]; then
        return 0
    else
        echo "BLOCKED: $reason — 用户在 Windows 弹窗中点击了「拒绝」。请停止此操作，告知用户操作已被拦截，询问用户是否要换一种方式。" >&2
        exit 2
    fi
}
# ==== HTTP CONFIRM END ====
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[[ "$TOOL" != "Bash" ]] && exit 0
[[ -z "$CMD" ]] && exit 0

# Skip string output commands
if echo "$CMD" | grep -qE '^\s*(echo|printf|cat\s*<<)'; then
    exit 0
fi

# Check for destructive commands with paths outside project
if echo "$CMD" | grep -qE '\brm\b.*(-[a-zA-Z]*[rf]|--(recursive|force))'; then
    # Block absolute paths
    if echo "$CMD" | grep -qE '\brm\b[^|;]*\s+/[a-zA-Z]'; then
        echo "BLOCKED: rm with absolute path" >&2
        echo "Command: $CMD" >&2
        _http_confirm "rm with absolute path"
        exit 0
    fi
    # Block home directory paths
    if echo "$CMD" | grep -qE '\brm\b[^|;]*\s+~/'; then
        echo "BLOCKED: rm targeting home directory" >&2
        _http_confirm "rm targeting home directory"
        exit 0
    fi
    # Block parent directory escapes
    if echo "$CMD" | grep -qE '\brm\b[^|;]*\s+\.\./'; then
        echo "BLOCKED: rm escaping project directory" >&2
        _http_confirm "rm escaping project directory"
        exit 0
    fi
fi

# Block targeting well-known user/system directories
if echo "$CMD" | grep -qiE '\b(rm|del|Remove-Item)\b.*(Desktop|Applications|Documents|Downloads|Library|Keychain|\.aws|\.ssh)'; then
    echo "BLOCKED: targeting system/user directory" >&2
    _http_confirm "targeting system/user directory"
    exit 0
fi

exit 0
