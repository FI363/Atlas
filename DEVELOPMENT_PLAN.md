# Atlas development plan

## Guiding constraint

Atlas is a trusted-device remote development environment. The engine can edit
files and run developer commands, so it must be safe to run on a laptop and
deliberately configured before it is reachable over a network.

## Delivery sequence

### 1. Secure, reliable engine foundation — complete

- Bind to loopback by default and require a shared engine token.
- Make the LAN workflow generate or accept a strong token and pass it to both
  the engine and Flutter client without committing secrets.
- Add connection/authentication regression coverage and document the trust
  boundary.
- Keep arbitrary shell access explicitly limited to authenticated, trusted
  clients; do not expose the engine directly to the public internet.

**Exit criteria:** a fresh `npm run dev` is local-only; `npm run ipad` starts
with a unique session token; an engine started by itself refuses to run without
an explicit token.

### 2. Terminal and connection experience

- Replace single-command execution with per-session PTY terminals, including
  resize and input events. **Complete.**
- Add reconnect with bounded backoff, clear offline state, and reload of
  workspace/editor state after reconnecting. **Complete.**
- Preserve process ownership per WebSocket session and clean up on disconnect.

**Exit criteria:** interactive tools work from iPad and a Wi-Fi interruption
does not require restarting Atlas.

### 3. Workspace and Git workflows

- Add a workspace allow-list and recent-workspace management. **Complete.**
- Surface Git diff, staged files, branches, pull/push errors, and conflict
  status in the UI. **Per-file diff review is complete.**
- Add integration tests using temporary workspaces and repositories.

### 4. Editor essentials

- Add language-aware highlighting, find/replace, keyboard shortcuts, dirty
  tabs, autosave/recovery, and mobile-friendly selection controls. **Find/
  replace, keyboard shortcuts, dirty tabs, and debounced Auto Save are
  complete; highlighting, cross-session draft recovery, and touch-specific
  selection controls remain.**
- Split connection, workspace, editor, terminal, Git, and agent state behind
  focused controllers.

### 5. Agent workflow

- Keep tool permissions and diff approval as the default policy.
- Add task history, cancellation cleanup, test-run summaries, and a clear
  review/apply flow before commits.
- Never persist provider credentials in source control or send them to an
  untrusted engine.

### 6. Remote deployment and iPad polish

- Put a TLS-terminating authenticated gateway in front of any non-LAN engine.
- Add engine pairing, device/session revocation, observability, and backups.
- Finish iPad layout, touch/keyboard behavior, accessibility, and offline UX.

## Current implementation checkpoint

Step 1 is complete. Steps 2–6 remain intentionally staged so each is usable
and testable before the next expands the system's surface area. The next
implementation increment is the PTY terminal and reconnection foundation.
