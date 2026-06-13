<div align="center">

<img src=".github/media/icon.png" width="88" height="88" alt="InkIt icon" />

# Just ink it.

Type at the speed of talking.<br>
InkIt catches every word, even over a hissing espresso machine, a chattering open office, or a rumbling train.

https://github.com/user-attachments/assets/a9bce14a-5294-48fc-ba1c-19f3eaef378e

<a href="https://github.com/cartesia-ai/InkIt/releases/latest/download/InkIt.dmg">
  <img src=".github/media/download-macos.svg" height="48" alt="Download for macOS" />
</a>

<sub>Requires macOS 14+ · Apple silicon</sub>

<sub>Powered by [Ink-2](https://www.cartesia.ai/ink) Speech to Text from Cartesia.</sub>
</div>

## Features
* **Works everywhere you type.** Any app on your Mac — editor, browser, chat, terminal. Text lands right at your cursor.
* **Catches every word.** InkIt stays accurate even when you are whispering or talking in noisy public spaces.
* **Hold, or go hands-free.** Hold your key to talk, release to drop the text. Or go hands-free with one tap to start, and another to stop.
* **Set your own shortcut.** Use the default `fn` key, or set any key combination you like.
* **Polish.** Cleans up filler, punctuation, and formatting without rewriting your words.
* **Searchable history.** Every dictation is saved locally on your Mac, so nothing you said is lost.
* **Make it yours.** Switch between light and dark mode, pick your input mic, and tune the app to fit how you work.

## Setup

1. Download the app via the button above. Install the app in your Applications folder.
2. Launch InkIt. Go through a quick onboarding to set up Microphone and Accessibility access. 
3. Grab a free [Cartesia API key](https://play.cartesia.ai) — good for about 15,000 words a month.
4. (Optional) Turn on Polish, and bring your own key from Groq, Google Gemini, OpenAI, or Anthropic.

## For developers

InkIt is open source but not open contribution.

Fork and modify it for your own use. Pull requests aren't guaranteed a review: see [CONTRIBUTING.md](.github/CONTRIBUTING.md). Bug reports and feedback go [here](https://forms.gle/jXNtDsTaLt2rKQ8N9).

<details>
<summary><strong>Build from source</strong> (Xcode 15+ and XcodeGen)</summary>

<br />

```bash
brew install xcodegen
xcodegen generate
open InkIt.xcodeproj
```

Install the build:

```bash
cp -R build/Build/Products/Release/InkIt.app /Applications/
```

Changes only take effect after you replace `/Applications/InkIt.app`. Rebuilding alone isn't enough.

</details>
