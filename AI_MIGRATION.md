# Atlas AI Subsystem Migration & Audit Report

**Date:** 2026-08-19  
**Status:** Phase 1 Audit Complete  
**Target:** Rebuild AI subsystem into a clean, modular Agent Runtime with interchangeable model providers.

---

## 1. Executive Summary

The current Atlas AI subsystem has evolved into a mix of disjointed mechanisms:
1. A monolithic ~1,100-line dispatcher (`ai_providers.js`) that hardcodes request formats and string manipulation for multiple models.
2. A rule-based regex fallback agent that mimics agent behavior through static string matching.
3. An `AgentLoop` that is tightly coupled to specific provider response formats and ad-hoc diffing logic.
4. Separate code paths for simple chat (`ai_prompt`) versus multi-turn tool calling (`agent_start`).

This document maps out the current architecture, identifies reusable host IDE APIs, specifies obsolete components, defines the replacement targets for the new **Agent Runtime**, and outlines the phased migration strategy.

---

## 2. Dependency Map (Current vs. Target)

### Current Architecture
```text
Flutter UI (ai_panel.dart)
    ↓ WebSocket (ai_prompt / agent_start)
server.js
    ↓
ai_providers.js (monolithic if/else) ──→ Hardcoded prompt regexes / Fake built-in responses
    ↓
agent_loop.js
    ↓
mcp/tools/*.js ──→ Direct FS/Terminal calls
```

### Target Modular Architecture
```text
┌────────────────────────────────────────────────────────┐
│                   EXISTING IDE HOST                    │
│ Editor  │  Explorer  │  Terminal  │  Git  │  Workspace │
└───────────────────────────┬────────────────────────────┘
                            │
                      IDE Tool Adapter
                            │
┌───────────────────────────▼────────────────────────────┐
│                  NEW AGENT RUNTIME                     │
│                                                        │
│  AgentRuntime (Lifecycle & ReAct Loop)                 │
│  ├── EventBus (Typed runtime events)                   │
│  ├── SessionManager (State surviving model switches)   │
│  ├── ContextManager (Targeted retrieval & compaction)  │
│  ├── PermissionManager (READ, WRITE, EXEC, DESTRUCT)   │
│  └── ToolRegistry (Native IDE tools + Future MCP)      │
│                                                        │
│  ProviderManager                                       │
│  ├── GeminiProvider (Milestone 1)                      │
│  ├── ClaudeProvider                                    │
│  ├── OpenAIProvider                                    │
│  ├── OpenRouterProvider                                │
│  ├── LocalProvider (Ollama / On-Device)                │
│  └── RemoteProvider (Colab / Custom API)               │
└────────────────────────────────────────────────────────┘
```

---

## 3. Inventory of AI-Related Files

| File Path | Role | Migration Disposition |
| :--- | :--- | :--- |
| `backend/engine/ai_providers.js` | Monolithic LLM client & regex rule agent | **OBSOLETE** — Replace with modular `ProviderManager` and dedicated provider classes. |
| `backend/engine/agent/agent_loop.js` | ReAct agent loop | **REPLACE** — Refactor into clean `AgentRuntime` using standard provider & tool interfaces. |
| `backend/engine/agent/context_builder.js` | System prompt & context assembler | **REPLACE** — Refactor into provider-agnostic `ContextManager`. |
| `backend/engine/agent/context_manager.js` | Token budgeting & conversation compaction | **PRESERVE & ADAPT** — Integrate into new `ContextManager`. |
| `backend/engine/agent/conversation_session.js` | Multi-turn session state store | **PRESERVE & ADAPT** — Upgrade to `SessionManager` supporting model switching. |
| `backend/engine/agent/cancellation_token.js` | Cooperative cancellation token | **PRESERVE** — Reusable across all runtime operations. |
| `backend/engine/agent/diff_engine.js` | Unified diff generation | **PRESERVE** — Used for diff previews before tool writes. |
| `backend/engine/agent/patch_engine.js` | Patch verification & application | **PRESERVE & INTEGRATE** into tool write pipeline. |
| `backend/engine/mcp/registry.js` | MCP Tool registration | **REPLACE** — Merge into unified `ToolRegistry`. |
| `backend/engine/mcp/tools/*.js` | MCP tool implementations | **REFACTOR** — Adapt into `IDEToolAdapter` exposing clean native tools. |
| `backend/engine/permissions.js` | Policy gatekeeper | **UPGRADE** — Standardize on `READ`, `WRITE`, `EXECUTE`, `DESTRUCTIVE` tiers. |
| `backend/server.js` | WebSocket server & message dispatch | **ADAPT** — Wire WebSocket events to `AgentRuntime` and `EventBus`. |
| `lib/state/agent_state.dart` | Flutter agent state container | **ADAPT** — Connect to new runtime event stream. |
| `lib/state/atlas_settings.dart` | Persistent user configuration | **PRESERVE** — Already streamlined for OpenRouter, Local, Custom, Gemini. |
| `lib/widgets/ai_panel.dart` | Frontend AI & Agent chat panel | **PRESERVE UI / REWIRE** — Connect to `AgentRuntime` events without internal agent logic. |
| `lib/services/engine_client.dart` | Frontend WebSocket protocol handler | **PRESERVE & EXPAND** — Support new typed runtime events. |
| `lib/services/local_inference_service.dart` | On-device llama.cpp bridge (iOS) | **PRESERVE** — Standalone local runtime adapter for `LocalProvider`. |

---

## 4. Reusable Host IDE APIs

The new AI subsystem will strictly act as a client of the host IDE. The following existing IDE backend modules provide stable, native capabilities to be wrapped by the `IDEToolAdapter`:

1. **Filesystem APIs (`backend/engine/filesystem.js`)**:
   - `readFile(workspaceRoot, relPath)`
   - `writeFile(workspaceRoot, relPath, content)`
   - `createFile(workspaceRoot, relPath)`
   - `deleteFile(workspaceRoot, relPath)`
   - `listDirectory(workspaceRoot, relPath)`
   - `buildTree(dirPath)`
2. **Terminal & Process Execution (`backend/engine/terminal.js`)**:
   - `createTerminal({ cwd, onData, onExit })`
   - `executeCommand(command, cwd, callback)`
   - `killProcess(pid)`
3. **Search & Indexing (`backend/engine/search.js`)**:
   - `searchCode(query, cwd, options, callback)` (powered by ripgrep)
   - `findFiles(pattern, cwd, callback)`
4. **Git Version Control (`backend/engine/git.js`)**:
   - `getGitStatus(cwd, callback)`
   - `getGitDiff(cwd, path, staged, callback)`
   - `runGit(args, cwd, callback)`
5. **Workspace Management (`backend/engine/workspace.js`)**:
   - `loadPersistedWorkspaceRoot()`
   - `persistWorkspaceRoot(root)`

---

## 5. Obsolete Components & Anti-Patterns to Eliminate

1. **Fake Built-In Agent Regexes**:
   - *Problem:* Hardcoded strings checking `prompt.includes('explain')` or `prompt.includes('bug')` return static mocked answers.
   - *Fix:* Remove mocked logic. Real agency comes from `Model + Tools + Agent Loop`.
2. **Monolithic Provider Branching**:
   - *Problem:* `if (provider === 'gemini') ... else if (provider === 'anthropic') ...` scattered across multiple dispatch functions.
   - *Fix:* Strict `ModelProvider` abstract interface. Adding a new provider requires adding one file in `providers/` and zero changes to the runtime.
3. **Disjointed Chat vs. Agent Loops**:
   - *Problem:* `ai_prompt` bypasses tools, while `agent_start` runs a separate flow.
   - *Fix:* Single unified `AgentRuntime` where a single-turn question is simply an agent session with 0 tool calls.
4. **Ad-Hoc Tool Schemas**:
   - *Problem:* Tools defined in multiple places with incompatible JSON structures.
   - *Fix:* Central `ToolRegistry` where every tool defines a JSON Schema `inputSchema` and permission level.

---

## 6. Target Replacement Specifications

### A. Agent Runtime (`backend/engine/runtime/agent_runtime.js`)
- Manages the execution loop:
  1. Receive request & load session.
  2. Assemble targeted context via `ContextManager`.
  3. Send request to active `ModelProvider`.
  4. If text response → emit message and finish.
  5. If tool call → check permissions via `PermissionManager` → execute via `ToolRegistry` → record result → continue loop.
- Core methods: `start(task, options)`, `continue(input)`, `cancel()`, `resume()`.
- Emits events through `EventBus`: `agent.started`, `agent.message`, `agent.tool_call`, `agent.tool_result`, `agent.file_changed`, `agent.permission_requested`, `agent.completed`, `agent.failed`, `agent.cancelled`.

### B. Model Provider Interface (`backend/engine/providers/base_provider.js`)
- Interface definition:
  - `id`: string
  - `name`: string
  - `models`: string[]
  - `capabilities`: `{ streaming: bool, toolCalling: bool, vision: bool }`
  - `send({ messages, tools, options, cancellationToken })`
  - `stream({ messages, tools, options, cancellationToken, onToken, onToolCall, onComplete })`
- **Initial Implementation:** `GeminiProvider` using Google Gemini 2.0 / 2.5 Flash API with native function calling and SSE streaming.

### C. IDE Tool Adapter (`backend/engine/tools/ide_tool_adapter.js`)
- Exposes clean tools mapped to host IDE:
  - `filesystem.read` (Permission: READ)
  - `filesystem.write` (Permission: WRITE)
  - `filesystem.list` (Permission: READ)
  - `filesystem.delete` (Permission: DESTRUCTIVE)
  - `search.files` (Permission: READ)
  - `search.text` (Permission: READ)
  - `terminal.execute` (Permission: EXECUTE)
  - `terminal.kill` (Permission: EXECUTE)
  - `git.status` (Permission: READ)
  - `git.diff` (Permission: READ)
  - `ide.get_diagnostics` (Permission: READ)
  - `ide.get_open_files` (Permission: READ)

### D. Permission Manager (`backend/engine/permissions/permission_manager.js`)
- Tiers: `READ`, `WRITE`, `EXECUTE`, `DESTRUCTIVE`.
- User Policies: `always_allow`, `ask_every_time`, `never_allow`, `approve_write_and_exec`.

### E. Session Manager (`backend/engine/session/session_manager.js`)
- Holds `AgentSession` state: `sessionId`, `task`, `providerId`, `modelId`, `conversation`, `toolHistory`, `contextState`, `status`.
- Supports switching model / provider mid-conversation without loss of workspace context or session history.

---

## 7. Migration Risks & Mitigations

| Risk | Impact | Mitigation Strategy |
| :--- | :--- | :--- |
| **WebSocket Contract Breakage** | Frontend AI Panel fails to render messages or tool calls. | Maintain backward-compatible WebSocket message translation in `server.js` while adding new typed runtime events. |
| **Infinite Agent Tool Loops** | Model repeatedly runs failing commands or reads same file. | Enforce `MAX_ITERATIONS` (default 25), `MAX_TOOL_CALLS` (50), and cycle detection for duplicate consecutive tool calls. |
| **Context Window Exhaustion** | Model requests fail due to exceeding token limit. | Implement token budgeting and compaction in `ContextManager` before each model request. |
| **Permission Deadlocks** | Agent loop hangs waiting for UI approval that is dismissed. | Implement timeout and cancellation handlers on all pending permission promises. |

---

## 8. Next Phase: Phase 2 Boundary & Phase 3 Agent Runtime

Phase 1 audit is complete. The system is ready to proceed to Phase 2 (defining IDE/AI boundary) and Phase 3 (implementing `AgentRuntime` and `GeminiProvider`).
