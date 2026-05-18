# Inksper

Push-to-talk macOS dictation app. Hold a global hotkey, speak, release. The transcript from Cartesia STT (`ink-whisper`) is pasted into the focused text field of the frontmost app.

## Status

Phase 1–4 of `PLAN.md` are implemented in source form. You must wire the files into an Xcode project to build.

## Building (one-time Xcode setup)

1. Open Xcode → **File → New → Project… → macOS → App**.
   - Product Name: `Inksper`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Uncheck Core Data / Tests.
2. Delete the auto-generated `InksperApp.swift` and `ContentView.swift`.
3. Drag every file from the `Inksper/` directory in this repo into the new target.
   - Replace the auto-generated `Info.plist` with the one in `Inksper/Info.plist`, or merge these keys into the existing one:
     - `LSUIElement = true` (menu bar only, no Dock icon)
     - `NSMicrophoneUsageDescription`
4. In the target's **Signing & Capabilities** tab:
   - Set a Development Team.
   - Set the deployment target to **macOS 14.0** or later (MenuBarExtra).
   - Add the **App Sandbox** capability **off** initially (Accessibility-based paste does not work reliably from a sandboxed app). If you want sandboxing, you'll need to switch the paste implementation.
5. In **Build Settings**, ensure `Other Linker Flags` includes Carbon by default (it does for macOS App targets).
6. Build & run. On first launch:
   - The app appears as a microphone icon in the menu bar.
   - Open Settings from the menu, paste your **Cartesia API key**, choose a language, set a hotkey.
   - Grant **Microphone** and **Accessibility** permissions when prompted.

## Default hotkey

`⌃⌥ Space` (Control + Option + Space). Change it in Settings → Hotkey.

## Files

| File | Role |
|------|------|
| `InksperApp.swift` | App entry point, menu bar UI |
| `AppCoordinator.swift` | State machine for the dictation lifecycle |
| `HotkeyManager.swift` | Carbon-based global press/release hotkey |
| `AudioCaptureService.swift` | `AVAudioEngine` mic capture |
| `AudioPCMConverter.swift` | Resample to mono pcm_s16le @ 16 kHz |
| `CartesiaStreamingClient.swift` | WebSocket to `wss://api.cartesia.ai/stt/websocket` |
| `PasteService.swift` | Pasteboard swap + synthesized ⌘V |
| `PermissionsService.swift` | Microphone + Accessibility checks |
| `SettingsStore.swift` | `UserDefaults`-backed settings |
| `SettingsView.swift` | SwiftUI settings window |
| `Info.plist` | Bundle metadata + usage strings |

## Notes & Risks

- The exact Cartesia event schema (field names like `text`, `is_final`, `flush_done`) was inferred from `PLAN.md`. If Cartesia's wire protocol differs, adjust `CartesiaStreamingClient.handleMessage`.
- Pasting via synthesized `⌘V` requires Accessibility permission and an unsandboxed app. Some apps (e.g. secure password fields) will reject the paste.
- The Cartesia API version string is `2026-03-01` per the plan. Update `cartesiaVersion` if the docs change.
