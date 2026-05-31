# xrdp watchdogs — design spec

**Date:** 2026-05-23
**Status:** draft, pending implementation
**Module:** `~/uap/os/xrdp/`

## Problem

Three known bugs in xrdp 0.9.24 (Ubuntu 24.04 noble) make RDP reattach unreliable. All hit on reconnect, all have known manual fixes, none have native auto-remediation upstream:

1. **Black screen** — a stale xrdp child from an unclean previous disconnect (laptop sleep, network blip) keeps its TCP socket `ESTABLISHED` and holds `/run/xrdp/sockdir/xrdp_chansrv_socket_<N>`. The next reconnect can't claim chansrv. Fix: kill the stale xrdp child PID.
2. **chansrv missing/defunct** — `xrdp-chansrv` for an active session dies or hangs without a parent respawn. New connections get no clipboard/audio/drive redirection. Fix: kill defunct chansrv, manually respawn with the session's env.
3. **Clipboard desync (cliprdr)** — chansrv state corrupts on disconnect; cliprdr channel inherits broken state on next mstsc connect. Fix: kill chansrv, respawn, then the operator must disconnect+reconnect mstsc for the cliprdr handshake to redo.

These bugs are tolerable on `Policy=UBD` (current default — fewer reattaches) but become frequent on `Policy=U` or `Policy=UB`, which is the configuration users will want for Windows-RDP-like reconnect behavior.

## Goal

Ship a watchdog in the UAP `xrdp` module that auto-detects and remediates all three bugs, so operators can safely run `Policy=U` / `Policy=UB` without babysitting reconnects. Must be safe enough for OSS distribution: never make xrdp worse than baseline, survive xrdp version upgrades, fail open.

## Non-goals

- Replicating Windows Terminal Services reattach semantics perfectly (X11 cannot change bpp/depth at runtime).
- Reaping arbitrary stale/orphan sessions beyond the three bug paths.
- Patching upstream xrdp.
- Active liveness probing of X11 sessions (false-positive risk against legitimately idle sessions).

## Design overview

A single bash script (`xrdp-watchdog`) installed to `/usr/local/bin/`, scheduled by a systemd timer (`xrdp-watchdog.timer`) every 30 seconds. Each tick is independent and idempotent; the script holds no in-memory state between ticks. systemd handles scheduling, restart, and logging.

### Why polling over log-tailing

- Survives xrdp version drift (state-based assertions vs log-format coupling).
- Auditable: `xrdp-watchdog --check` runs the same checks in dry-run mode for diagnostics.
- Fails safe: a crashed timer is visible in `systemctl status`; a hung log-tailer would silently stop reacting.
- No state to corrupt across ticks.

### File layout

```
~/uap/os/xrdp/                          # in-repo
├── reconnectwm.sh                      (existing — modifier-stuck fix)
├── xrdp-watchdog                       (new — bash script)
├── xrdp-watchdog.service               (new — systemd oneshot)
└── xrdp-watchdog.timer                 (new — fires every 30s)

# installed by ~/uap/setup/apply.sh:
/usr/local/bin/xrdp-watchdog
/etc/systemd/system/xrdp-watchdog.service
/etc/systemd/system/xrdp-watchdog.timer
/etc/sudoers.d/xrdp-watchdog
```

## Detection invariants

Three checks. Each prints `OK` / `BAD: <reason>` / `SKIP: <reason>`. Only `BAD` triggers remediation.

### Check A — Stale xrdp child holding chansrv

**Premise:** A live RDP session has exactly one xrdp child holding its chansrv socket. A stale child holds the socket with no live remote peer.

**Steps:**
1. Enumerate xrdp children of the xrdp listener (PPID = listener PID).
2. For each child, find its `ESTABLISHED` TCP socket on port 3389 via `ss -tnp`.
3. Mark stale if: TCP peer is unreachable (kernel keepalive declared dead OR explicit probe fails) AND child age > 60s AND there exists another xrdp child for the same session/display.
4. **Solo-session guard:** never mark stale if it's the *only* xrdp child for a display.

### Check B — chansrv socket missing or unowned

**Premise:** For each active X display N, `/run/xrdp/sockdir/xrdp_chansrv_socket_<N>` must exist and be owned by a live `xrdp-chansrv` process.

**Steps:**
1. List displays: `ls /tmp/.X11-unix/X*`.
2. For each display N:
   - Socket missing + no chansrv process for display N = `BAD`.
   - Socket missing + chansrv process exists for display N = `BAD` (defunct).
   - Socket present + chansrv alive = `OK`.

### Check C — cliprdr desync (clipboard broken)

**Default mode (passive):** scan `journalctl -u xrdp --since "1 minute ago"` for cliprdr error patterns:
- `[ERROR] clipboard_event_selection_request: unknown target`
- `xrdp-chansrv: [ERROR] cliprdr_*`

A match within the last tick interval = `BAD`.

**Opt-in mode (active probe):** gated by identity flag `xrdp.watchdog_clipboard_active_probe: true`. For each session, set a sentinel value into xclip on its display, read back via RDP channel. Mismatch across two ticks = `BAD`. Off by default because it briefly touches the user's clipboard.

## Remediation actions

All remediations share a single `flock` lock at `/run/xrdp-watchdog.lock` (non-blocking — skip tick if held).

### Fix A — stale xrdp child
1. Re-verify staleness on candidate PID (world may have changed since detection). Abort if no longer stale.
2. `sudo kill -TERM <pid>`; wait up to 5s; `kill -KILL` if still alive.
3. Verify chansrv socket returns to `LISTEN` state. If not, log and bail (no escalation cascade).
4. Log: `fixed stale xrdp child pid=X for display=Y`.

### Fix B — chansrv missing/defunct
1. Resolve session owner: read `/proc/<sesman-pid>/environ` for `USER`, `DISPLAY`, `XAUTHORITY`.
2. Kill any defunct chansrv for that display.
3. Respawn:
   ```bash
   sudo -u <user> DISPLAY=:<N> XAUTHORITY=<auth> XRDP_SESSION=<N> \
     nohup /usr/sbin/xrdp-chansrv >/var/log/xrdp/chansrv-<N>.log 2>&1 &
   ```
4. Wait up to 3s for socket to reappear; verify.
5. Log: `respawned chansrv for display=Y user=Z`.

### Fix C — cliprdr desync
1. Find chansrv PID for affected display; kill (`-TERM`, then `-KILL` after 3s).
2. Respawn (same recipe as Fix B).
3. Send desktop notification to the affected user's session:
   ```bash
   sudo -u <user> DISPLAY=:<N> notify-send -u normal -t 10000 \
     "xrdp clipboard restarted" \
     "Disconnect and reconnect your RDP client to restore copy/paste."
   ```
4. `notify-send` is a soft dep: if missing, fix still runs, notification skipped with warning.
5. Log: `respawned chansrv for cliprdr desync display=Y; user notified`.

## Cross-cutting guards

- **Single in-flight remediation per host:** `flock` on `/run/xrdp-watchdog.lock`.
- **Per-fix backoff:** if Fix X ran in the last 90s, skip and log. Prevents loops when remediation doesn't stick.
- **Hourly circuit breaker:** max 10 remediations per rolling hour. Beyond that, idle until next hour with `circuit breaker tripped` log line.
- **Soft fail on every action:** any `sudo`/`kill`/`spawn` failure is logged and the script exits 0. Timer stays healthy. xrdp is never worse off after a failed fix attempt.
- **Fail open guarantee:** if the watchdog is uninstalled, disabled, or itself crashes, xrdp continues operating exactly as it would without the watchdog. No invariants are added that xrdp depends on.

## CLI surface

```
xrdp-watchdog              # one-shot tick (used by timer)
xrdp-watchdog --check      # dry-run: print findings, exit 0/1, no remediation
xrdp-watchdog --once       # one-shot tick (manual invocation, same as no-arg)
xrdp-watchdog --dry-run    # print what each fix would do, no execution
xrdp-watchdog --explain    # dump current state of xrdp children, chansrv sockets, X displays
xrdp-watchdog --help
```

## Logging

- All output via `logger -t xrdp-watchdog` → journalctl.
- Idle ticks: `debug` level (filtered by default `LogLevelMax` on the service unit).
- Findings + remediations: `info`.
- Failures, missing deps, circuit breaker: `warning`.
- Inspection: `journalctl -u xrdp-watchdog -f`.

## UAP integration

### `~/uap.local/identity.yaml` additions

```yaml
xrdp:
  sesman_policy: UBD                     # existing
  install_reconnectwm: true              # existing
  install_watchdog: auto                 # NEW — true | false | auto
  watchdog_interval_seconds: 30          # NEW — timer cadence
  watchdog_clipboard_active_probe: false # NEW — opt-in active probe
  tcp_keepalive: true                    # NEW — sets tcp_keepalive in xrdp.ini [Globals]
```

**`install_watchdog: auto` resolution:**
- `auto` → enabled if `sesman_policy` ∈ {`U`, `UB`}, disabled otherwise.
- `true` / `false` → explicit override.

Rationale for `auto`: operators who stick with the default `UBD` policy hit these bugs rarely (they get fresh sessions on different bpp). The watchdog earns its keep on reattach-heavy policies where the same chansrv survives many reconnects.

### `apply.sh` changes (additions to existing `install_xrdp()`)

1. **tcp_keepalive patch.** If `xrdp.tcp_keepalive: true` and `/etc/xrdp/xrdp.ini` lacks `tcp_keepalive=true` in `[Globals]`, patch idempotently with `sed` (same pattern as the existing sesman Policy patch). Log change. The patch logic is the source of truth; `xrdp.ini` is not shipped wholesale in the module (it's an upstream-managed file we only nudge in place).

2. **Watchdog install.** Evaluate `install_watchdog` (resolving `auto`).

   If enabled:
   - Create system user `xrdp-watchdog` (no shell, no home dir).
   - `install -m 755 -o root -g root` the script to `/usr/local/bin/xrdp-watchdog`.
   - Render `xrdp-watchdog.service` and `xrdp-watchdog.timer` templates (substituting `OnUnitActiveSec` from `watchdog_interval_seconds`).
   - `install -m 644` the units to `/etc/systemd/system/`.
   - Install `/etc/sudoers.d/xrdp-watchdog` (mode 440), validated with `visudo -c` before activating.
   - `systemctl daemon-reload && systemctl enable --now xrdp-watchdog.timer`.
   - Run `xrdp-watchdog --check` as a self-test; if it can't introspect, abort apply and roll back.

   If disabled and previously installed:
   - `systemctl disable --now xrdp-watchdog.timer`
   - Remove `/usr/local/bin/xrdp-watchdog`, the unit files, sudoers file, and user (idempotent).

### sudoers (scoped, mode 440)

```
# /etc/sudoers.d/xrdp-watchdog
xrdp-watchdog ALL=(root) NOPASSWD: /bin/kill -TERM *, /bin/kill -KILL *, /bin/kill -0 *
xrdp-watchdog ALL=(ALL) NOPASSWD: /usr/sbin/xrdp-chansrv
xrdp-watchdog ALL=(root) NOPASSWD: /usr/bin/cat /proc/*/environ
```

No general root, no shell, only the operations Fix A/B/C need.

### README documentation

Add a section to `~/uap/README.md` under "Known issues" titled "RDP reconnect bugs (auto-fixed by watchdog)":

- Describe all three bugs in plain language.
- Document the identity toggles.
- Document inspection commands: `systemctl status xrdp-watchdog.timer`, `journalctl -u xrdp-watchdog -f`, `xrdp-watchdog --check`.
- Document how to disable (set `install_watchdog: false`, rerun `apply.sh`).
- Link to this spec for design rationale.

## Testing approach

### Helper shims (testability)

Detection functions read state via small wrappers:

```bash
_list_xrdp_children()         # returns PIDs
_get_chansrv_socket_state()   # returns LISTEN | CONNECTED | MISSING
_list_active_displays()       # returns "10 11 12"
_journalctl_recent_errors()   # returns matched log lines
```

Each wrapper checks an env override first (`XRDP_WATCHDOG_TEST_<NAME>`). Tests set the env var to inject fake state, then run the check function.

### Integration tests

`~/uap/os/xrdp/tests/watchdog-integration.sh` — runs only on a disposable VM (refuses to run if `/etc/uap.local/test-mode` absent). Reproduces each bug deliberately:

- **Fix A:** spawn fake stale xrdp child holding a socket; run watchdog; assert PID gone, socket back to LISTEN.
- **Fix B:** send `SIGSTOP` to a real chansrv; run watchdog; assert respawn.
- **Fix C:** synthesize a fake cliprdr ERROR log line; run watchdog; assert chansrv respawned and notify-send invoked (or skip-with-warning if no libnotify).

### Smoke test (in `apply.sh`)

After install, `apply.sh` runs `xrdp-watchdog --check`. If output is malformed or exit code is non-zero on a clean system, abort apply and roll back the install.

### Manual fuzz (documented)

README documents reproduction recipes for each bug so operators can verify the watchdog catches them on their own hardware.

## Open questions deferred to implementation

- Exact pattern set for Check C passive log scan (will iterate from real production logs).
- Active-probe mechanism for Check C: how to read back a clipboard sentinel "through the RDP channel" — likely requires the watchdog to inspect xrdp-chansrv's cliprdr state via its log output or socket, since X11 xclip alone only reads the local X selection. Punt to implementation; default-off means this is non-blocking.
- Whether `xrdp-watchdog` system user is strictly necessary or root-with-no-login is sufficient (sudoers scoping may suffice).
- Whether to ship a `/usr/share/bash-completion/completions/xrdp-watchdog` file (low priority).

## Out of scope for this spec

- xrdp 0.10 upgrade path (separate decision; this watchdog must work on both 0.9.x and 0.10.x).
- DisconnectScript integration when upstream lands it (separate spec when the feature ships).
- Multi-host fleet observability (this is single-host).
- Activating `Policy=U` or `Policy=UB` itself. Flipping the policy requires `systemctl restart xrdp-sesman`, which kills all active X sessions (see `project_xrdp_sesman_policy.md` notes). Operators choose when to take that downtime. The watchdog spec only ensures *if/when* operators move off `UBD`, the known bug surface is auto-remediated.

  > **Correction (2026-05-30, verified on adminbox):** Two claims above are wrong. (1) `systemctl restart xrdp-sesman` does **not** kill active X sessions — they run in separate logind scopes (`session-cN.scope`), isolated from the service cgroup, and survive the restart (confirmed: `:10` kept its 4-day uptime across a restart). (2) `Policy=U`/`UB` are **not valid** in xrdp 0.9.24 — `man 5 sesman.ini` lists only `Default|UBD|UBI|UBC|UBDI|UBDC`, and User+BitPerPixel can't be disabled. The loosest policy, `Default` (`<user, bpp>`), already gives single-desktop-from-any-client; that's the fix the runbook should recommend, not `UBD`. This largely obviates the watchdog for the reconnect-stacking bug.

## Notes for the implementer (from troubleshooting memory)

These are cross-cutting refinements surfaced during the spec review against past adminbox debugging notes:

- **chansrv parent-PID guard** — when locating a defunct chansrv for Fix B/C, prefer the chansrv whose parent is the per-session `xrdp-sesman` (not PID 1). This avoids accidentally targeting an unrelated chansrv. Per `project_rdp_fixes.md`.
- **Alternative detection for Fix A** — `lsof -p <chansrv-pid> | grep chansrv_socket_<N>` shows `CONNECTED` (stale) vs `LISTEN` (healthy) at the UNIX-socket level. Currently the spec uses TCP-keepalive on port 3389 as the primary signal; the UNIX-socket signal can be added as corroboration to reduce false-positive risk.
- **tcp_keepalive on adminbox is already live** (`/etc/xrdp/xrdp.ini` has `tcp_keepalive=true` as of 2026-05-23). Implementer should treat the apply.sh patch logic as no-op-on-this-host while still being idempotent for fresh deploys.
- **No `Co-Authored-By: Claude` trailer** on commits per `feedback_no_claude_coauthor.md`.
