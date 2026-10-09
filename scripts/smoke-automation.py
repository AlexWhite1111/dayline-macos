#!/usr/bin/env python3
"""Check CLI help and MCP metadata."""
import json
from pathlib import Path
import subprocess
import sys

binaries = Path(sys.argv[1])
for option in ["help", "--help", "-h"]:
    help_result = subprocess.run(
        [str(binaries / "dayline-cli"), option],
        capture_output=True, text=True, check=True, timeout=15,
    )
    assert "dayline add" in help_result.stdout
requests = [
    {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
        "protocolVersion": "2025-11-25", "capabilities": {},
        "clientInfo": {"name": "dayline-check", "version": "1"}}},
    {"jsonrpc": "2.0", "method": "notifications/initialized"},
    {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
    {"jsonrpc": "2.0", "id": 3, "method": "ping"},
]
result = subprocess.run(
    [str(binaries / "dayline-mcp")],
    input="".join(json.dumps(request) + "\n" for request in requests),
    capture_output=True, text=True, check=True, timeout=15,
)
responses = [json.loads(line) for line in result.stdout.splitlines()]
assert [response["id"] for response in responses] == [1, 2, 3]
assert responses[0]["result"]["serverInfo"]["name"] == "dayline-mcp"
assert {tool["name"] for tool in responses[1]["result"]["tools"]} == {
    "list_todos", "add_todo", "add_todos", "update_todo", "set_timeline_range",
    "set_todo_completed", "delete_todo", "get_settings", "update_settings",
    "show_timeline",
}
assert responses[2]["result"] == {}
print("CLI help and MCP initialize/tools-list/ping passed.")
