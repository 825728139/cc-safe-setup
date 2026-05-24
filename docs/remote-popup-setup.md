# 跨机弹窗确认方案 — Linux Claude Code → HTTP → Windows 弹窗

## 架构

```
Linux (Claude Code)                        Windows (弹窗服务)
  destructive-guard.sh ──curl POST──→      server.py (Flask :9800)
  scope-guard.sh      ──curl POST──→       → tkinter 弹窗
  block-database-wipe.sh ──curl POST──→    → 返回 exit code
  notify-waiting.sh   ──curl POST──→
  ...
```

## 改动清单

### scripts.json（内置 hook）

| Hook | 改动 |
|------|------|
| `destructive-guard` | 12 个拦截点前加 HTTP 弹窗确认 |
| `api-error-alert` | 加 HTTP 远程通知（会话异常时推送到 Windows） |

### examples/（可选 hook，需 --install-example 安装）

| Hook | 改动 |
|------|------|
| `notify-waiting.sh` | 加 HTTP 远程通知（Claude 等待输入时推送到 Windows） |
| `bulk-file-delete-guard.sh` | 2 个拦截点 → HTTP 弹窗确认 |
| `scope-guard.sh` | 4 个拦截点 → HTTP 弹窗确认 |
| `block-database-wipe.sh` | 8 个拦截点 → HTTP 弹窗确认 |
| `windows-destructive-command-guard.sh` | 1 个拦截点 → HTTP 弹窗确认 |

### 新增文件

| 文件 | 说明 |
|------|------|
| `windows-hook-server/server.py` | Flask + tkinter 弹窗服务 |

## 行为分类

### 走 HTTP 弹窗确认的（Windows 点"允许/拒绝"）

- `destructive-guard` — rm -rf / git reset --hard / chmod 777 / sudo + 危险命令 等
- `bulk-file-delete-guard` — 批量删除文件
- `scope-guard` — 操作项目目录外的文件
- `block-database-wipe` — DROP DATABASE / migrate:fresh 等数据库摧毁命令
- `windows-destructive-command-guard` — rd /s/q / Remove-Item -Recurse -Force

### 走 HTTP 通知的（Windows 弹"知道了"，不阻塞 Claude）

- `api-error-alert` — 会话因 rate limit / API 错误异常退出
- `notify-waiting` — Claude 等待用户输入

### 直接拦截不弹窗的

- `branch-guard` — force push / push to main
- `secret-guard` — git add .env / 密钥文件

### 自动放行的（减少弹窗干扰）

- `cd-git-allow` — cd && git log/diff/status 等只读复合命令
- `comment-strip` — 自动清理 bash 注释
- `syntax-check` — 编辑后语法检查（只警告不拦截）
- `context-monitor` — 上下文窗口监控（只警告不拦截）

## 配置（环境变量）

所有 hook 共用一套环境变量：

```bash
export CC_REMOTE_CONFIRM_HOST="192.168.21.22"      # Windows 内网 IP
export CC_REMOTE_CONFIRM_PORT="9800"                # Flask 端口
export CC_REMOTE_CONFIRM_TIMEOUT="200"              # 超时秒数（默认拦截）
export CC_REMOTE_CONFIRM_ENABLED="1"                # 1 启用 / 0 禁用

export CC_REMOTE_NOTIFY_HOST="192.168.21.22"        # 通知用同一个 IP
export CC_REMOTE_NOTIFY_PORT="9800"
export CC_REMOTE_NOTIFY_TIMEOUT="205"
export CC_REMOTE_NOTIFY_ENABLED="1"
```

切换到公司电脑时改 IP 为 `192.168.100.x`。

## 安装步骤

### Windows

```bash
pip install flask
python cc-safe-setup/windows-hook-server/server.py
# 看到 "Hook server running on 0.0.0.0:9800" 即启动成功
```

### Linux

```bash
# 0. 确保有 jq
which jq || sudo apt install jq

# 1. 设置环境变量（写到 ~/.bashrc 或 Claude Code env 配置）
export CC_REMOTE_CONFIRM_HOST="192.168.21.22"
export CC_REMOTE_NOTIFY_HOST="192.168.21.22"

# 2. 安装内置 hook（destructive-guard / branch-guard / secret-guard 等 8 个）
npx cc-safe-setup

# 3. 安装额外 hook
npx cc-safe-setup --install-example notify-waiting
npx cc-safe-setup --install-example bulk-file-delete-guard
npx cc-safe-setup --install-example scope-guard
npx cc-safe-setup --install-example block-database-wipe
npx cc-safe-setup --install-example windows-destructive-command-guard
```

### 测试

```bash
# 测试确认弹窗（Windows 应弹窗）
echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/test"}}' | ~/.claude/hooks/destructive-guard.sh

# 测试通知弹窗
echo '{"hook_event_name":"Notification"}' | ~/.claude/hooks/notify-waiting.sh
```

## 8 个内置 hook 说明

| Hook | 作用 |
|------|------|
| `destructive-guard` | 拦截 rm -rf / git reset --hard / chmod 777 / sudo + 危险命令 |
| `branch-guard` | 拦截 push to main/master + force push |
| `syntax-check` | 编辑后自动检查 .py/.sh/.json/.yaml/.js 语法（只警告） |
| `context-monitor` | token 消耗监控，4 级警告（40%→25%→20%→15%） |
| `comment-strip` | 去掉 bash 命令中的注释，修复权限匹配问题 |
| `cd-git-allow` | 自动放行 cd && git log/diff/status 等只读复合命令 |
| `secret-guard` | 拦截 git add .env / *.pem / *.key |
| `api-error-alert` | 会话异常退出时记录日志 + 发通知 |

## 其他推荐安装的 hook

| 类别 | Hook | 说明 |
|------|------|------|
| 安全 | `env-var-check` | 阻止 export 里硬编码 API key |
| 安全 | `bash-secret-output-detector` | 检测命令输出中是否包含密钥 |
| 安全 | `symlink-guard` | 检测 rm 目标是否经过 symlink/junction |
| 效率 | `auto-approve-build` | 自动放行 npm test / cargo build 等 |
| 效率 | `auto-approve-git-read` | 自动放行 git status/log/diff |
| 效率 | `auto-approve-test` | 自动放行测试命令 |
| 效率 | `compound-command-approver` | 自动放行 cd && git log 等复合命令 |
| 效率 | `bash-heuristic-approver` | 自动放行含 $() 反引号的安全命令 |
| 效率 | `auto-snapshot` | 编辑前自动保存文件快照（7 天自动清理） |
| Git | `test-before-push` | push 前检查是否跑过测试 |
| Git | `deploy-guard` | 有未提交更改时阻止部署 |
| 会话 | `large-read-guard` | 读大文件前警告 |
| 会话 | `read-before-edit` | 编辑没读过的文件时警告 |
| 会话 | `working-directory-fence` | 阻止操作 CWD 外的文件 |

这些 hook 不需要走 HTTP 弹窗（要么直接拦截，要么自动放行，要么只警告）。

## 注意事项

- 超时 200s 无操作 → 默认拦截（安全优先）
- Windows 弹窗服务不可达 → 默认拦截
- `CC_REMOTE_CONFIRM_ENABLED=0` 可禁用 HTTP 确认，恢复原生直接拦截行为
- `auto-snapshot` 每次编辑复制被修改的单个文件，7 天自动清理，不会持续膨胀磁盘
