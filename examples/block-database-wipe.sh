#!/bin/bash
# block-database-wipe.sh — Block destructive database commands
#
# Prevents accidental database destruction from commands like:
#   - Laravel: migrate:fresh, migrate:reset, db:wipe
#   - Django: flush, sqlflush
#   - Rails: db:drop, db:reset
#   - Raw SQL: DROP DATABASE, TRUNCATE
#   - Symfony/Doctrine: fixtures:load (without --append), schema:drop, database:drop
#   - Prisma: migrate reset, db push --force-reset
#   - PostgreSQL: dropdb
#
# Born from GitHub Issues #37405, #37439, #34729, #37574
#
# Usage: Add to settings.json as a PreToolUse hook
#
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash",
#       "hooks": [{ "type": "command", "command": "~/.claude/hooks/block-database-wipe.sh" }]
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
    escaped_cmd=$(printf '%s' "$COMMAND" | jq -Rs . 2>/dev/null) || true
    if [ -z "$escaped_cmd" ]; then
        escaped_cmd='"'"$( printf '%s' "$COMMAND" | sed 's/\\/\\\\/g; s/"/\\"/g' )""'"
    fi
    local response
    response=$(curl -s --max-time "$REMOTE_CONFIRM_TIMEOUT" \
        -X POST "http://${REMOTE_CONFIRM_HOST}:${REMOTE_CONFIRM_PORT}/confirm" \
        -H "Content-Type: application/json" \
        -d "{\"command\": ${escaped_cmd}}" \
        2>/dev/null)
    if [ -z "$response" ]; then
        echo "BLOCKED: $reason — 弹窗服务不可达，默认拦截" >&2
        exit 2
    fi
    local exit_code
    exit_code=$(printf '%s' "$response" | jq -r '.exit // 2' 2>/dev/null)
    [ -z "$exit_code" ] && exit_code=2
    if [ "$exit_code" = "0" ]; then
        return 0
    else
        echo "BLOCKED: $reason — 用户拒绝" >&2
        exit 2
    fi
}
# ==== HTTP CONFIRM END ====
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[[ -z "$COMMAND" ]] && exit 0

# Laravel destructive commands
if echo "$COMMAND" | grep -qiE 'artisan\s+(migrate:fresh|migrate:reset|db:wipe|db:seed\s+--force)'; then
    echo "BLOCKED: Destructive Laravel database command" >&2
    echo "Command: $COMMAND" >&2
    _http_confirm "Destructive Laravel database command"
    exit 0
fi

# Laravel --env flag without corresponding .env file
if echo "$COMMAND" | grep -qE 'artisan.*--env='; then
    ENV_NAME=$(echo "$COMMAND" | grep -oP '(?<=--env=)\w+')
    if [ -n "$ENV_NAME" ] && [ ! -f ".env.$ENV_NAME" ]; then
        echo "BLOCKED: .env.$ENV_NAME does not exist. Command would fall back to .env (possibly production)" >&2
        _http_confirm ".env.$ENV_NAME does not exist. Command would fall back to .env (possibly production)"
        exit 0
    fi
fi

# Django destructive commands
if echo "$COMMAND" | grep -qiE 'manage\.py\s+(flush|sqlflush)'; then
    echo "BLOCKED: Destructive Django database command" >&2
    _http_confirm "Destructive Django database command"
    exit 0
fi

# Rails destructive commands
if echo "$COMMAND" | grep -qiE 'rake\s+db:(drop|reset)|rails\s+db:(drop|reset)'; then
    echo "BLOCKED: Destructive Rails database command" >&2
    _http_confirm "Destructive Rails database command"
    exit 0
fi

# Raw SQL destructive commands
if echo "$COMMAND" | grep -qiE 'DROP\s+(DATABASE|TABLE|SCHEMA)|TRUNCATE\s+TABLE|DELETE\s+FROM\s+\w+\s*(;|\s*$|WHERE\s+(1\s*=\s*1|true))'; then
    echo "BLOCKED: Destructive SQL command" >&2
    _http_confirm "Destructive SQL command"
    exit 0
fi

# Symfony/Doctrine destructive commands
if echo "$COMMAND" | grep -qiE 'doctrine:(fixtures:load|schema:drop|database:drop)' && ! echo "$COMMAND" | grep -qE '\-\-append'; then
    echo "BLOCKED: Destructive Doctrine command (use --append for fixtures:load)" >&2
    _http_confirm "Destructive Doctrine command (use --append for fixtures:load)"
    exit 0
fi

# Prisma destructive commands
if echo "$COMMAND" | grep -qiE 'prisma\s+migrate\s+reset|prisma\s+db\s+push\s+--force-reset'; then
    echo "BLOCKED: Destructive Prisma database command" >&2
    _http_confirm "Destructive Prisma database command"
    exit 0
fi

# PostgreSQL CLI
if echo "$COMMAND" | grep -qE '^\s*dropdb\s'; then
    echo "BLOCKED: dropdb command" >&2
    _http_confirm "dropdb command"
    exit 0
fi

exit 0
