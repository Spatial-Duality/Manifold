#!/usr/bin/env python3
"""E2E crash/restart coverage for the real Manifold MCP -> XPC path."""

from __future__ import annotations

import json
import os
import re
import shutil
import signal
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APP_BIN = ROOT / ".deriveddata-ui-tests/Build/Products/Debug/Manifold.app/Contents/MacOS/Manifold"
MCP_BIN = ROOT / ".deriveddata-ui-tests/Build/Products/Debug/Manifold.app/Contents/Resources/manifold-mcp"


class MCPClient:
    def __init__(self, env: dict[str, str], host_bin: Path) -> None:
        self.proc = subprocess.Popen(
            [str(host_bin), str(MCP_BIN), "--agent", "codex"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
            env=env,
        )
        if self.proc.stdin is None or self.proc.stdout is None or self.proc.stderr is None:
            raise RuntimeError("failed to open MCP stdio pipes")
        self.stdin = self.proc.stdin
        self.stdout = self.proc.stdout
        self.stderr_lines: list[str] = []
        self._stderr_thread = threading.Thread(target=self._drain_stderr, daemon=True)
        self._stderr_thread.start()
        self.next_id = 1
        self.request(
            "initialize",
            {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": "restart-disconnect-e2e", "version": "1"},
            },
            timeout=20,
        )
        self.notify("notifications/initialized")

    def _drain_stderr(self) -> None:
        assert self.proc.stderr is not None
        for line in self.proc.stderr:
            self.stderr_lines.append(line.rstrip())

    def close(self) -> None:
        try:
            self.stdin.close()
        except Exception:
            pass
        if self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.proc.kill()

    def notify(self, method: str) -> None:
        self.stdin.write(json.dumps({"jsonrpc": "2.0", "method": method, "params": {}}) + "\n")
        self.stdin.flush()

    def request(self, method: str, params: dict, timeout: float = 10) -> dict:
        request_id = self.next_id
        self.next_id += 1
        payload = {"jsonrpc": "2.0", "id": request_id, "method": method, "params": params}
        self.stdin.write(json.dumps(payload) + "\n")
        self.stdin.flush()

        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            line = self.stdout.readline()
            if not line:
                if self.proc.poll() is not None:
                    raise RuntimeError(f"MCP exited early: {self.stderr_text}")
                time.sleep(0.05)
                continue
            response = json.loads(line)
            if response.get("id") != request_id:
                continue
            if "error" in response:
                raise RuntimeError(response["error"])
            return response
        raise TimeoutError(f"timed out waiting for {method}; stderr={self.stderr_text}")

    @property
    def stderr_text(self) -> str:
        return "\n".join(self.stderr_lines[-20:])

    def call_tool(self, name: str, arguments: dict | None = None, timeout: float = 20) -> tuple[str, bool]:
        response = self.request(
            "tools/call",
            {"name": name, "arguments": arguments or {}},
            timeout=timeout,
        )
        result = response.get("result", {})
        content = result.get("content", [])
        text = "\n".join(item.get("text", "") for item in content if item.get("type") == "text")
        return text, bool(result.get("isError", False))


def wait_until(label: str, timeout: float, predicate) -> object:
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        last = predicate()
        if last:
            return last
        time.sleep(0.5)
    raise AssertionError(f"timed out waiting for {label}; last={last!r}")


def launch_app(test_home: Path) -> tuple[subprocess.Popen, dict[str, str]]:
    env = os.environ.copy()
    env.update(
        {
            "MANIFOLD_UI_TEST_MODE": "1",
            "MANIFOLD_TEST_RUNTIME_MODE": "local",
            "MANIFOLD_TEST_SCENARIO": "synthetic-mcp-ui",
            "MANIFOLD_TEST_HOME": str(test_home),
            "MANIFOLD_TEST_PROTECTED_STORAGE_KEY": str(test_home),
            "MANIFOLD_TEST_ALLOW_UI_RUNNER_MCP": "1",
        }
    )
    log = open(test_home.with_suffix(".app.log"), "w", encoding="utf-8")
    proc = subprocess.Popen([str(APP_BIN)], env=env, stdout=log, stderr=log, text=True)
    source_root = test_home / "sources/Synthetic MCP UI"
    wait_until("synthetic source bootstrap", 20, lambda: source_root.exists())
    return proc, env


def stop_app(proc: subprocess.Popen) -> None:
    if proc.poll() is not None:
        return
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()


def build_codex_host_wrapper(test_home: Path) -> Path:
    source = test_home / "codex-mcp-host.c"
    binary = test_home / "codex-mcp-host"
    source.write_text(
        r'''
#include <errno.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <sys/wait.h>
#include <unistd.h>

static void copy_all(int fd, const char *buffer, ssize_t length) {
    ssize_t written = 0;
    while (written < length) {
        ssize_t result = write(fd, buffer + written, (size_t)(length - written));
        if (result <= 0) return;
        written += result;
    }
}

int main(int argc, char **argv) {
    if (argc < 2) return 64;
    int child_stdin[2], child_stdout[2], child_stderr[2];
    if (pipe(child_stdin) != 0 || pipe(child_stdout) != 0 || pipe(child_stderr) != 0) return 65;
    pid_t pid = fork();
    if (pid < 0) return 66;
    if (pid == 0) {
        dup2(child_stdin[0], STDIN_FILENO);
        dup2(child_stdout[1], STDOUT_FILENO);
        dup2(child_stderr[1], STDERR_FILENO);
        close(child_stdin[0]); close(child_stdin[1]);
        close(child_stdout[0]); close(child_stdout[1]);
        close(child_stderr[0]); close(child_stderr[1]);
        execv(argv[1], &argv[1]);
        _exit(127);
    }
    close(child_stdin[0]); close(child_stdout[1]); close(child_stderr[1]);
    int stdin_open = 1, stdout_open = 1, stderr_open = 1;
    char buffer[4096];
    while (stdout_open || stderr_open) {
        fd_set readfds;
        FD_ZERO(&readfds);
        int maxfd = -1;
        if (stdin_open) { FD_SET(STDIN_FILENO, &readfds); if (STDIN_FILENO > maxfd) maxfd = STDIN_FILENO; }
        if (stdout_open) { FD_SET(child_stdout[0], &readfds); if (child_stdout[0] > maxfd) maxfd = child_stdout[0]; }
        if (stderr_open) { FD_SET(child_stderr[0], &readfds); if (child_stderr[0] > maxfd) maxfd = child_stderr[0]; }
        if (select(maxfd + 1, &readfds, NULL, NULL, NULL) < 0) {
            if (errno == EINTR) continue;
            break;
        }
        if (stdin_open && FD_ISSET(STDIN_FILENO, &readfds)) {
            ssize_t n = read(STDIN_FILENO, buffer, sizeof(buffer));
            if (n <= 0) { close(child_stdin[1]); stdin_open = 0; }
            else copy_all(child_stdin[1], buffer, n);
        }
        if (stdout_open && FD_ISSET(child_stdout[0], &readfds)) {
            ssize_t n = read(child_stdout[0], buffer, sizeof(buffer));
            if (n <= 0) { close(child_stdout[0]); stdout_open = 0; }
            else copy_all(STDOUT_FILENO, buffer, n);
        }
        if (stderr_open && FD_ISSET(child_stderr[0], &readfds)) {
            ssize_t n = read(child_stderr[0], buffer, sizeof(buffer));
            if (n <= 0) { close(child_stderr[0]); stderr_open = 0; }
            else copy_all(STDERR_FILENO, buffer, n);
        }
        int status = 0;
        if (waitpid(pid, &status, WNOHANG) == pid && !stdout_open && !stderr_open) {
            return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
        }
    }
    int status = 0;
    waitpid(pid, &status, 0);
    return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
}
''',
        encoding="utf-8",
    )
    subprocess.run(["clang", str(source), "-o", str(binary)], check=True)
    return binary


def service_label(test_home: Path) -> str:
    suffix = re.sub(r"[^a-z0-9.-]", "-", test_home.name.lower()).strip("-")
    return f"com.spatialduality.manifold.runtime.{suffix}"


def launchctl_print(label: str) -> str:
    result = subprocess.run(
        ["launchctl", "print", f"gui/{os.getuid()}/{label}"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stdout.strip())
    return result.stdout


def launchd_pid(label: str) -> int:
    output = launchctl_print(label)
    match = re.search(r"\bpid\s*=\s*(\d+)", output)
    if not match:
        raise RuntimeError(f"launchd service has no pid yet:\n{output[-1000:]}")
    return int(match.group(1))


def failure_count(db_path: Path) -> int:
    conn = sqlite3.connect(str(db_path))
    try:
        row = conn.execute(
            """
            SELECT COUNT(*) FROM mcp_failure_events
            WHERE classification IN ('xpc.connection_invalidated', 'xpc.runtime_unavailable', 'xpc.timeout')
            """
        ).fetchone()
        return int(row[0])
    finally:
        conn.close()


def wait_for_visible_files(mcp: MCPClient, timeout: float = 30) -> str:
    def visible() -> str | None:
        text, is_error = mcp.call_tool("list_files", timeout=10)
        return text if not is_error and "Docs/ReleaseNotes.md" in text else None

    return wait_until("MCP files visible", timeout, visible)


def main() -> int:
    for path in (APP_BIN, MCP_BIN):
        if not path.exists():
            print(f"missing build product: {path}", file=sys.stderr)
            return 2

    test_home = Path(tempfile.mkdtemp(prefix="manifold-mcp-restart-"))
    app_proc: subprocess.Popen | None = None
    mcp: MCPClient | None = None
    failed = False
    try:
        app_proc, env = launch_app(test_home)
        host_bin = build_codex_host_wrapper(test_home)
        mcp = MCPClient(env, host_bin)
        status_text, status_error = mcp.call_tool("get_status", timeout=30)
        if status_error:
            raise AssertionError(f"get_status failed before restart: {status_text}")
        wait_for_visible_files(mcp)

        label = service_label(test_home)
        before_pid = wait_until("runtime helper pid", 20, lambda: launchd_pid(label))
        before_failures = failure_count(test_home / "runtime-store/manifold.db")
        os.kill(int(before_pid), signal.SIGKILL)

        interrupted_text, interrupted_error = mcp.call_tool("list_files", timeout=10)
        if not interrupted_error:
            # A fast launchd restart can make the first post-kill call succeed.
            # The next assertion still verifies the recovered visible set.
            pass
        elif "Manifold error" not in interrupted_text and "No active runtime connection" not in interrupted_text:
            raise AssertionError(f"unexpected interrupted response: {interrupted_text}")

        wait_for_visible_files(mcp)
        after_pid = wait_until(
            "runtime helper restarted",
            30,
            lambda: (pid if (pid := launchd_pid(label)) != before_pid else None),
        )

        after_failures = failure_count(test_home / "runtime-store/manifold.db")
        if after_failures <= before_failures:
            raise AssertionError("runtime interruption did not leave a durable MCP failure event")

        print(f"PASS restart-disconnect old_pid={before_pid} new_pid={after_pid}")
        return 0
    except Exception:
        failed = True
        print(f"FAILED restart-disconnect; preserved test home: {test_home}", file=sys.stderr)
        raise
    finally:
        if mcp is not None:
            mcp.close()
        if app_proc is not None:
            stop_app(app_proc)
        if not failed:
            shutil.rmtree(test_home, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
