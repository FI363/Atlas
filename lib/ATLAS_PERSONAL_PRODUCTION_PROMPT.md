# Atlas Personal Productionization Prompt

## Role

You are the senior software engineer responsible for turning the
existing **Atlas AI Coding Agent** repository into a polished, reliable
**personal production application**.

This is **not** a SaaS product and will not be released publicly. It is
a single-user application intended to run primarily on the owner's
Windows machine, with possible future support for other personal
devices.

Your job is to inspect the existing repository, understand its
architecture, and then implement the required improvements directly in
the codebase.

Do not rewrite the project unnecessarily. Preserve existing
functionality and architecture where practical.

------------------------------------------------------------------------

# Primary Goal

Transform the current Atlas development project from something that
requires development commands such as:

``` powershell
npm run dev
```

into a stable application that can be launched and used like a normal
desktop application.

The final experience should be approximately:

``` text
Launch Atlas
    ↓
Atlas starts its required backend/runtime components
    ↓
MCP services are initialized
    ↓
Agent becomes ready
    ↓
User can chat with Atlas
    ↓
Atlas can inspect/edit/run code and use tools
    ↓
Conversation and project state persist
    ↓
Closing Atlas cleanly shuts down child processes
```

------------------------------------------------------------------------

# Important Existing Problems

## 1. Conversation context resets

The current Atlas behavior includes:

User:

> create a text file in my current directory

Atlas:

> I can create a text file for you. What would you like to name it and
> what content should I put inside?

User:

> anything you want

Atlas unexpectedly returns its generic initial greeting again:

> Hello! I am Atlas, your AI software engineer...

and the UI shows:

> Agent Task Started

Investigate and fix the underlying cause.

Atlas must maintain conversation context across multiple messages within
the same session.

Do not fake this by hardcoding responses.

The correct lifecycle should resemble:

``` text
Session
  ↓
Agent initialized
  ↓
Message 1
  ↓
Assistant response
  ↓
History persisted
  ↓
Message 2
  ↓
Same session/context
  ↓
Agent continues the task
```

Check for:

-   Agent instances being recreated per message
-   Conversation/session IDs changing unexpectedly
-   Conversation history not being persisted
-   Assistant responses not being saved
-   Frontend state being reset
-   Backend task creation creating a new agent
-   Streaming responses not being committed to history
-   Task completion accidentally resetting the session
-   MCP initialization creating a new context
-   Race conditions in chat/task state

Trace the actual implementation before modifying it.

------------------------------------------------------------------------

# 2. Windows `spawn EINVAL`

The project previously produced:

``` text
Error: spawn EINVAL
errno: -4071
code: 'EINVAL'
syscall: 'spawn'
```

The project runs on:

``` text
Windows
Node.js v22.18.0
```

Available npm scripts include:

``` text
engine
    node backend/server.js

dev
    node scripts/start-atlas.js dev

ipad
    node scripts/start-atlas.js ipad

test:engine
    node backend/test/security.test.js && node backend/test/atlas_agent.test.js
```

Investigate every relevant process-launching path, including:

-   `child_process.spawn`
-   `spawnSync`
-   `exec`
-   `execFile`
-   `fork`
-   MCP server processes
-   Node subprocesses
-   Python processes
-   shell commands
-   npm commands
-   development-server startup
-   process cleanup

Find the exact source of the Windows `EINVAL`.

Fix the underlying cross-platform problem.

Do not simply catch and suppress the error.

Pay particular attention to:

-   Unix-only executables
-   `/bin/sh`
-   POSIX shell syntax
-   executable resolution
-   malformed argument arrays
-   invalid working directories
-   Windows path handling
-   environment variables
-   shell configuration
-   process lifecycle
-   quoting/escaping
-   detached processes

------------------------------------------------------------------------

# Personal Production Architecture

The target is a local-first architecture.

Do NOT introduce unnecessary cloud infrastructure.

A reasonable target architecture is:

``` text
                    Atlas Desktop App
                           │
              ┌────────────┴────────────┐
              │                         │
           Atlas UI                Atlas Runtime
                                        │
                     ┌──────────────────┼─────────────────┐
                     │                  │                 │
                   Agent              MCP              Local Files
                     │
                  SQLite
                     │
                  LLM API
```

The application should remain primarily local.

------------------------------------------------------------------------

# 3. Persistent local storage

Use a lightweight local database such as **SQLite** unless the
repository already has a suitable local persistence layer.

Persist at least:

-   Conversations
-   Messages
-   Sessions
-   Agent runs
-   Tool calls
-   Project metadata
-   User settings
-   Model configuration
-   MCP configuration where appropriate

The application must survive restarts without losing conversations.

For example:

``` text
Atlas data
├── atlas.db
├── logs/
├── projects/
└── configuration/
```

Do not introduce PostgreSQL or another server database unless there is a
compelling architectural reason.

------------------------------------------------------------------------

# 4. Agent lifecycle

Implement a robust agent lifecycle.

The agent should have explicit states such as:

``` text
INITIALIZING
READY
RUNNING
WAITING_FOR_INPUT
ERROR
STOPPING
STOPPED
```

A failed tool call must NOT silently recreate the entire agent.

If a tool fails:

``` text
Tool failure
    ↓
Report failure
    ↓
Preserve conversation
    ↓
Return agent to usable state
    ↓
Allow user to continue/retry
```

Do not revert to the initial Atlas greeting.

------------------------------------------------------------------------

# 5. Tool execution and permissions

Atlas is an AI coding agent and can potentially:

-   Read files
-   Create files
-   Modify files
-   Delete files
-   Execute commands
-   Run tests
-   Use Git
-   Start MCP servers
-   Access project resources

For a personal application, implement a practical local permission
system.

Suggested defaults:

``` text
Read files                  ALLOW
Create files                ALLOW
Modify files                ALLOW
Delete files                CONFIRM
Run shell commands          CONFIRM
Install packages            CONFIRM
Access outside workspace    CONFIRM
Destructive operations      CONFIRM
```

The system should make it clear when Atlas is about to perform a
potentially destructive operation.

Do not make the permission system so restrictive that Atlas becomes
unusable.

------------------------------------------------------------------------

# 6. Workspace management

Atlas should understand the concept of a project/workspace.

A workspace should have:

-   Root directory
-   Project name
-   Git repository information when available
-   File access boundaries
-   Project-specific settings
-   Conversation association

The agent should know which directory is currently active.

Path handling must work correctly on Windows.

Use robust path utilities rather than manual string concatenation.

------------------------------------------------------------------------

# 7. MCP management

Atlas has MCP support.

Make MCP lifecycle reliable:

``` text
Atlas startup
    ↓
Load MCP configuration
    ↓
Start required MCP servers
    ↓
Verify connectivity
    ↓
Expose available tools
```

On shutdown:

``` text
Atlas closing
    ↓
Stop agent
    ↓
Stop MCP servers
    ↓
Clean up child processes
    ↓
Exit
```

Handle MCP crashes without destroying the conversation.

If an MCP process fails:

-   Report the actual error
-   Record the failure in logs
-   Attempt a reasonable restart when appropriate
-   Preserve agent/session state
-   Do not silently reset the conversation

------------------------------------------------------------------------

# 8. Configuration

Create a proper settings/configuration system.

At minimum support:

``` text
LLM provider
API key
Model
Temperature / generation settings where supported
Workspace
MCP configuration
Permission settings
Logging level
```

Never hardcode API keys into source code.

Use a secure local configuration mechanism appropriate for a personal
Windows application.

Do not commit secrets to Git.

------------------------------------------------------------------------

# 9. Logging and diagnostics

Create useful local logs.

Suggested structure:

``` text
logs/
├── atlas.log
├── agent.log
├── mcp.log
└── errors.log
```

Use structured logging where practical.

Log:

-   Application startup
-   Application shutdown
-   Agent lifecycle transitions
-   Session IDs
-   Agent run IDs
-   Tool calls
-   MCP lifecycle
-   Subprocess failures
-   LLM failures
-   Important errors

Do NOT blindly log:

-   API keys
-   Passwords
-   Tokens
-   Private credentials
-   Sensitive file contents

Add enough diagnostic information to reproduce failures.

------------------------------------------------------------------------

# 10. Error handling

Atlas should fail gracefully.

Handle:

-   LLM API failures
-   Network failures
-   MCP failures
-   Child-process failures
-   Invalid paths
-   Missing executables
-   Permission failures
-   Tool timeouts
-   malformed tool results
-   malformed model responses
-   application shutdown during an active task

Errors shown to the user should be understandable.

Developer logs should contain the technical details.

------------------------------------------------------------------------

# 11. Task cancellation

Implement proper task cancellation if the current architecture allows
it.

The user should be able to stop a long-running agent task.

Cancellation should:

-   Stop the current agent operation
-   Stop/abort active tools where possible
-   Clean up child processes
-   Preserve conversation history
-   Return Atlas to a usable state

Avoid leaving orphaned processes behind.

------------------------------------------------------------------------

# 12. Desktop application packaging

Determine what framework the existing Atlas frontend uses and choose the
most appropriate packaging strategy.

Possible approaches include:

-   Electron
-   Tauri
-   Flutter desktop
-   Another existing desktop wrapper

Do NOT migrate frameworks unless there is a strong reason.

The final application should ideally launch without requiring the user
to manually run multiple terminal commands.

Target experience:

``` text
Atlas.exe
    ↓
Launch
    ↓
Backend/runtime starts
    ↓
MCP initializes
    ↓
UI becomes ready
```

The development workflow should remain available separately.

For example:

``` text
Development:
npm run dev

Production:
Atlas.exe
```

------------------------------------------------------------------------

# 13. Startup and shutdown

Implement reliable startup orchestration.

Startup should:

1.  Load configuration
2.  Initialize local storage
3.  Start required backend/runtime
4.  Start required MCP services
5.  Verify services
6.  Initialize agent/session infrastructure
7.  Display the UI
8.  Mark Atlas as READY

Shutdown should:

1.  Stop accepting new tasks
2.  Gracefully stop the agent
3.  Cancel active operations
4.  Stop MCP processes
5.  Close database connections
6.  Flush logs
7.  Exit cleanly

Make startup/shutdown platform-aware.

------------------------------------------------------------------------

# 14. UI polish

Do not redesign the entire UI unnecessarily.

Improve the existing interface where needed so that the application
clearly communicates:

-   Agent status
-   Running task
-   Tool execution
-   Waiting for user input
-   Errors
-   Completion
-   Cancellation
-   MCP status

Avoid showing confusing messages such as:

``` text
Agent Task Started
```

when the user simply sent a conversational follow-up.

The UI should distinguish between:

``` text
Normal conversation
```

and:

``` text
Autonomous agent execution
```

------------------------------------------------------------------------

# 15. Testing

Add or improve automated tests.

At minimum test:

## Conversation continuity

``` text
Message 1:
create a text file in my current directory

Message 2:
anything you want
```

Verify the second message retains the context of the first.

## Three-turn context

Test:

``` text
User → task
Atlas → clarification
User → clarification
Atlas → execution
User → modification
Atlas → modification
```

## Restart persistence

1.  Create conversation
2.  Close Atlas
3.  Reopen Atlas
4.  Verify conversation still exists

## Tool failure recovery

1.  Trigger a tool failure
2.  Verify error is shown
3.  Send another message
4.  Verify conversation continues normally

## MCP failure recovery

1.  Start MCP
2.  Use MCP tool
3.  Terminate MCP process
4.  Verify failure is reported
5.  Restart/recover MCP
6.  Verify conversation remains intact

## Windows process execution

Verify the actual Atlas startup path works on Windows without:

``` text
spawn EINVAL
```

## Shutdown

Verify no orphaned Node/MCP processes remain after Atlas closes.

------------------------------------------------------------------------

# 16. Development vs production configuration

Maintain separate modes.

Development:

``` text
npm run dev
```

Production:

``` text
Packaged Atlas application
```

Production builds should:

-   Disable development-only debugging
-   Use production configuration
-   Use proper logging
-   Use bundled/static frontend assets
-   Start required runtime components automatically
-   Avoid relying on the developer's PATH where possible

------------------------------------------------------------------------

# 17. Security for a personal application

This is not a public SaaS, but still protect the machine.

At minimum:

-   Do not expose the local agent server publicly
-   Bind local services to localhost unless external access is
    explicitly required
-   Protect API keys
-   Validate tool arguments
-   Prevent accidental traversal outside the intended workspace where
    appropriate
-   Require confirmation for destructive commands
-   Avoid executing arbitrary model-generated commands without a
    permission mechanism
-   Do not expose debugging endpoints unnecessarily

------------------------------------------------------------------------

# 18. Do not over-engineer

This is critical.

This application is for one person.

Do NOT introduce:

-   Kubernetes
-   Microservices everywhere
-   Cloud databases
-   User accounts
-   OAuth
-   Billing
-   Stripe
-   SaaS multi-tenancy
-   CDN infrastructure
-   Load balancing
-   Enterprise authentication
-   Public APIs
-   Complex distributed systems

Prefer:

``` text
Local
Simple
Reliable
Maintainable
Fast
```

over:

``` text
Distributed
Complex
Cloud-dependent
Over-engineered
```

------------------------------------------------------------------------

# 19. Implementation process

Before editing:

1.  Inspect the repository structure.
2.  Identify the frontend architecture.
3.  Identify the backend architecture.
4.  Identify agent initialization.
5.  Identify conversation/session state.
6.  Identify MCP management.
7.  Identify subprocess execution.
8.  Identify current persistence.
9.  Identify startup scripts.
10. Identify existing tests.

Then produce a short internal implementation plan.

After that, implement the changes.

Do not ask me to manually fix obvious issues one by one unless a
decision genuinely requires my input.

------------------------------------------------------------------------

# 20. Verification requirement

After implementation, actually test the application.

Do not merely state that the code "should work."

Run the relevant tests and startup commands.

Verify:

-   Atlas starts
-   Conversations persist
-   Multi-turn context works
-   Tools work
-   MCP works
-   Windows process spawning works
-   Errors recover correctly
-   Shutdown works
-   No obvious orphan processes remain

If something cannot be tested in the current environment, explicitly
state what could not be verified and why.

------------------------------------------------------------------------

# Final deliverable

At the end, report:

## Root causes found

Explain the actual causes of the existing conversation-reset and
`spawn EINVAL` problems.

## Changes made

List every modified/created file and summarize its purpose.

## Production architecture

Briefly describe the final architecture.

## Tests performed

List the tests and their results.

## Remaining issues

List anything that still requires manual setup or cannot be verified in
the current environment.

## How to run

Provide the exact development and production commands.

The final result should be a **stable personal Atlas application**, not
a prototype that merely happens to run.
