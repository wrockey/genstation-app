#!/usr/bin/env python3
"""End-to-end protocol smoke test for the genstation-mcp helper (WS-7).

Plays the GenStation app side over a Unix socket (canned responses) while
driving the helper's stdio with JSON-RPC — the GenStation app itself is never
launched (GENSTATION_MCP_SOCKET disables auto-launch).

Usage: python3 smoke_test.py /path/to/genstation-mcp
"""

import json
import plistlib
from pathlib import Path
import os
import socket
import subprocess
import sys
import tempfile
import threading

# 1x1 transparent PNG
TINY_PNG_B64 = (
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNg"
    "YGBgAAAABQABh6FO1AAAAABJRU5ErkJggg=="
)

FAKE_RESULTS = {
    "list_models": {
        "result": {
            "models": [
                {
                    "id": "flux/dev",
                    "is_video": False,
                    "max_input_images": 0,
                    "requires_input_image": False,
                    "parameters": {"num_images": 1, "image_size": "square_hd"},
                },
                {
                    "id": "veo-3.1-t2v",
                    "is_video": True,
                    "max_input_images": 0,
                    "requires_input_image": False,
                    "parameters": {"duration": 8, "resolution": "720p"},
                },
            ],
            "count": 2,
        }
    },
    "generate_image": {
        "result": {
            "job_id": "11111111-2222-3333-4444-555555555555",
            "status": "done",
            "file_path": "/Users/test/Downloads/generated_media_1.png",
            "cost_usd": 0.012,
            "preview_png_base64": TINY_PNG_B64,
        }
    },
    "generate_video": {
        "result": {"job_id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", "status": "queued"}
    },
    "get_job_status": {
        "error": {
            "code": "invalid_params",
            "message": "Unknown job_id 'zzz'.",
        }
    },
}

# Canned structured error for the credit-exhaustion path (fix 5): the app maps a
# 402/403 balance failure to insufficient_credits; the helper must pass the code,
# message, and data through as an isError tool result.
INSUFFICIENT_CREDITS_ERROR = {
    "error": {
        "code": "insufficient_credits",
        "message": "You're out of API credits. Top up your balance to continue:\nhttps://aimlapi.com/app/billing/",
        "data": {"billing_url": "https://aimlapi.com/app/billing/"},
    }
}

# Every request the fake app receives, so tests can assert the helper forwards
# tool arguments verbatim (fix 4: the list_models type filter must reach the app).
FORWARDED = []

failures = []


def check(name, condition, detail=""):
    tag = "PASS" if condition else "FAIL"
    print(f"[{tag}] {name}" + (f" — {detail}" if detail and not condition else ""))
    if not condition:
        failures.append(name)


# Methods the fake app should answer slowly, to prove the helper keeps servicing
# stdio (ping) locally while a tools/call is forwarded and blocked. Value = delay
# in seconds.
SLOW_METHODS = {"generate_video": 1.0}


def fake_app_server(sock_path, ready):
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(sock_path)
    server.listen(1)
    ready.set()
    conn, _ = server.accept()
    buf = b""
    while True:
        data = conn.recv(65536)
        if not data:
            break
        buf += data
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            if not line.strip():
                continue
            request = json.loads(line)
            FORWARDED.append(request)
            method = request.get("method")
            if method in SLOW_METHODS:
                threading.Event().wait(SLOW_METHODS[method])
            response = {"id": request.get("id")}
            if method == "generate_image" and request.get("params", {}).get("prompt") == "no credits":
                response.update(INSUFFICIENT_CREDITS_ERROR)
            else:
                response.update(FAKE_RESULTS.get(
                    method, {"error": {"code": "invalid_params", "message": f"fake: unknown {method}"}}))
            conn.sendall(json.dumps(response).encode() + b"\n")
    conn.close()
    server.close()


def main():
    for parent in Path(sys.argv[1]).resolve().parents:
        info = parent / 'Contents/Info.plist'
        if parent.suffix == '.app' and info.exists():
            if plistlib.loads(info.read_bytes()).get('CFBundleIdentifier') == 'art.genstation.demo':
                raise RuntimeError('Mock tests require a production-mode helper, never an embedded demo helper.')
    if len(sys.argv) != 2:
        sys.exit(f"usage: {sys.argv[0]} /path/to/genstation-mcp")
    helper = sys.argv[1]

    tmpdir = tempfile.mkdtemp(prefix="genstation-mcp-test-")
    sock_path = os.path.join(tmpdir, "mcp.sock")
    ready = threading.Event()
    threading.Thread(target=fake_app_server, args=(sock_path, ready), daemon=True).start()
    ready.wait(5)

    proc = subprocess.Popen(
        [helper],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env={**os.environ, "GENSTATION_MCP_SOCKET": sock_path},
    )

    def send(obj):
        proc.stdin.write(json.dumps(obj).encode() + b"\n")
        proc.stdin.flush()

    def recv():
        line = proc.stdout.readline()
        if not line:
            raise RuntimeError("helper closed stdout")
        return json.loads(line)

    def call_tool(rpc_id, name, arguments=None):
        send({"jsonrpc": "2.0", "id": rpc_id, "method": "tools/call",
              "params": {"name": name, "arguments": arguments or {}}})
        return recv()

    try:
        # --- initialize
        send({"jsonrpc": "2.0", "id": 1, "method": "initialize",
              "params": {"protocolVersion": "2025-06-18",
                         "capabilities": {}, "clientInfo": {"name": "smoke", "version": "0"}}})
        r = recv()
        result = r.get("result", {})
        check("initialize: jsonrpc envelope", r.get("jsonrpc") == "2.0" and r.get("id") == 1, str(r))
        if result.get("serverInfo", {}).get("name") == "genstation-demo":
            raise RuntimeError("Use a standalone production-mode helper for mock tests; demo helpers ignore socket overrides.")
        check("initialize: protocolVersion", result.get("protocolVersion") == "2025-06-18", str(result))
        check("initialize: serverInfo.name", result.get("serverInfo", {}).get("name") == "genstation", str(result))
        check("initialize: capabilities.tools", "tools" in result.get("capabilities", {}), str(result))

        check("initialize: resources capability", result.get("capabilities", {}).get("resources") == {})
        instructions = result.get("instructions", "")
        check("initialize: essential workflow instructions", all(term.lower() in instructions.lower() for term in ["genstation://docs/image-workflow", "request_id", "IDENTICAL", "approval", "unknown", "get_asset", "generate_video"]))
        send({"jsonrpc": "2.0", "id": 900, "method": "resources/list"})
        resources = recv().get("result", {}).get("resources", [])
        check("resources: bundled guide advertised", len(resources) == 1 and resources[0].get("uri") == "genstation://docs/image-workflow" and resources[0].get("mimeType") == "text/markdown")
        send({"jsonrpc": "2.0", "id": 901, "method": "resources/read", "params": {"uri": "genstation://docs/image-workflow"}})
        contents = recv().get("result", {}).get("contents", [])
        guide = contents[0].get("text", "") if contents else ""
        check("resources: complete workflow guide", all(term in guide for term in ["## Example", "billing_status", "resubmit_safe", "insufficient_credits", "20 MB", "64 megapixels", "revocation", "no pagination", "generate_video"]))
        check("resources: read envelope", len(contents) == 1 and contents[0].get("uri") == resources[0]["uri"] and contents[0].get("mimeType") == "text/markdown")
        for request_id, params, expected in [(902, {}, -32602), (903, {"uri": 123}, -32602), (904, {"uri": "file:///etc/passwd"}, -32002), (905, {"uri": "genstation://docs/missing"}, -32002)]:
            send({"jsonrpc": "2.0", "id": request_id, "method": "resources/read", "params": params})
            check("resources: reject invalid/unknown URI " + str(request_id), recv().get("error", {}).get("code") == expected)
        send({"jsonrpc": "2.0", "id": 906, "method": "resources/templates/list"})
        check("resources: no invented templates", recv().get("result", {}).get("resourceTemplates") == [])
        send({"jsonrpc": "2.0", "id": 907, "method": "resources/list", "params": {"cursor": "unknown"}})
        check("resources: invalid cursor rejected", recv().get("error", {}).get("code") == -32602)
        check("resources: served locally without app proxy", not FORWARDED)

        # --- notifications/initialized must produce no response;
        # the next reply must be for tools/list (id 2).
        send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        send({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
        r = recv()
        check("notification suppressed; tools/list id matches", r.get("id") == 2, str(r))
        tools = r.get("result", {}).get("tools", [])
        names = sorted(t.get("name") for t in tools)
        check("tools/list: bounded image tools",
              names == sorted(["generate_image", "generate_video", "get_job_status", "list_models", "validate_image_request", "list_assets", "get_asset", "connection_status", "list_styles", "compose_prompt", "list_workflows", "validate_workflow_request", "run_saved_workflow", "validate_video_request", "recover_video_job", "recover_workflow_job", "list_jobs", "wait_for_job", "list_history_folders", "create_history_folder", "rename_history_folder", "move_history_assets"]), str(names))
        check("tools/list: inputSchema present",
              all(isinstance(t.get("inputSchema"), dict) and t["inputSchema"].get("type") == "object" for t in tools))
        gen = next(t for t in tools if t["name"] == "generate_image")
        check("tools/list: generate_image requires model+prompt",
              sorted(gen["inputSchema"].get("required", [])) == ["model", "prompt", "provider", "request_id"], str(gen["inputSchema"]))

        # fix 4: list_models must advertise its type filter in the inputSchema.
        lm = next(t for t in tools if t["name"] == "list_models")
        lm_type = lm["inputSchema"].get("properties", {}).get("type", {})
        check("tools/list: list_models advertises type filter (enum image/video)",
              sorted(lm_type.get("enum", [])) == ["image", "video"], str(lm["inputSchema"]))

        # fix 5: descriptions document the structured insufficient_credits code.
        check("tools/list: generate tools document insufficient_credits",
              all("insufficient_credits" in t.get("description", "")
                  for t in tools if t["name"] in ("generate_image", "generate_video", "get_job_status")),
              str([t.get("description") for t in tools]))

        # --- tools/call list_models (proxied over the socket)
        r = call_tool(3, "list_models")
        content = r.get("result", {}).get("content", [])
        check("list_models: text content item",
              len(content) == 1 and content[0].get("type") == "text", str(content))
        body = json.loads(content[0]["text"])
        check("list_models: models round-tripped",
              body.get("count") == 2 and body["models"][0]["id"] == "flux/dev", str(body))
        check("list_models: not an error", not r.get("result", {}).get("isError", False))

        check("list_models: structuredContent matches JSON text", r.get("result", {}).get("structuredContent") == body)
        for name in ["validate_image_request", "list_assets", "get_asset", "connection_status"]:
            FAKE_RESULTS[name] = {"result": {"checked": name}}
            response = call_tool(100 + ["validate_image_request", "list_assets", "get_asset", "connection_status"].index(name), name, {"probe": "forwarded"})
            check(name + ": proxied and structured", response.get("result", {}).get("structuredContent") == {"checked": name}, str(response))
        check("image schema advertises asset/data inputs", "input_images" in gen["inputSchema"]["properties"])

        # --- tools/call generate_image → text + image content
        r = call_tool(4, "generate_image", {"model": "flux/dev", "prompt": "a lighthouse at dusk"})
        content = r.get("result", {}).get("content", [])
        types = [c.get("type") for c in content]
        check("generate_image: text + image items", types == ["text", "image"], str(types))
        body = json.loads(content[0]["text"])
        check("generate_image: file_path in text summary",
              body.get("file_path", "").endswith("generated_media_1.png"), str(body))
        check("generate_image: preview lifted out of text", "preview_png_base64" not in body, str(body))
        image = content[1] if len(content) > 1 else {}
        check("generate_image: image item shape",
              image.get("mimeType") == "image/png" and image.get("data") == TINY_PNG_B64)

        # --- fix 4: the list_models type filter must be forwarded to the app
        # verbatim (a {"type": "video"} argument used to be dropped, so the app
        # returned image models too).
        r = call_tool(10, "list_models", {"type": "video"})
        check("list_models type filter: call succeeds",
              not r.get("result", {}).get("isError", False), str(r))
        forwarded = [q for q in FORWARDED if q.get("method") == "list_models"
                     and q.get("params", {}).get("type") == "video"]
        check("list_models type filter forwarded to the app", len(forwarded) == 1,
              str([q for q in FORWARDED if q.get("method") == "list_models"]))

        # --- fix 5: a credit-exhaustion failure surfaces as the structured
        # insufficient_credits error (isError tool result), with the billing URL
        # preserved in message and data.
        r = call_tool(11, "generate_image", {"model": "flux/dev", "prompt": "no credits"})
        result = r.get("result", {})
        check("insufficient_credits: isError", result.get("isError") is True, str(result))
        body = json.loads(result["content"][0]["text"])
        err = body.get("error", {})
        check("insufficient_credits: structured code",
              err.get("code") == "insufficient_credits", str(body))
        check("insufficient_credits: billing url in message + data",
              "aimlapi.com/app/billing" in err.get("message", "")
              and err.get("data", {}).get("billing_url", "").startswith("https://aimlapi.com"),
              str(err))

        check("provider failure: no invented local diagnostics",
              "filter_reasons" not in err.get("data", {}) and "filter_source" not in err.get("data", {}))

        # --- tools/call generate_video → async job id
        r = call_tool(5, "generate_video", {"model": "veo-3.1-t2v", "prompt": "waves", "request_id": "smoke-video"})
        body = json.loads(r["result"]["content"][0]["text"])
        check("generate_video: queued with job_id",
              body.get("status") == "queued" and "job_id" in body, str(body))

        # Filter diagnostics must survive the helper unchanged in both result forms.
        filter_data = {"filter_source": "genstation_local", "filter_reasons": [{
            "rule": "forbidden_text_pattern", "category": "prohibited_text",
            "policy_version": "text-2026-09-14", "match_kind": "normalized_phrase", "phrase": "gore"}]}
        for index, tool in enumerate(["validate_image_request", "validate_video_request", "validate_workflow_request",
                                      "generate_image", "generate_video", "run_saved_workflow"], 800):
            previous = FAKE_RESULTS.get(tool)
            FAKE_RESULTS[tool] = {"error": {"code": "content_filtered", "message": "Local text rejection", "data": filter_data}}
            response = call_tool(index, tool, {"prompt": "gore"})["result"]
            check(tool + ": filter data retained", response.get("isError") is True and
                  response.get("structuredContent", {}).get("error", {}).get("data") == filter_data and
                  json.loads(response["content"][0]["text"]) == response["structuredContent"])
            if previous is None:
                del FAKE_RESULTS[tool]
            else:
                FAKE_RESULTS[tool] = previous

        # --- tools/call get_job_status → structured error as isError result
        r = call_tool(6, "get_job_status", {"job_id": "zzz"})
        result = r.get("result", {})
        check("get_job_status error: isError", result.get("isError") is True, str(result))
        body = json.loads(result["content"][0]["text"])
        check("get_job_status error: structured code",
              body.get("error", {}).get("code") == "invalid_params", str(body))

        # --- unknown tool → isError with invalid_params
        r = call_tool(7, "frobnicate")
        result = r.get("result", {})
        body = json.loads(result["content"][0]["text"])
        check("unknown tool: isError + invalid_params",
              result.get("isError") is True and body["error"]["code"] == "invalid_params", str(body))

        # --- ping
        send({"jsonrpc": "2.0", "id": 8, "method": "ping"})
        r = recv()
        check("ping: empty result", r.get("result") == {}, str(r))

        # --- unknown method → -32601
        send({"jsonrpc": "2.0", "id": 9, "method": "unsupported/test-method"})
        r = recv()
        check("unknown method: -32601", r.get("error", {}).get("code") == -32601, str(r))

        # id-matched reader for the out-of-order responses the concurrency test
        # produces (a locally-served ping can overtake a forwarded tools/call).
        pending = {}

        def recv_id(target):
            if target in pending:
                return pending.pop(target)
            while True:
                msg = recv()
                if msg.get("id") == target:
                    return msg
                pending[msg.get("id")] = msg

        # --- fix 9: a slow tools/call must not block ping. generate_video is
        # delayed ~1s by the fake app; the ping sent right after must reply first.
        send({"jsonrpc": "2.0", "id": 20, "method": "tools/call",
              "params": {"name": "generate_video",
                         "arguments": {"model": "veo-3.1-t2v", "prompt": "slow"}}})
        send({"jsonrpc": "2.0", "id": 21, "method": "ping"})
        first = recv()
        check("slow tools/call does not block ping (ping replies first)",
              first.get("id") == 21, str(first))
        tool = recv_id(20)
        body = json.loads(tool.get("result", {}).get("content", [{}])[0].get("text", "{}"))
        check("slow tools/call still returns its result",
              body.get("status") == "queued", str(tool))

        # --- fix 10: protocol version negotiation
        send({"jsonrpc": "2.0", "id": 30, "method": "initialize",
              "params": {"protocolVersion": "2024-11-05", "capabilities": {}}})
        r = recv_id(30)
        check("initialize echoes a known requested protocolVersion (2024-11-05)",
              r.get("result", {}).get("protocolVersion") == "2024-11-05", str(r))

        send({"jsonrpc": "2.0", "id": 31, "method": "initialize",
              "params": {"protocolVersion": "1999-01-01", "capabilities": {}}})
        r = recv_id(31)
        check("initialize falls back to latest for an unknown protocolVersion",
              r.get("result", {}).get("protocolVersion") == "2025-06-18", str(r))

    finally:
        proc.stdin.close()
        proc.wait(timeout=10)
        stderr = proc.stderr.read().decode()
        if stderr:
            print("--- helper stderr ---")
            print(stderr.rstrip())

    if failures:
        print(f"\n{len(failures)} FAILURE(S): {failures}")
        sys.exit(1)
    print("\nAll smoke-test checks passed.")


if __name__ == "__main__":
    main()
