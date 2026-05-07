#!/usr/bin/env python3
"""Probe the installed Manifold MCP server through Claude Desktop's wrapper.

This is intentionally a local diagnostic harness, not a product dependency.
It exercises the same command shape Claude Desktop uses:

    /Applications/Claude.app/Contents/Helpers/disclaimer \
      ~/Library/Application Support/Manifold/bin/manifold-mcp --agent cowork

Run it as a normal GUI user. A restricted sandbox can deny launchd Mach
lookups before Manifold code has control, which produces false negatives for
the XPC-backed tool-call path.
"""

from __future__ import annotations

import json
import os
import queue
import subprocess
import sys
import threading
from pathlib import Path
from typing import Any


CLAUDE_WRAPPER = Path("/Applications/Claude.app/Contents/Helpers/disclaimer")
INSTALLED_MCP = Path.home() / "Library/Application Support/Manifold/bin/manifold-mcp"


class MCPProbe:
    def __init__(self) -> None:
        if not CLAUDE_WRAPPER.exists():
            raise RuntimeError(f"Claude wrapper not found at {CLAUDE_WRAPPER}")
        if not INSTALLED_MCP.exists():
            raise RuntimeError(f"Installed Manifold MCP binary not found at {INSTALLED_MCP}")

        self.proc = subprocess.Popen(
            [str(CLAUDE_WRAPPER), str(INSTALLED_MCP), "--agent", "cowork"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        if self.proc.stdin is None or self.proc.stdout is None or self.proc.stderr is None:
            raise RuntimeError("failed to open MCP stdio pipes")

        self._responses: queue.Queue[dict[str, Any] | Exception] = queue.Queue()
        self._stderr: list[str] = []
        threading.Thread(target=self._drain_stdout, daemon=True).start()
        threading.Thread(target=self._drain_stderr, daemon=True).start()

    def _drain_stdout(self) -> None:
        assert self.proc.stdout is not None
        for line in self.proc.stdout:
            try:
                self._responses.put(json.loads(line))
            except Exception as exc:
                self._responses.put(RuntimeError(f"invalid JSON response: {exc}; line={line!r}"))

    def _drain_stderr(self) -> None:
        assert self.proc.stderr is not None
        for line in self.proc.stderr:
            self._stderr.append(line.rstrip())

    def request(self, request_id: int, method: str, params: dict[str, Any] | None = None, timeout: float = 20) -> dict[str, Any]:
        assert self.proc.stdin is not None
        message: dict[str, Any] = {"jsonrpc": "2.0", "id": request_id, "method": method}
        if params is not None:
            message["params"] = params
        self.proc.stdin.write(json.dumps(message) + "\n")
        self.proc.stdin.flush()
        try:
            response = self._responses.get(timeout=timeout)
        except queue.Empty as exc:
            raise TimeoutError(
                f"timed out waiting for {method}; exit={self.proc.poll()}; stderr={self.stderr_tail}"
            ) from exc
        if isinstance(response, Exception):
            raise response
        return response

    def notify_initialized(self) -> None:
        assert self.proc.stdin is not None
        self.proc.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
        self.proc.stdin.flush()

    @property
    def stderr_tail(self) -> str:
        return "\n".join(self._stderr[-20:])

    def close(self) -> None:
        try:
            if self.proc.stdin is not None:
                self.proc.stdin.close()
        except Exception:
            pass
        if self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait(timeout=5)


def summarize_tool_response(response: dict[str, Any]) -> dict[str, Any]:
    result = response.get("result")
    if not isinstance(result, dict):
        return {"has_result": False}

    content = result.get("content")
    content_items = content if isinstance(content, list) else []
    text_bytes = 0
    error_preview = None
    for item in content_items:
        if not isinstance(item, dict):
            continue
        text = item.get("text")
        if not isinstance(text, str):
            continue
        text_bytes += len(text.encode("utf-8"))
        if result.get("isError") is True and error_preview is None:
            error_preview = text.splitlines()[0][:300] if text else ""

    meta = result.get("_meta")
    manifold_meta = {}
    if isinstance(meta, dict) and isinstance(meta.get("manifold"), dict):
        manifold_meta = meta["manifold"]

    summary: dict[str, Any] = {
        "has_result": True,
        "is_error": result.get("isError") is True,
        "content_items": len(content_items),
        "text_bytes": text_bytes,
        "manifold_meta": manifold_meta,
    }
    if error_preview:
        summary["error_preview"] = error_preview
    return summary


def main() -> int:
    probe = MCPProbe()
    try:
        initialize = probe.request(
            1,
            "initialize",
            {
                "protocolVersion": "2025-11-25",
                "capabilities": {
                    "extensions": {
                        "io.modelcontextprotocol/ui": {
                            "mimeTypes": ["text/html;profile=mcp-app"],
                        },
                    },
                },
                "clientInfo": {"name": "claude-ai", "version": "0.1.0"},
            },
        )
        probe.notify_initialized()
        tools = probe.request(2, "tools/list", {})
        health = probe.request(
            3,
            "tools/call",
            {"name": "manifold_health", "arguments": {}},
            timeout=30,
        )
        files = probe.request(
            4,
            "tools/call",
            {"name": "list_files", "arguments": {"intent_summary": "Claude Desktop MCP health probe"}},
            timeout=30,
        )
        emails = probe.request(
            5,
            "tools/call",
            {"name": "list_emails", "arguments": {"intent_summary": "Claude Desktop MCP health probe"}},
            timeout=30,
        )

        payload = {
            "pid": probe.proc.pid,
            "initialize": {
                "protocol_version": initialize.get("result", {}).get("protocolVersion"),
                "server_info": initialize.get("result", {}).get("serverInfo"),
            },
            "tool_count": len(tools.get("result", {}).get("tools", [])),
            "manifold_health": summarize_tool_response(health),
            "list_files": summarize_tool_response(files),
            "list_emails": summarize_tool_response(emails),
            "stderr_tail": probe.stderr_tail,
        }
        print(json.dumps(payload, indent=2, sort_keys=True))
        health_error = health.get("result", {}).get("isError") is True
        files_error = files.get("result", {}).get("isError") is True
        emails_error = emails.get("result", {}).get("isError") is True
        return 1 if health_error or files_error or emails_error else 0
    finally:
        probe.close()


if __name__ == "__main__":
    sys.exit(main())
