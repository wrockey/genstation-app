#!/usr/bin/env python3
"""Live-socket test against the REAL, running GenStation app (manual live check).

`smoke_test.py` fakes the app side (a canned Unix-socket server) and drives the
bundled `genstation-mcp` helper's stdio. This script is the opposite: it IS the
agent/helper side — a bare python client that speaks the app's line-delimited
JSON protocol directly against the socket of a real, already-running GenStation
Debug build. Debug builds bypass peer auth (`#if DEBUG` in MCPPeerAuth.swift),
which is what makes an unsigned python client acceptable to the app at all; a
Release build would reject this same client (see the Release peer-auth half of
Task 8, checked separately and not by this script).

Wire format (GenStation/Agents/MCPService.swift:493-529):
    request:  {"id": "...", "method": "...", "params": {...}}\\n
    response: {"id": "...", "result": {...}}\\n
           or {"id": "...", "error": {"code": "...", "message": "...", "data": {...}}}\\n
over a Unix domain socket at
    ~/Library/Containers/art.genstation.app/Data/Library/Application Support/art.genstation.app/mcp.sock

Prerequisites (this script does NOT launch the app or flip any settings):
  - A Debug build of GenStation is running.
  - Agent Access is ON (default ON — MCPService.isEnabledInSettings).
  - An AI/ML API key is configured, for the paid checks (only run when the
    confirm-first dialog gate is open — see below).

Confirm-first safety: generate_image goes through MCPCore.authorize()
(MCPService.swift:787-817), which pops a real NSAlert via
`alert.runModal()` (MCPService.swift:1421-1470, MCPDialogs) whenever the
connection is not on the standing daily budget or a per-connection grant.
Per MCPCore.openSession (MCPService.swift:479-483), a connection only avoids
the dialog when `mcpConfirmFirst == false AND mcpStandingBudgetUSD > 0` —
confirm-first OFF alone is not enough. runModal() blocks synchronously on
that connection's MainActor task until a human clicks a button, and nothing
here may ever click one. So before attempting any paid generate_image call,
this script reads the app's OWN persisted settings (the UserDefaults-backed
prefs plist, matching `@AppStorage` defaults in GenStationApp.swift) to
determine whether the dialog gate is open. If it is closed (the common,
default case), every check gated behind it is reported SKIP with a reason,
and must be checked manually in the app. This is a read of the
app's own persisted state, not a settings change, and nothing here drives
the app's GUI.

Usage: python3 live_socket_test.py
Exit codes: 0 = no FAILs (SKIPs do not fail the run), 1 = at least one FAIL,
2 = the app's MCP socket is not reachable at all (Agent Access looks OFF —
a human must turn it on in Settings).
"""

import json
import os
import plistlib
import re
import socket
import stat
import sys
import time
import uuid

BUNDLE_ID = "art.genstation.app"
HOME = os.path.expanduser("~")
CONTAINER_DIR = (
    f"{HOME}/Library/Containers/{BUNDLE_ID}/Data/Library/Application Support/{BUNDLE_ID}"
)
SOCKET_PATH = os.environ.get("GENSTATION_MCP_SOCKET", f"{CONTAINER_DIR}/mcp.sock")
STATE_PATH = f"{CONTAINER_DIR}/mcp_state.json"
PREFS_PLIST = f"{HOME}/Library/Containers/{BUNDLE_ID}/Data/Library/Preferences/{BUNDLE_ID}.plist"

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CATALOG_MODELS_DIR = os.path.join(
    REPO_ROOT, "Packages/GenStationCore/Sources/GenStationCore/Catalog/Models"
)

CHEAP_T2I_MODEL = "flux/schnell"  # ~1c/image — cheapest registered t2i model
PREFERRED_I2I_MODEL = "google/gemini-3-1-flash-lite-image"  # cheap, 1K, acceptsBase64
CANONICAL_ALWAYS_PRESENT_ID = "google/gemini-3.1-flash-image-preview"
KNOWN_ALIAS_ID = "nano-banana-2"  # alias of the id above — must never be its own row

# 1x1 transparent PNG (same constant smoke_test.py uses) — a durable, checked-in
# stand-in for "a small PNG I built myself" so this script has no external file
# dependency and stays re-runnable from a clean checkout.
TINY_PNG_B64 = (
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNg"
    "YGBgAAAABQABh6FO1AAAAABJRU5ErkJggg=="
)

results = []  # (name, status) — status in {"PASS", "FAIL", "SKIP"}


def record(name, status, detail=""):
    print(f"[{status}] {name}" + (f" — {detail}" if detail else ""))
    results.append((name, status))


def check(name, condition, detail=""):
    record(name, "PASS" if condition else "FAIL", detail if not condition else "")
    return condition


def skip(name, reason):
    record(name, "SKIP", reason)


# --- socket plumbing -------------------------------------------------------


def send_request(method, params=None, timeout=30):
    """Open one connection, send one line-delimited JSON request, read one
    response line, close. Mirrors the framing in MCPService.swift:493-529.

    sockaddr_un.sun_path is capped at 104 bytes on macOS and the sandboxed
    container path is usually longer than that — the same problem
    MCPService.bindAndListen works around (MCPService.swift:271-299) by
    chdir-ing into the socket's directory and binding the bare filename. We
    do the mirror image on connect: chdir, connect to the relative filename,
    then restore cwd (even on failure) so this has no lasting side effect."""
    sock_dir = os.path.dirname(SOCKET_PATH)
    sock_name = os.path.basename(SOCKET_PATH)
    prev_cwd = os.getcwd()
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    try:
        os.chdir(sock_dir)
        sock.connect(sock_name)
        req = {"id": str(uuid.uuid4()), "method": method, "params": params or {}}
        sock.sendall((json.dumps(req) + "\n").encode())
        buf = b""
        while b"\n" not in buf:
            chunk = sock.recv(65536)
            if not chunk:
                raise ConnectionError("socket closed before a full response line arrived")
            buf += chunk
    finally:
        sock.close()
        os.chdir(prev_cwd)
    line = buf.split(b"\n", 1)[0]
    return json.loads(line)


# --- settings introspection (read-only; never written by this script) ------


def confirm_gate_status():
    """(confirm_first, standing_budget_usd, note). See the module docstring for
    why this is read from the persisted plist rather than probed live."""
    try:
        with open(PREFS_PLIST, "rb") as f:
            prefs = plistlib.load(f)
    except Exception as e:
        return True, 0.0, f"could not read prefs plist ({e}) — assuming the dialog gate is closed"
    # Defaults match the @AppStorage declarations in GenStationApp.swift.
    confirm_first = bool(prefs.get("mcpConfirmFirst", True))
    standing = float(prefs.get("mcpStandingBudgetUSD", 0.0))
    return confirm_first, standing, None


# --- catalog introspection (read-only source scan, for the .dead assertion) -


def find_dead_catalog_ids():
    """Heuristic scan of the checked-in catalog source for ids whose row sets
    `lifecycle: .dead`, so list_models's exclusion of them can be asserted
    without GenStation exposing lifecycle over the wire. One id per
    CatalogModel(...) block; a block's `id:` line precedes its `lifecycle:`
    line by convention (see any file in Catalog/Models/)."""
    dead_ids = []
    if not os.path.isdir(CATALOG_MODELS_DIR):
        return dead_ids
    id_re = re.compile(r'^\s*id:\s*"([^"]+)"')
    lifecycle_re = re.compile(r'lifecycle:\s*\.dead\b')
    for fname in sorted(os.listdir(CATALOG_MODELS_DIR)):
        if not fname.endswith(".swift"):
            continue
        current_id = None
        with open(os.path.join(CATALOG_MODELS_DIR, fname), encoding="utf-8") as f:
            for line in f:
                m = id_re.match(line)
                if m:
                    current_id = m.group(1)
                elif lifecycle_re.search(line) and current_id:
                    dead_ids.append(current_id)
                    current_id = None
    return dead_ids


# --- ledger introspection ----------------------------------------------------


def read_ledger_today():
    try:
        with open(STATE_PATH) as f:
            state = json.load(f)
    except Exception:
        return 0.0
    # MCPLedger.dayKey: local-time calendar day, "%04d-%02d-%02d" (MCPStateStore.swift).
    key = time.strftime("%Y-%m-%d")
    return float(state.get("ledgerByDay", {}).get(key, 0.0))


def pick_i2i_model(models):
    """An i2i id from the live list_models response, preferring PREFERRED_I2I_MODEL.
    Returns None (never an arbitrary guess) when the live app didn't actually offer one —
    the caller must SKIP rather than send a request naming a model nothing confirmed exists."""
    candidates = [
        m for m in models
        if m.get("requires_input_image") or (m.get("max_input_images") or 0) > 0
    ]
    for m in candidates:
        if m.get("id") == PREFERRED_I2I_MODEL:
            return m["id"]
    return candidates[0]["id"] if candidates else None


def main():
    print(f"[INFO] socket: {SOCKET_PATH}")
    print(f"[INFO] sidecar: {STATE_PATH}")

    # --- (1) socket + sidecar exist, correct mode [A1] ---------------------
    sock_stat = os.stat(SOCKET_PATH) if os.path.exists(SOCKET_PATH) else None
    if check("socket exists", sock_stat is not None, SOCKET_PATH) and sock_stat:
        check("socket is a unix socket (S_ISSOCK)", stat.S_ISSOCK(sock_stat.st_mode))
        check("socket mode 0600", stat.S_IMODE(sock_stat.st_mode) == 0o600,
              oct(stat.S_IMODE(sock_stat.st_mode)))

    state_stat = os.stat(STATE_PATH) if os.path.exists(STATE_PATH) else None
    if check("mcp_state.json exists", state_stat is not None, STATE_PATH) and state_stat:
        check("mcp_state.json mode 0600", stat.S_IMODE(state_stat.st_mode) == 0o600,
              oct(stat.S_IMODE(state_stat.st_mode)))

    # If there's no socket at all, nothing past this point can run — that is
    # exactly the "Agent Access is off" signal (MCPService only binds the
    # socket when startIfEnabled's guard passes). Stop and ask for a human.
    if sock_stat is None:
        print("\nSTATUS: NEEDS ATTENTION — no MCP socket found. Agent Access is likely OFF "
              "in GenStation's General Options (Settings/GeneralOptionsView.swift). "
              "A human needs to flip it on once; this script does not drive the GUI.")
        sys.exit(2)

    # --- (2) list_models -----------------------------------------------------
    models = []
    try:
        resp = send_request("list_models")
    except Exception as e:
        check("list_models: responds", False, str(e))
        resp = None

    if resp is None:
        print("\nSTATUS: NEEDS ATTENTION — socket exists but list_models did not get a usable "
              "response (connection refused / reset). Agent Access may be OFF, the app just "
              "isn't the one holding this socket, or (on a signed/Release build) this "
              "unsigned client was rejected by peer auth (MCPPeerAuth.isTrustedPeer) — check "
              "the app's log for 'MCP: rejected peer'. A human needs to check the toggle "
              "(this script never drives the GUI or re-signs itself).")
        sys.exit(2)

    result = resp.get("result")
    if check("list_models: no error", result is not None, json.dumps(resp)[:400]):
        models = result.get("models", [])
        ids = [m.get("id") for m in models]
        check("list_models: returns >0 models", len(models) > 0, f"count={len(models)}")
        check("list_models: includes google/gemini-3.1-flash-image-preview",
              CANONICAL_ALWAYS_PRESENT_ID in ids, f"ids sample: {ids[:8]}")
        check("list_models: alias id 'nano-banana-2' is not its own row",
              KNOWN_ALIAS_ID not in ids, f"ids sample: {ids[:8]}")
        dead_ids = find_dead_catalog_ids()
        if not dead_ids:
            # A check that can never see a `.dead` id can never fail either — that's a green
            # line that proves nothing. Say so out loud instead of reporting a silent PASS.
            skip("list_models: excludes every .dead catalog id",
                 f"the catalog scan found zero 'lifecycle: .dead' rows in {CATALOG_MODELS_DIR} "
                 "— there is currently nothing dead to exclude, so this check cannot exercise "
                 "the exclusion path. Re-run once a model is retired to .dead to get a real PASS/FAIL.")
        else:
            leaked = sorted(set(ids) & set(dead_ids))
            check("list_models: excludes every .dead catalog id",
                  not leaked, f"leaked={leaked} (scanned {len(dead_ids)} known-dead ids in {CATALOG_MODELS_DIR})")

    # --- confirm-first dialog gate: decide which paid checks can run --------
    confirm_first, standing_budget, note = confirm_gate_status()
    dialog_gated = confirm_first or standing_budget <= 0
    if note:
        print(f"[INFO] {note}")
    print(f"[INFO] mcpConfirmFirst={confirm_first} mcpStandingBudgetUSD={standing_budget} "
          f"-> generate_image dialog gate is {'CLOSED (would pop a dialog)' if dialog_gated else 'open'}")

    gate_reason = (
        "confirm-first dialog gate is closed (mcpConfirmFirst="
        f"{confirm_first}, mcpStandingBudgetUSD={standing_budget} — MCPCore.openSession "
        "only skips the dialog when confirm-first is OFF AND the standing budget is > 0, "
        "MCPService.swift:479-483). generate_image would block on a real NSAlert "
        "(MCPService.swift:1421-1470) waiting for a human to click Approve/Deny — this "
        "script will never do that. Needs a human: either set a standing daily budget with "
        "confirm-first OFF and re-run this script, or approve the request manually "
        "in the app."
    )

    # --- (3) generate_image on flux/schnell (paid, cheapest) [A2] ------------
    if dialog_gated:
        skip("generate_image: flux/schnell t2i (paid, ~1c)", gate_reason)
    else:
        ledger_before = read_ledger_today()
        try:
            resp = send_request(
                "generate_image",
                {"model": CHEAP_T2I_MODEL, "prompt": "a small red cube on a plain white background", "params": {}},
                timeout=180,
            )
        except Exception as e:
            check("generate_image: flux/schnell responds", False, str(e))
            resp = None
        if resp is not None:
            result = resp.get("result", {})
            ok = check("generate_image: flux/schnell status is done",
                       result.get("status") == "done", json.dumps(resp)[:500])
            if ok:
                fp = result.get("file_path")
                check("generate_image: file_path exists on disk", bool(fp) and os.path.exists(fp), fp)
                cost = result.get("cost_usd")
                if check("generate_image: cost_usd present and > 0",
                         isinstance(cost, (int, float)) and cost > 0, str(cost)):
                    time.sleep(1.0)  # let persist() land before we re-read the sidecar
                    ledger_after = read_ledger_today()
                    grew_correctly = abs((ledger_after - ledger_before) - cost) <= 0.001
                    check("mcp_state.json ledgerByDay today grew by cost_usd (+/- $0.001) [A2]",
                          grew_correctly,
                          f"before={ledger_before} after={ledger_after} cost_usd={cost}")

    # --- (4) generate_image i2i [B2] -----------------------------------------
    i2i_model = pick_i2i_model(models)
    if i2i_model is None:
        skip("generate_image: i2i (paid) [B2]",
             "list_models returned no candidate with requires_input_image or "
             "max_input_images > 0 — nothing to pick, and this script will not guess a model "
             "id the live app didn't actually offer.")
        skip("generate_image: file-path input_images -> input_image_invalid [B2]",
             "no i2i model available (see above) — same reason.")
    elif dialog_gated:
        skip(f"generate_image: i2i on {i2i_model} (paid) [B2]", gate_reason)
    else:
        data_uri = f"data:image/png;base64,{TINY_PNG_B64}"
        try:
            resp = send_request(
                "generate_image",
                {"model": i2i_model, "prompt": "add a small blue star in the corner",
                 "input_images": [data_uri], "params": {}},
                timeout=180,
            )
        except Exception as e:
            check(f"generate_image: i2i on {i2i_model} responds", False, str(e))
            resp = None
        if resp is not None:
            result = resp.get("result", {})
            check(f"generate_image: i2i on {i2i_model} status is done [B2]",
                  result.get("status") == "done", json.dumps(resp)[:500])

    # --- (5) input_images file path rejected [B2 file-path rejection] --------
    # (already SKIPped above, once, if i2i_model is None — don't double-report)
    if i2i_model is None:
        pass
    elif dialog_gated:
        skip("generate_image: file-path input_images -> input_image_invalid [B2]", gate_reason)
    else:
        try:
            resp = send_request(
                "generate_image",
                {"model": i2i_model, "prompt": "x", "input_images": ["/etc/passwd"]},
                timeout=30,
            )
        except Exception as e:
            check("generate_image: file-path input_images responds", False, str(e))
            resp = None
        if resp is not None:
            err = resp.get("error", {})
            check("generate_image: file-path input_images -> input_image_invalid",
                  err.get("code") == "input_image_invalid", json.dumps(err))
            msg = err.get("message", "").lower()
            check("generate_image: error mentions base64 data URIs (not file paths)",
                  "data uri" in msg or ("data:" in msg and "uri" in msg), err.get("message"))

    # --- (6) more images than max_input_images -> input_image_invalid -------
    # This check runs BEFORE MCPCore.authorize() (MCPService.swift:686-690 vs.
    # 719-721) so it never reaches the confirm dialog — free regardless of gate.
    try:
        resp = send_request(
            "generate_image",
            {"model": CHEAP_T2I_MODEL, "prompt": "x", "input_images": [f"data:image/png;base64,{TINY_PNG_B64}"]},
        )
    except Exception as e:
        check("generate_image: too many input_images responds", False, str(e))
        resp = None
    if resp is not None:
        err = resp.get("error", {})
        check("generate_image: too many input_images -> input_image_invalid",
              err.get("code") == "input_image_invalid", json.dumps(err))
        check("generate_image: error data.max_input_images == 0 for flux/schnell",
              err.get("data", {}).get("max_input_images") == 0, json.dumps(err.get("data")))

    # --- (7) get_job_status with a random UUID -> invalid_params, no crash --
    try:
        resp = send_request("get_job_status", {"job_id": str(uuid.uuid4())})
    except Exception as e:
        check("get_job_status: random job_id responds (no crash)", False, str(e))
        resp = None
    if resp is not None:
        err = resp.get("error", {})
        check("get_job_status: random job_id -> invalid_params",
              err.get("code") == "invalid_params", json.dumps(err))

    # --- summary --------------------------------------------------------------
    passed = sum(1 for _, s in results if s == "PASS")
    failed = [n for n, s in results if s == "FAIL"]
    skipped = [n for n, s in results if s == "SKIP"]
    print(f"\n{len(results)} checks: {passed} passed, {len(failed)} failed, {len(skipped)} skipped.")
    if skipped:
        print("Skipped — needs a human to check manually:")
        for n in skipped:
            print(f"  - {n}")
    if failed:
        print(f"\n{len(failed)} FAILURE(S): {failed}")
        sys.exit(1)
    print("\nAll runnable checks passed.")


if __name__ == "__main__":
    main()
