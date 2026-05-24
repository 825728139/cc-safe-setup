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

## 触发弹窗的完整命令清单

### destructive-guard（12 个拦截点）

| # | 命令示例 | 触发条件 | 放行例外 |
|---|---------|---------|---------|
| 1 | `rm -rf /` `rm -rf /home` `rm -rf ~` `rm -rf ..` | rm 目标为 `/` `/home` `/etc` `/usr` `/var` `/mnt` `~` `..` | 目标是 `node_modules` `dist` `build` `.cache` `__pycache__` `coverage` `.next` `.nuxt` `tmp` 时放行 |
| 2 | `rm --no-preserve-root` | 带 `--no-preserve-root` 参数 | — |
| 3 | `git reset --hard` | 管道开头或 `;` `&&` `\|\|` 后的 `git reset --hard` | — |
| 4 | `git clean -fd` `git clean -fdx` | 管道开头或 `;` `&&` `\|\|` 后的 `git clean` | — |
| 5 | `chmod -R 777 /` `chmod 777 ~` | chmod 777 作用于 `/` `~` `.` 等广域路径 | — |
| 6 | `find / -delete` `find ~ -exec rm` | find 作用于 `/` `~` `..` 并带 `-delete` | — |
| 7 | `sudo rm -rf` `sudo chmod 777` `sudo dd if=` `sudo mkfs` | sudo 搭配危险命令 | — |
| 8 | `Remove-Item -Recurse -Force` `del /s /q` `rd /s /q` | PowerShell/Windows 递归强制删除 | — |
| 9 | `git checkout --force` `git switch --discard-changes` | git 强制切换丢弃更改 | — |
| 10 | `bash -c 'rm -rf /...'` | 危险命令包裹在 `sh -c` / `bash -c` / `zsh -c` 中 | — |
| 11 | `echo 'rm -rf /' \| bash` | 危险命令通过管道传给 shell | — |
| 12 | `rm -rf` 目标含 NFS/Docker/bind 挂载点 | 检测到目标路径下有子挂载（需 findmnt） | — |

### bulk-file-delete-guard（2 个拦截点）

| # | 命令示例 | 触发条件 | 阈值 |
|---|---------|---------|------|
| 1 | `rm -rf dir/` `find . -delete` `find . -exec rm` `Remove-Item -Recurse` | 递归删除且目标目录文件数 > 10 | `THRESHOLD=10` |
| 2 | `git clean -fd` | 未跟踪文件数 > 10 | `THRESHOLD=10` |

### scope-guard（4 个拦截点）

| # | 命令示例 | 触发条件 |
|---|---------|---------|
| 1 | `rm -rf /absolute/path` | rm 带绝对路径（项目目录外） |
| 2 | `rm -rf ~/something` | rm 目标为 home 目录 |
| 3 | `rm -rf ../parent` | rm 逃逸到上级目录 |
| 4 | `rm` / `del` / `Remove-Item` 操作 Desktop/Documents/Downloads/.aws/.ssh | 目标为知名用户/系统目录 |

### block-database-wipe（8 个拦截点）

| # | 命令示例 | 框架 |
|---|---------|------|
| 1 | `artisan migrate:fresh` `artisan migrate:reset` `artisan db:wipe` `artisan db:seed --force` | Laravel |
| 2 | `artisan --env=xxx`（.env.xxx 不存在时） | Laravel |
| 3 | `manage.py flush` `manage.py sqlflush` | Django |
| 4 | `rake db:drop` `rake db:reset` `rails db:drop` `rails db:reset` | Rails |
| 5 | `DROP DATABASE` `DROP TABLE` `DROP SCHEMA` `TRUNCATE TABLE` `DELETE FROM xxx WHERE 1=1` | Raw SQL |
| 6 | `doctrine:fixtures:load`（无 --append）`doctrine:schema:drop` `doctrine:database:drop` | Symfony/Doctrine |
| 7 | `prisma migrate reset` `prisma db push --force-reset` | Prisma |
| 8 | `dropdb` | PostgreSQL CLI |

### windows-destructive-command-guard（5 个拦截点）

| # | 命令示例 | 触发条件 |
|---|---------|---------|
| 1 | `rd /s /q` `rmdir /s /q` | 递归静默删除目录 |
| 2 | `cmd /c "rd ..."` / `cmd /c "del ..."` | 通过 cmd /c 跳转执行删除 |
| 3 | `Remove-Item -Recurse -Force` | PowerShell 递归强制删除 |
| 4 | `del /s /q` `erase /s /q` | 递归静默删除文件 |
| 5 | `Format-Volume` `Clear-Disk` `Remove-Partition` | 磁盘级破坏性操作 |

### 直接拦截（exit 2，不弹窗）

**branch-guard：**
- `git push --force` / `git push -f` / `git push --force-with-lease`（任何分支）
- `git push origin main` / `git push origin master`（受保护分支，默认 `main:master`，可通过 `CC_PROTECT_BRANCHES` 配置）

**secret-guard：**
- `git add .env` / `git add .env.local` / `git add .env.production`
- `git add` 包含 `*.pem` / `*.key` / `*.p12` / `*.pfx` / `id_rsa` / `id_ed25519` / `credentials`
- `git add .` 或 `git add -A`（当前目录存在 .env 文件时）

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

## 踩坑记录（重要）

### 1. jq 是硬依赖，缺失时 hook 静默放行

所有 hook 脚本用 `jq` 从 stdin JSON 中提取命令。**jq 没装时，脚本无法解析 JSON，`COMMAND` 为空，直接 `exit 0` 放行一切命令**——没有任何报错，弹窗也不会出现。

```bash
# Linux 安装
sudo apt install jq

# Windows / Git Bash — 下载二进制
curl -L -o ~/bin/jq.exe https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-windows-amd64.exe
chmod +x ~/bin/jq.exe
```

**验证方法**：运行 `which jq`，必须有输出。如果 hook 没弹窗，第一个排查项就是 jq。

### 2. Hook 系统拦截的是 Bash 命令本身，不是脚本参数

Claude Code 的 hook 系统会把你执行的 Bash 命令转成 JSON 传给 hook 脚本。所以当你在终端手动测试时：

```bash
# ❌ 这样做会被 hook 系统拦截——它把整条管道命令当成要检查的内容
echo '{"tool_input":{"command":"rm -rf /test"}}' | bash destructive-guard.sh

# ✅ 正确测试方式：用 Python 子进程或写入临时文件
python3 -c "
import subprocess, json
inp = json.dumps({'tool_name':'Bash','tool_input':{'command':'rm -rf /home/test'}})
result = subprocess.run(['bash','destructive-guard.sh'], input=inp.encode(), capture_output=True)
print('EXIT:', result.returncode)
"
```

### 3. 全局 hook vs 项目 hook

Claude Code 有两个 hook 安装位置：
- **全局**：`~/.claude/hooks/` + `~/.claude/settings.json` — 所有项目生效
- **项目**：`.claude/hooks/` + `.claude/settings.json` — 仅当前项目生效

`npx cc-safe-setup` 默认安装到全局。用 `CLAUDE_PROJECT_DIR` 可指定项目目录：

```bash
CLAUDE_PROJECT_DIR=/path/to/project npx cc-safe-setup
```

**注意**：如果全局和项目都装了同名 hook，两边都会执行。改了其中一个的 IP 不影响另一个。

### 4. 环境变量通过管道传递的问题

在 Git Bash 中，管道命令里的内联环境变量可能不传递到子进程：

```bash
# ❌ IP 变量可能不生效
echo '...' | CC_REMOTE_CONFIRM_HOST=127.0.0.1 bash hook.sh

# ✅ 先 export 再执行
export CC_REMOTE_CONFIRM_HOST=127.0.0.1
echo '...' | bash hook.sh
```

### 5. Windows Git Bash 的 grep -P 警告

`destructive-guard.sh` 用 `grep -oP` 提取目标路径，在 Git Bash 中会产生警告：

```
grep: -P supports only unibyte and UTF-8 locales
```

**不影响功能**——提取失败时 TARGET_PATH 为空，脚本仍会继续执行拦截逻辑。如需消除警告，可设置：

```bash
export LC_ALL=C.UTF-8
```

### 6. 切换网络环境时批量修改 IP

脚本里的默认 IP 硬编码在每个 hook 文件中。切换网络（如家里 192.168.21.22 → 公司 192.168.100.x）时：

```bash
# 一键替换所有 hook 的默认 IP
sed -i 's/192\.168\.21\.22/192.168.100.x/g' ~/.claude/hooks/*.sh
```

或者统一用环境变量管理（推荐），这样只需改 export 不用改文件：

```bash
export CC_REMOTE_CONFIRM_HOST="192.168.100.x"
export CC_REMOTE_NOTIFY_HOST="192.168.100.x"
```
