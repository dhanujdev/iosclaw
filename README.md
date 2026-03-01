# iosclaw

Foundation scaffolding for the iOS Autonomous Agent.

## Structure

- `iosclaw/App/`: app entry point and scene wiring
- `iosclaw/Core/Config/`: runtime configuration and environment lookups
- `iosclaw/Core/Agent/`: observe-plan-act orchestration state
- `iosclaw/Core/Memory/`: SwiftData models for persistent memory, pending approvals, and approval audit records
- `iosclaw/Core/Runtime/`: background task scheduling boundary
- `iosclaw/Core/Security/`: approval and biometric gatekeeping
- `iosclaw/Core/Tools/`: fixed secure tool registry
- `iosclaw/Features/Chat/`: initial UI shell and view model
- `iosclaw/Services/Agent/`: agent-facing service boundary and Gemini transport

## Gemini Configuration Pattern

The app now includes a direct Gemini HTTP client. Use one of these inputs:

- Add `GEMINI_API_KEY` to the Xcode scheme environment variables for local simulator runs.
- Or add a `GEMINI_API_KEY` entry to the app's Info.plist data once you move to a managed build configuration.
- Optionally set `GEMINI_MODEL` to override the default `gemini-2.0-flash`.
- Optionally set `GEMINI_BASE_URL` if you need a proxy or gateway.
- Set `ENABLE_CLOUDKIT_SYNC=1` to request a CloudKit-backed SwiftData store when your app has the required iCloud entitlements.

`AppConfiguration.live` resolves the first non-empty value from the environment or Info.plist so the UI and service layer never read secrets directly.
If CloudKit is requested but unavailable, the app now falls back to the local SwiftData store instead of failing at launch.

## Current Delivery State

- Phase 1: app shell, configuration path, and Gemini transport boundary are in place.
- Phase 2: the agent planner, SwiftData memory schema, and persistent chat thread are scaffolded.
- Phase 3: the secure tool registry is defined and simple command-driven web, files, and reminders execution is wired.
- Phase 4: approval queueing, approval audit persistence, background execution coordinators, and a CloudKit-ready SwiftData container path are added as integration boundaries.

## Tool Commands

- `search: your query`
- `read file: notes.txt`
- `write file: notes.txt | content to save`
- `remind: Follow up on CloudKit sync`

`write file:` commands are treated as high-risk. They are queued for approval in the chat UI, and approvals or denials are stored in SwiftData-backed audit history so the record survives relaunches.
