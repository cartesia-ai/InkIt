# Inksper Plan

## Goal

Build a macOS app that behaves like Wispr Flow / Willow Voice for a single dictation workflow:

- User holds a configurable global hotkey.
- App records microphone audio while the key is held.
- Audio streams to Cartesia STT in real time.
- No text is inserted while recording is in progress.
- When the user releases the key, the app finalizes transcription and pastes the full transcript into the currently focused text field in the frontmost app.

There is no post-processing LLM step. The pasted text is the raw STT output.

## Cartesia Integration

Based on the Ink 2 docs provided for this project:

- Model family: `ink-2`
- Preview snapshot currently documented: `ink-2-2026-04-15`
- Latest beta alias: `ink-2-latest`
- Recommended production default for this app: `ink-2`
- API reference to follow: `/api-reference/stt/turns/websocket`

Planned model behavior:

- use `ink-2` by default so the app tracks the latest stable Ink 2 snapshot
- allow an advanced setting to pin a specific snapshot later if needed

Expected session behavior:

1. Open the turn-based STT WebSocket for Ink 2
2. Stream microphone audio continuously while the hotkey is held
3. Keep transcript updates internal only while recording
4. On hotkey release, explicitly end the user turn / finalize the stream using the turns WebSocket protocol
5. Wait for the completed transcript for that turn
6. Paste the completed text once, then close or recycle the session as appropriate

Implementation note:

- this project should follow the Ink 2 turn-detection API semantics rather than the older non-turn-specific streaming endpoint
- exact message names and finalization commands should be taken from the Ink 2 turns WebSocket reference during implementation

## App Shape

Build this as a native SwiftUI macOS app with AppKit integrations where needed.

Primary app form:

- Menu bar app for fast access
- Small settings window for configuration
- No main editor UI required

Core responsibilities:

1. Global hotkey capture
2. Press-to-record audio capture
3. Streaming STT client for Cartesia
4. Delayed paste into the active app
5. Permissions and onboarding
6. Lightweight status reporting in the menu bar/settings UI

## Major Components

### 1. App State / Coordinator

Central coordinator object to manage:

- idle
- recording
- finalizing
- pasting
- error

Responsibilities:

- start dictation on hotkey press
- stop dictation on hotkey release
- collect latest transcript internally without exposing it to the target app
- trigger paste only after finalization completes

### 2. Global Hotkey Manager

Use a macOS global hotkey implementation based on Carbon hotkey APIs.

Requirements:

- user-configurable key + modifiers
- capture both key-down and key-up
- ignore key repeat
- survive focus changes between apps

Reason for this choice:

- standard event monitors are weaker for reliable global press/release semantics
- Carbon hotkeys still provide the cleanest macOS-native way to observe both press and release for a registered shortcut

### 3. Audio Capture Pipeline

Use `AVAudioEngine` for microphone capture.

Requirements:

- start recording immediately on hotkey press
- stop capture immediately on hotkey release
- convert microphone input to mono `pcm_s16le` at `16000` Hz
- stream small chunks to Cartesia for low latency

Suggested implementation:

- install an input tap on the microphone bus
- use `AVAudioConverter` to resample and convert incoming buffers
- push encoded bytes to the WebSocket client on a dedicated queue

### 4. Cartesia Streaming Client

Use `URLSessionWebSocketTask`.

Responsibilities:

- connect with API key, model ID, and Ink 2 turn-based session parameters
- stream binary PCM audio
- receive transcript events
- handle turn completion and error messages
- keep an internal "best transcript so far"

Transcript handling rule:

- partial transcripts may update continuously
- the app should not type or paste partials
- only the final resolved transcript for the completed turn should be emitted into the target text field after release

### 5. Paste Engine

Use accessibility-based event synthesis to paste into the frontmost app.

Recommended behavior:

- save current clipboard contents
- write final transcript to the pasteboard
- synthesize `Cmd+V`
- restore the previous clipboard contents after a short delay

Why paste instead of simulated typing:

- aligns with the requirement that nothing appears until completion
- avoids a long stream of keystroke events
- behaves better for multi-word transcripts

Dependencies:

- app must request Accessibility permission

### 6. Settings / Onboarding UI

Minimal but polished settings surface with:

- Cartesia API key field
- hotkey recorder
- permission status for Microphone and Accessibility
- test button for recording/paste flow
- current status text such as `Idle`, `Recording`, `Finalizing`, or error state

Store settings in `UserDefaults` initially.

## Permissions

The app needs:

- Microphone permission for recording
- Accessibility permission for paste event synthesis

Plan:

- include `NSMicrophoneUsageDescription` in the app plist
- prompt for Accessibility trust using `AXIsProcessTrustedWithOptions`
- show clear UI when permissions are missing
- block dictation start until required permissions are available

## Dictation Lifecycle

1. User presses the configured hotkey
2. App validates permissions and API key
3. App opens Cartesia WebSocket
4. App starts microphone capture
5. App streams audio while key remains held
6. App receives transcript updates internally only
7. User releases hotkey
8. App stops audio capture
9. App signals turn end using the Ink 2 turns protocol
10. App waits for the final transcript for that turn
11. App closes or resets the WebSocket session according to the API behavior
12. App pastes the final transcript into the frontmost text target
13. App returns to idle

## Error Handling

Handle these cases explicitly:

- missing API key
- microphone permission denied
- accessibility permission denied
- WebSocket connection failure
- Cartesia authentication failure
- empty transcript after release
- audio conversion failure
- paste failure because no valid focused target exists

UX rule:

- failures should show in the menu/settings UI
- failures should never paste partial or corrupted text

## Initial File / Module Layout

Suggested structure:

- `InksperApp.swift`
- `AppCoordinator.swift`
- `HotkeyManager.swift`
- `AudioCaptureService.swift`
- `AudioPCMConverter.swift`
- `CartesiaStreamingClient.swift`
- `PasteService.swift`
- `PermissionsService.swift`
- `SettingsStore.swift`
- `SettingsView.swift`

## Delivery Sequence

### Phase 1: Project Scaffold

- create Xcode macOS app project
- configure plist, signing placeholders, and menu bar entry
- add settings persistence

### Phase 2: Input + Recording

- implement global hotkey registration
- implement microphone capture
- verify hold-to-record / release-to-stop behavior locally

### Phase 3: Cartesia Streaming

- implement WebSocket client
- stream 16 kHz PCM data to Cartesia
- collect internal transcript state
- verify Ink 2 turn completion behavior on release

### Phase 4: Paste Flow

- implement pasteboard swap + `Cmd+V`
- verify transcript appears only after release
- restore clipboard safely

### Phase 5: UX + Hardening

- add onboarding and permission prompts
- add hotkey recorder UI
- improve error states and retry behavior
- test common apps like Notes, TextEdit, Slack, and browser textareas

## Non-Goals For V1

- no LLM cleanup, rewriting, punctuation correction, or formatting pass
- no continuous always-on listening
- no transcript history
- no cloud sync
- no custom wake word
- no mobile version

## Open Technical Risks

- exact STT transcript event semantics may require tuning if Cartesia emits segmented final transcripts rather than a single cumulative final string
- some sandboxed or unusual target apps may behave differently with synthetic paste events
- hotkey conflicts with system or app shortcuts need a clear fallback path in settings
- microphone and accessibility permission UX on first launch needs careful handling to avoid a broken first-run experience

## Recommended First Implementation Target

Aim for a reliable V1 with:

- one global hotkey
- English transcription
- menu bar settings
- hold-to-talk dictation
- delayed full paste on release

Once this works end-to-end, add hotkey customization polish, better onboarding, and additional options (e.g. pinned Ink 2 snapshots) as Cartesia exposes them.
