#!/usr/bin/env python3
"""
Windows 弹窗服务 — 接收 Linux Claude Code hook 的 HTTP 请求，弹窗等待用户确认。

启动: python server.py
端口: 9800 (0.0.0.0)
依赖: pip install flask (tkinter Python 内置)

配套 hook:
  - destructive-guard (scripts.json) — 危险命令确认
  - api-error-alert (scripts.json) — 会话异常通知
  - notify-waiting.sh (examples/) — 等待输入通知
"""

import queue
import threading
import uuid
from flask import Flask, request, jsonify

# --- 请求队列 (Flask线程 -> tkinter主线程) ---
popup_queue = queue.Queue()

# --- 待处理请求 {req_id: {event, result}} ---
pending = {}
pending_lock = threading.Lock()

app = Flask(__name__)


@app.route("/confirm", methods=["POST"])
def confirm():
    """删除确认弹窗。返回 {"exit": 0} 放行, {"exit": 2} 拦截。"""
    data = request.get_json(silent=True) or {}
    command = data.get("command", "(unknown)")

    req_id = str(uuid.uuid4())
    done = threading.Event()
    result = {"exit": 2}  # 默认拦截

    with pending_lock:
        pending[req_id] = {"event": done, "result": result}

    # 放入队列，让 tkinter 主线程弹窗
    popup_queue.put({
        "id": req_id,
        "type": "confirm",
        "command": command,
    })

    # 阻塞等待用户操作（或超时 200s）
    done.wait(timeout=200)

    with pending_lock:
        entry = pending.pop(req_id, None)

    exit_code = entry["result"]["exit"] if entry else 2
    return jsonify(exit=exit_code)


@app.route("/notify", methods=["POST"])
def notify():
    """通知弹窗（单按钮）。返回 {"exit": 0}。"""
    data = request.get_json(silent=True) or {}
    message = data.get("message", "Claude waiting for input")

    req_id = str(uuid.uuid4())
    done = threading.Event()
    result = {"exit": 0}

    with pending_lock:
        pending[req_id] = {"event": done, "result": result}

    popup_queue.put({
        "id": req_id,
        "type": "notify",
        "message": message,
    })

    done.wait(timeout=205)

    with pending_lock:
        pending.pop(req_id, None)

    return jsonify(exit=0)


def run_flask():
    app.run(host="0.0.0.0", port=9800, debug=False, use_reloader=False)


# ============================================================
# tkinter 主循环
# ============================================================

import tkinter as tk
from tkinter import messagebox


def poll_queue(root):
    """每 100ms 检查队列，有请求就弹窗。"""
    try:
        req = popup_queue.get_nowait()
    except queue.Empty:
        root.after(100, lambda: poll_queue(root))
        return

    req_id = req["id"]
    req_type = req["type"]

    if req_type == "confirm":
        _show_confirm(root, req_id, req["command"])
    elif req_type == "notify":
        _show_notify(root, req_id, req["message"])
    else:
        _finish(req_id, 2)


def _finish(req_id, exit_code):
    """通知 Flask 线程弹窗结果。"""
    with pending_lock:
        entry = pending.get(req_id)
        if entry:
            entry["result"]["exit"] = exit_code
            entry["event"].set()


def _show_confirm(root, req_id, command):
    """弹确认框：是=放行(0), 否=拦截(2), 超时=拦截(2)。"""
    win = tk.Toplevel(root)
    win.title("Claude Code - Confirm Operation")
    win.attributes("-topmost", True)
    win.resizable(False, False)

    # 居中
    w, h = 520, 220
    sx = win.winfo_screenwidth()
    sy = win.winfo_screenheight()
    win.geometry(f"{w}x{h}+{(sx - w) // 2}+{(sy - h) // 2}")

    tk.Label(win, text="Claude wants to run:", font=("", 11)).pack(pady=(15, 5))

    # 命令文本，限制长度
    display = command if len(command) <= 120 else command[:120] + "..."
    cmd_var = tk.StringVar(value=display)
    entry = tk.Entry(win, textvariable=cmd_var, state="readonly", width=65, font=("Consolas", 10))
    entry.pack(pady=5, padx=15)

    tk.Label(win, text="Allow? (200s timeout = block)", fg="gray").pack(pady=(10, 5))

    btn_frame = tk.Frame(win)
    btn_frame.pack(pady=10)

    timed_out = {"v": False}

    def on_yes():
        if not timed_out["v"]:
            win.destroy()
            _finish(req_id, 0)

    def on_no():
        if not timed_out["v"]:
            win.destroy()
            _finish(req_id, 2)

    def on_timeout():
        timed_out["v"] = True
        win.destroy()
        _finish(req_id, 2)

    tk.Button(btn_frame, text="Allow (Yes)", width=12, command=on_yes).pack(side="left", padx=10)
    tk.Button(btn_frame, text="Block (No)", width=12, command=on_no).pack(side="left", padx=10)

    # 超时 200s
    win.after(200_000, on_timeout)

    # 关闭窗口按钮 = 拦截
    win.protocol("WM_DELETE_WINDOW", on_no)

    # 继续轮询队列
    root.after(100, lambda: poll_queue(root))


def _show_notify(root, req_id, message):
    """弹通知框（单按钮确定）。"""
    win = tk.Toplevel(root)
    win.title("Claude Code - Notification")
    win.attributes("-topmost", True)
    win.resizable(False, False)

    w, h = 420, 160
    sx = win.winfo_screenwidth()
    sy = win.winfo_screenheight()
    win.geometry(f"{w}x{h}+{(sx - w) // 2}+{(sy - h) // 2}")

    tk.Label(win, text=message, font=("", 12)).pack(pady=(25, 15))

    def on_ok():
        win.destroy()
        _finish(req_id, 0)

    tk.Button(win, text="OK", width=10, command=on_ok).pack()

    # 超时 205s 自动关闭
    win.after(205_000, on_ok)
    win.protocol("WM_DELETE_WINDOW", on_ok)

    root.after(100, lambda: poll_queue(root))


def main():
    # Flask 放后台线程
    flask_thread = threading.Thread(target=run_flask, daemon=True)
    flask_thread.start()

    # tkinter 主线程
    root = tk.Tk()
    root.withdraw()  # 隐藏主窗口，只显示弹窗

    # 开始轮询队列
    root.after(100, lambda: poll_queue(root))

    print("Hook server running on 0.0.0.0:9800")
    print("Endpoints: POST /confirm  POST /notify")
    root.mainloop()


if __name__ == "__main__":
    main()
