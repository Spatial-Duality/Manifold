#!/usr/bin/env python3
"""Failure-mode E2E coverage for the real Codex MCP path.

This harness intentionally exercises the stdio MCP adapter as the Codex
agent. Scenarios that touch launchd must be run as a normal GUI user, not
from a restricted Python/Codex sandbox, because launchd can deny bootstrap
before Manifold code is reached.
"""

from __future__ import annotations

import importlib.util
import json
import os
import queue
import shutil
import signal
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path
from types import ModuleType


ROOT = Path(__file__).resolve().parents[1]
APP_BIN = ROOT / ".deriveddata-ui-tests/Build/Products/Debug/Manifold.app/Contents/MacOS/Manifold"
MCP_BIN = ROOT / ".deriveddata-ui-tests/Build/Products/Debug/Manifold.app/Contents/Resources/manifold-mcp"


def load_script(name: str) -> ModuleType:
    path = ROOT / "scripts" / name
    spec = importlib.util.spec_from_file_location(path.stem, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"unable to load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


restart = load_script("mcp_restart_disconnect_e2e.py")
source_health = load_script("source_health_mcp_e2e.py")


class RawMCPProcess:
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
        self.responses: queue.Queue[dict | Exception] = queue.Queue()
        self._stdout_thread = threading.Thread(target=self._drain_stdout, daemon=True)
        self._stderr_thread = threading.Thread(target=self._drain_stderr, daemon=True)
        self._stdout_thread.start()
        self._stderr_thread.start()

    def _drain_stdout(self) -> None:
        for line in self.stdout:
            try:
                self.responses.put(json.loads(line))
            except Exception as exc:
                self.responses.put(exc)

    def _drain_stderr(self) -> None:
        assert self.proc.stderr is not None
        for line in self.proc.stderr:
            self.stderr_lines.append(line.rstrip())

    def write_line(self, line: str) -> None:
        self.stdin.write(line + "\n")
        self.stdin.flush()

    def read_response(self, timeout: float = 10) -> dict:
        try:
            response = self.responses.get(timeout=timeout)
        except queue.Empty as exc:
            raise TimeoutError(f"timed out waiting for MCP response; stderr={self.stderr_text}") from exc
        if isinstance(response, Exception):
            raise RuntimeError(f"invalid response from MCP: {response}")
        return response

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

    @property
    def stderr_text(self) -> str:
        return "\n".join(self.stderr_lines[-20:])


def base_env(test_home: Path) -> dict[str, str]:
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
    return env


def launch_app_with_env(
    test_home: Path,
    extra_env: dict[str, str] | None = None,
) -> tuple[subprocess.Popen, dict[str, str]]:
    env = base_env(test_home)
    if extra_env:
        env.update(extra_env)
    log = open(test_home.with_suffix(".app.log"), "w", encoding="utf-8")
    proc = subprocess.Popen([str(APP_BIN)], env=env, stdout=log, stderr=log, text=True)
    source_root = test_home / "sources/Synthetic MCP UI"
    restart.wait_until("synthetic source bootstrap", 20, lambda: source_root.exists())
    return proc, env


def call_tool_response(mcp, name: str, arguments: dict | None = None, timeout: float = 20) -> dict:
    response = mcp.request(
        "tools/call",
        {"name": name, "arguments": arguments or {}},
        timeout=timeout,
    )
    return response.get("result", {})


def manifold_meta(result: dict) -> dict:
    return result.get("_meta", {}).get("manifold", {})


def failure_events(db_path: Path) -> list[tuple[str, str, str | None, str, str]]:
    conn = sqlite3.connect(str(db_path))
    try:
        rows = conn.execute(
            """
            SELECT request_id, classification, tool_name, boundary, phase
            FROM mcp_failure_events
            ORDER BY timestamp ASC
            """
        ).fetchall()
        return [(str(a), str(b), c, str(d), str(e)) for a, b, c, d, e in rows]
    finally:
        conn.close()


def count_classifications(db_path: Path, classifications: set[str]) -> int:
    return sum(1 for _, classification, _, _, _ in failure_events(db_path) if classification in classifications)


def diagnostic_names(test_home: Path) -> list[str]:
    names: list[str] = []
    diagnostics_dir = test_home / "diagnostics"
    for path in diagnostics_dir.glob("*.jsonl"):
        for line in path.read_text(encoding="utf-8").splitlines():
            try:
                payload = json.loads(line)
            except json.JSONDecodeError:
                continue
            name = payload.get("name")
            if isinstance(name, str):
                names.append(name)
    return names


def scenario_protocol_errors() -> None:
    test_home = Path(tempfile.mkdtemp(prefix="manifold-mcp-protocol-"))
    raw: RawMCPProcess | None = None
    failed = False
    try:
        host_bin = restart.build_codex_host_wrapper(test_home)
        raw = RawMCPProcess(base_env(test_home), host_bin)

        raw.write_line('{"jsonrpc":"2.0","id":1,')
        parse_error = raw.read_response()
        assert parse_error["error"]["code"] == -32700, parse_error

        raw.write_line(json.dumps({"jsonrpc": "2.0", "id": 7, "params": {}}))
        invalid_request = raw.read_response()
        assert invalid_request["id"] == 7, invalid_request
        assert invalid_request["error"]["code"] == -32600, invalid_request

        raw.write_line(json.dumps({"jsonrpc": "2.0", "id": 8, "method": "no/such_method", "params": {}}))
        missing_method = raw.read_response()
        assert missing_method["id"] == 8, missing_method
        assert missing_method["error"]["code"] == -32601, missing_method
    except Exception:
        failed = True
        print(f"FAILED protocol-errors; preserved test home: {test_home}", file=sys.stderr)
        raise
    finally:
        if raw is not None:
            raw.close()
        if not failed:
            shutil.rmtree(test_home, ignore_errors=True)


def scenario_old_agent_version_mismatch_fails_closed() -> None:
    test_home = Path(tempfile.mkdtemp(prefix="manifold-mcp-old-agent-version-"))
    app_proc: subprocess.Popen | None = None
    failed = False
    try:
        app_proc, _ = launch_app_with_env(
            test_home,
            {"MANIFOLD_TEST_AGENT_VERSION_OVERRIDE": "0.0.0-old"},
        )

        def mismatch_recorded() -> bool:
            names = diagnostic_names(test_home)
            return "versionMismatchRestart" in names and "runtimeRestartFailed" in names

        restart.wait_until("old helper version restart failure diagnostics", 30, mismatch_recorded)
        names = diagnostic_names(test_home)
        assert names.count("versionMismatchRestart") == 1, names
        assert "runtimeRestartFailed" in names, names
    except Exception:
        failed = True
        print(f"FAILED old-agent-version; preserved test home: {test_home}", file=sys.stderr)
        raise
    finally:
        if app_proc is not None:
            restart.stop_app(app_proc)
        if not failed:
            shutil.rmtree(test_home, ignore_errors=True)


def scenario_runtime_unavailable_records_failure() -> None:
    test_home = Path(tempfile.mkdtemp(prefix="manifold-mcp-runtime-unavailable-"))
    mcp = None
    failed = False
    try:
        host_bin = restart.build_codex_host_wrapper(test_home)
        mcp = restart.MCPClient(base_env(test_home), host_bin)
        result = call_tool_response(mcp, "get_status", timeout=20)
        assert result.get("isError") is True, result

        meta = manifold_meta(result)
        request_id = meta.get("request_id")
        error = meta.get("error", {})
        assert request_id, result
        assert error.get("classification") == "xpc.runtime_unavailable", result
        assert error.get("retryable") is True, result

        rows = failure_events(test_home / "runtime-store/manifold.db")
        assert any(
            row_request_id == request_id and classification == "xpc.runtime_unavailable"
            for row_request_id, classification, _, _, _ in rows
        ), rows
    except Exception:
        failed = True
        print(f"FAILED runtime-unavailable; preserved test home: {test_home}", file=sys.stderr)
        raise
    finally:
        if mcp is not None:
            mcp.close()
        if not failed:
            shutil.rmtree(test_home, ignore_errors=True)


def scenario_launchagent_bootout_records_failure() -> None:
    test_home = Path(tempfile.mkdtemp(prefix="manifold-mcp-bootout-"))
    app_proc: subprocess.Popen | None = None
    mcp = None
    failed = False
    try:
        app_proc, env = restart.launch_app(test_home)
        host_bin = restart.build_codex_host_wrapper(test_home)
        mcp = restart.MCPClient(env, host_bin)
        restart.wait_for_visible_files(mcp)

        label = restart.service_label(test_home)
        restart.wait_until("runtime helper pid", 20, lambda: restart.launchd_pid(label))
        db_path = test_home / "runtime-store/manifold.db"
        before = count_classifications(
            db_path,
            {"xpc.runtime_unavailable", "xpc.connection_invalidated", "xpc.timeout"},
        )

        result = subprocess.run(
            ["launchctl", "bootout", f"gui/{os.getuid()}/{label}"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        if result.returncode != 0 and "No such process" not in result.stdout:
            raise RuntimeError(result.stdout.strip())

        tool_result = call_tool_response(mcp, "list_files", timeout=20)
        assert tool_result.get("isError") is True, tool_result
        classification = manifold_meta(tool_result).get("error", {}).get("classification")
        assert classification in {"xpc.runtime_unavailable", "xpc.connection_invalidated"}, tool_result

        after = count_classifications(
            db_path,
            {"xpc.runtime_unavailable", "xpc.connection_invalidated", "xpc.timeout"},
        )
        assert after > before, (before, after, failure_events(db_path))
    except Exception:
        failed = True
        print(f"FAILED launchagent-bootout; preserved test home: {test_home}", file=sys.stderr)
        raise
    finally:
        if mcp is not None:
            mcp.close()
        if app_proc is not None:
            restart.stop_app(app_proc)
        if not failed:
            shutil.rmtree(test_home, ignore_errors=True)


def scenario_two_clients_survive_helper_crash() -> None:
    test_home = Path(tempfile.mkdtemp(prefix="manifold-mcp-two-clients-"))
    app_proc: subprocess.Popen | None = None
    mcp_a = None
    mcp_b = None
    failed = False
    try:
        app_proc, env = restart.launch_app(test_home)
        host_bin = restart.build_codex_host_wrapper(test_home)
        mcp_a = restart.MCPClient(env, host_bin)
        mcp_b = restart.MCPClient(env, host_bin)
        restart.wait_for_visible_files(mcp_a)
        restart.wait_for_visible_files(mcp_b)

        label = restart.service_label(test_home)
        before_pid = restart.wait_until("runtime helper pid", 20, lambda: restart.launchd_pid(label))
        db_path = test_home / "runtime-store/manifold.db"
        before = count_classifications(
            db_path,
            {"xpc.runtime_unavailable", "xpc.connection_invalidated", "xpc.timeout"},
        )

        os.kill(int(before_pid), signal.SIGKILL)
        restart.wait_for_visible_files(mcp_a)
        restart.wait_for_visible_files(mcp_b)
        after_pid = restart.wait_until(
            "runtime helper restarted",
            30,
            lambda: (pid if (pid := restart.launchd_pid(label)) != before_pid else None),
        )
        assert after_pid != before_pid

        after = count_classifications(
            db_path,
            {"xpc.runtime_unavailable", "xpc.connection_invalidated", "xpc.timeout"},
        )
        assert after > before, (before, after, failure_events(db_path))
    except Exception:
        failed = True
        print(f"FAILED two-clients-helper-crash; preserved test home: {test_home}", file=sys.stderr)
        raise
    finally:
        if mcp_b is not None:
            mcp_b.close()
        if mcp_a is not None:
            mcp_a.close()
        if app_proc is not None:
            restart.stop_app(app_proc)
        if not failed:
            shutil.rmtree(test_home, ignore_errors=True)


def scenario_source_health_modes() -> None:
    result = source_health.main()
    assert result == 0


def scenario_single_client_helper_crash() -> None:
    result = restart.main()
    assert result == 0


SCENARIOS: list[tuple[str, str, object]] = [
    ("FM-PROTO-001", "malformed JSON, invalid JSON-RPC, and unknown method responses", scenario_protocol_errors),
    ("FM-XPC-001", "runtime unavailable returns structured retryable MCP error and durable event", scenario_runtime_unavailable_records_failure),
    ("FM-LAUNCHD-005", "old runtime helper version triggers one restart then fails closed if unresolved", scenario_old_agent_version_mismatch_fails_closed),
    ("FM-LAUNCHD-001", "LaunchAgent bootout produces classified durable failure", scenario_launchagent_bootout_records_failure),
    ("FM-XPC-002", "single MCP client survives helper SIGKILL and demand-start reconnect", scenario_single_client_helper_crash),
    ("FM-XPC-003", "two concurrent Codex MCP clients survive helper SIGKILL with stale connection IDs", scenario_two_clients_survive_helper_crash),
    ("FM-SOURCE-001", "source rename/delete/replace cannot leak stale file visibility", scenario_source_health_modes),
]


def main() -> int:
    for path in (APP_BIN, MCP_BIN):
        if not path.exists():
            print(f"missing build product: {path}", file=sys.stderr)
            return 2

    started = time.monotonic()
    for identifier, description, body in SCENARIOS:
        print(f"RUN {identifier} {description}", flush=True)
        body()
        print(f"PASS {identifier}", flush=True)
    elapsed = time.monotonic() - started
    print(f"PASS all failure-mode scenarios in {elapsed:.1f}s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
