# InkIt

Push-to-talk dictation for macOS. Hold a hotkey, speak, release — your words get transcribed by Cartesia's `ink-2` and pasted wherever your cursor is.

## Use it

1. Hold the **Fn 🌐** key.
2. Speak. The notch HUD shows you're recording.
3. Release. Transcript pastes at your cursor.

Works in any text field — Slack, Mail, your IDE, browser, anywhere.

## Setup

You need macOS 14+, a microphone, and a [Cartesia API key](https://play.cartesia.ai).

On first launch, onboarding walks you through Microphone + Accessibility permissions and your API key.

**The Fn 🌐 key just works.** macOS normally opens the emoji panel on that key, but InkIt installs an event tap that intercepts Fn before the system sees it (once Accessibility is granted), so holding it dictates instead — no need to remap it in System Settings.

## Build from source

No signed release yet — build it yourself. Needs Xcode 15+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
open InkIt.xcodeproj
```

To install:

```bash
cp -R build/Build/Products/Release/InkIt.app /Applications/
```

Code changes only take effect after replacing `/Applications/InkIt.app` — rebuilding alone isn't enough.
