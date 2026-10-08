#!/usr/bin/env python3
"""Sidebar chatbot backend: talks to Claude through the Claude Code CLI.

Uses the user's existing Claude Code login (`claude -p`), so no API key is
needed. Each chat session maps to one Claude Code session: the first message
starts it with --session-id, later messages --resume it, so Claude keeps the
full conversation context. history.json stays the display copy the widget
reads.
"""

import os
import sys
import json
import time
import uuid
import shutil
import subprocess
from pathlib import Path

CACHE_DIR = Path.home() / ".cache" / "quickshell" / "chatbot"
# Neutral working dir outside $HOME so Claude Code doesn't pick up any
# CLAUDE.md / project memory from the user's dotfiles repo.
WORK_DIR = Path(f"/tmp/quickshell-{os.environ.get('USER', 'user')}") / "claude-chat"
TIMEOUT_S = 300

SYSTEM_PROMPT = (
    "You are Claude, an AI assistant made by Anthropic, answering in a small "
    "chat panel in the sidebar of the user's Arch Linux + Hyprland desktop "
    "(ArchEclipse Quickshell). Be concise and direct. The panel renders basic "
    "markdown: headers, bullet and numbered lists, quotes, inline code, bold, "
    "italics and fenced code blocks; avoid tables and images. You have no "
    "tools in this panel, so you cannot read files or run commands; when the "
    "user needs something done on their system, give them the exact commands."
)


def create_message(role: str, content: str, response_time: int = 0) -> dict:
    """Create a message object with all required fields."""
    return {
        "id": str(uuid.uuid4()),
        "role": role,
        "content": content,
        "timestamp": int(time.time() * 1000),  # milliseconds
        "responseTime": response_time,
    }


def get_session_dir(model: str, session_id: str = "default") -> Path:
    return CACHE_DIR / model / "sessions" / session_id


def load_history(session_dir: Path) -> list:
    """Load conversation history from JSON file."""
    history_path = session_dir / "history.json"
    if history_path.exists():
        try:
            with open(history_path, "r") as f:
                return json.load(f)
        except (json.JSONDecodeError, IOError):
            # If file is corrupted or can't be read, start fresh
            return []
    return []


def save_history(session_dir: Path, history: list):
    """Save conversation history to JSON file."""
    session_dir.mkdir(parents=True, exist_ok=True)
    with open(session_dir / "history.json", "w") as f:
        json.dump(history, f, indent=2)


def claude_session(session_dir: Path, history: list) -> tuple[str, bool]:
    """Return (claude session id, resume?) for this chat session.

    An empty history (new or cleared chat) always starts a fresh Claude
    session so cleared context really is gone.
    """
    id_path = session_dir / "claude-session"
    if history and id_path.exists():
        sid = id_path.read_text().strip()
        if sid:
            return sid, True
    sid = str(uuid.uuid4())
    session_dir.mkdir(parents=True, exist_ok=True)
    id_path.write_text(sid)
    return sid, False


def main():
    if len(sys.argv) < 3:
        print("ERROR: Missing arguments", file=sys.stderr)
        print(
            "Usage: python chatbot.py <model> <message> [session_id]",
            file=sys.stderr,
        )
        print('Example: python chatbot.py opus "Hello world" session1', file=sys.stderr)
        sys.exit(1)

    model = sys.argv[1]
    user_message = sys.argv[2]
    session_id = sys.argv[3] if len(sys.argv) > 3 else "default"

    claude_bin = shutil.which("claude") or str(Path.home() / ".local" / "bin" / "claude")
    if not Path(claude_bin).exists():
        print("ERROR: Claude Code is not installed (claude not found)", file=sys.stderr)
        sys.exit(1)

    session_dir = get_session_dir(model, session_id)
    history = load_history(session_dir)
    claude_sid, resume = claude_session(session_dir, history)

    cmd = [
        claude_bin, "-p", user_message,
        "--model", model,
        "--output-format", "json",
        "--system-prompt", SYSTEM_PROMPT,
        # Plain chat: no tools, MCP servers, hooks/settings or skills.
        "--tools", "",
        "--strict-mcp-config",
        "--setting-sources", "",
        "--disable-slash-commands",
        "--resume" if resume else "--session-id", claude_sid,
    ]

    WORK_DIR.mkdir(parents=True, exist_ok=True)
    start_time = time.time()
    try:
        proc = subprocess.run(
            cmd, cwd=WORK_DIR, capture_output=True, text=True, timeout=TIMEOUT_S
        )
    except subprocess.TimeoutExpired:
        print(f"ERROR: Request timed out after {TIMEOUT_S} seconds", file=sys.stderr)
        sys.exit(1)
    response_time = int((time.time() - start_time) * 1000)  # milliseconds

    try:
        data = json.loads(proc.stdout)
    except json.JSONDecodeError:
        err = (proc.stderr or proc.stdout or "no output").strip()
        print(f"ERROR: {err}", file=sys.stderr)
        sys.exit(1)

    reply = str(data.get("result") or "").strip()
    if data.get("is_error") or proc.returncode != 0 or not reply:
        print(f"ERROR: {reply or data.get('subtype') or 'Claude returned no reply'}", file=sys.stderr)
        sys.exit(1)

    history.append(create_message("user", user_message))
    history.append(create_message("assistant", reply, response_time))
    save_history(session_dir, history)

    print(reply)


if __name__ == "__main__":
    main()
