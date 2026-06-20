# Return to Agent Session Plan

## Goal

When an agent notification speaks, FlowOSS should remember where that agent session came from. The user should then be able to quickly jump back to that terminal/app/session from wherever they are.

Example flow:

1. User opens Claude Code in a terminal.
2. User dictates a prompt with GingerPaw.
3. User switches to Chrome, Slack, or another app.
4. Claude finishes and FlowOSS speaks: "Claude finished. Tests passed."
5. User presses a shortcut or clicks an action.
6. FlowOSS brings the relevant terminal/session back to the front.

## Product Shape

Feature name ideas:

- Return to Agent
- Jump Back
- Open Last Agent
- Focus Agent Session

Primary user-facing behavior:

- FlowOSS speaks agent status.
- FlowOSS stores the latest agent source.
- User can return to that source through:
  - menu bar item
  - global hotkey
  - notification action
  - app UI button

## MVP Scope

The MVP should not try to perfectly target every terminal tab. Start with reliable app/process activation.

MVP behavior:

1. `flowoss notify` receives Claude hook payload.
2. CLI captures useful source context:
   - current working directory
   - process ID
   - parent process ID
   - timestamp
   - event kind
   - optional Claude session ID from payload
3. FlowOSS app stores this as the latest agent notification source.
4. User clicks "Return to Last Agent" from menu bar.
5. FlowOSS activates the originating terminal app or process.

MVP fallback behavior:

- If exact process activation fails, activate Terminal/iTerm/Warp/Cursor by bundle id.
- If app activation fails, open the working directory in Finder.
- If there is no known source, disable the button or show "No agent session yet."

## Non-MVP Scope

Save these for later:

- Exact Terminal.app tab targeting.
- Exact iTerm2 session targeting.
- Warp-specific targeting.
- Cursor/VS Code integrated terminal targeting.
- Multi-agent session list.
- "Return to the session that mentioned project X."
- Voice command: "take me back to Claude."

## Data Model

Add a model similar to:

```swift
public struct AgentSessionSource: Equatable, Sendable, Codable, Identifiable {
    public let id: UUID
    public let agent: AgentKind
    public let eventKind: AgentEventKind
    public let receivedAt: Date
    public let processID: Int32?
    public let parentProcessID: Int32?
    public let appBundleID: String?
    public let appName: String?
    public let terminalKind: TerminalKind
    public let workingDirectory: URL?
    public let sessionID: String?
    public let spokenSummary: String?
}
```

Supporting enums:

```swift
public enum AgentKind: String, Codable, Sendable {
    case claude
    case codex
    case unknown
}

public enum AgentEventKind: String, Codable, Sendable {
    case stop
    case notification
    case subagentStop
    case error
    case unknown
}

public enum TerminalKind: String, Codable, Sendable {
    case terminal
    case iTerm
    case warp
    case cursor
    case vsCode
    case unknown
}
```

## Capturing Source Context

The CLI should capture what it can at hook time.

Useful fields:

```sh
pwd
echo $TERM_PROGRAM
echo $TERM_SESSION_ID
echo $ITERM_SESSION_ID
echo $__CFBundleIdentifier
echo $PPID
```

Also inspect the process tree if needed:

```sh
ps -o pid,ppid,comm= -p "$PPID"
```

For MVP, do not over-invest in perfect process-tree detection. Store best-effort context and make the return action layered.

## Return Strategy

Implement return behavior in layers.

### Layer 1: Activate Process

If `processID` or `parentProcessID` maps to a running app:

```swift
NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows])
```

### Layer 2: Activate App By Bundle ID

Known bundle IDs:

```text
com.apple.Terminal
com.googlecode.iterm2
dev.warp.Warp-Stable
com.todesktop.230313mzl4w4u92
com.microsoft.VSCode
```

Note: verify Cursor bundle ID on the user's machine before hardcoding.

### Layer 3: Open Working Directory

If the app cannot be focused:

```swift
NSWorkspace.shared.open(workingDirectory)
```

### Layer 4: Terminal-Specific Exact Targeting

Later:

- Terminal.app AppleScript
- iTerm2 AppleScript
- Warp URL/API if available
- Cursor/VS Code CLI if available

## UI

Add a menu bar item:

```text
Return to Last Agent
```

State:

- Enabled when there is a recent `AgentSessionSource`.
- Disabled when no agent notification has been received.

Optional detail line:

```text
Last agent: Claude in FlowOSS, 2 min ago
```

Add a settings toggle:

```text
Enable Return to Agent shortcut
```

Add later:

- global shortcut recorder
- notification action button
- in-app Agent Notifications history

## Hotkey Design

Possible shortcut options:

- `Option + Space`
- `Control + Option + Space`
- double-tap GingerPaw hotkey
- menu bar only for MVP

Recommendation:

Start with menu bar only. Then add a global hotkey once the return behavior is proven.

Avoid overloading the dictation hold hotkey in the first version because press/release timing can get confusing.

## Notification Action

When FlowOSS speaks, also show a macOS notification:

```text
Claude finished. Tests passed.
[Open Session]
```

Clicking the notification or action should call:

```swift
returnToLatestAgentSession()
```

This is probably the best UX after menu bar support.

## Implementation Steps

1. Add `AgentSessionSource` model to the agent notification module.
2. Extend `flowoss notify` to include source context with every event.
3. Parse Claude hook payload plus environment/process context.
4. Send source context to the FlowOSS app through the existing local IPC path.
5. Store `latestAgentSessionSource` in the app runtime/controller.
6. Implement `AgentSessionReturner` service.
7. Add menu bar item: `Return to Last Agent`.
8. Wire menu item to `AgentSessionReturner.return(to:)`.
9. Add user-visible failure fallback:
   - activate known terminal app
   - open working directory
10. Add tests for source parsing and return strategy selection.

## Testing Plan

Manual:

1. Open Claude Code in Terminal.app.
2. Trigger a hook event.
3. Switch to another app.
4. Use menu bar `Return to Last Agent`.
5. Confirm Terminal.app activates.

Repeat with:

- iTerm2
- Warp
- Cursor terminal

Automated:

- Unit-test hook payload parsing.
- Unit-test environment capture mapping.
- Unit-test return strategy order:
  - process activation preferred
  - bundle activation fallback
  - working directory fallback

## Risks

- Exact terminal tab targeting is inconsistent across terminal apps.
- GUI app activation may require different behavior depending on whether the process is a terminal shell, Terminal.app, or an integrated terminal inside an editor.
- Claude hook payload may not include enough session identity, so environment/process capture matters.
- Some apps may not expose stable AppleScript or URL APIs.

## Recommended First Version

Build only this:

- Store latest agent source.
- Menu bar item: `Return to Last Agent`.
- Activate source app or parent app.
- Fallback to opening working directory.

That gives the user the core feeling:

> "FlowOSS told me Claude is done, and one click takes me back."

