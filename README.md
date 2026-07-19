<div align="center">

### InkIt - just ink it
https://github.com/user-attachments/assets/d09303cc-55b6-4f37-9fd2-a658a27aff88

<a href="https://github.com/cartesia-ai/InkIt/releases/latest/download/InkIt.dmg">
  <img src=".github/media/download-macos.svg" height="48" alt="Download for macOS" />
</a>

<sub>Powered by [Ink-2](https://www.cartesia.ai/ink) Speech to Text from Cartesia.</sub>
</div>

## Features
* **Get hours back every week.** You talk 3× faster than you type. Start talking, stop typing.
* **Heard right the first time.** Stays accurate when you're whispering or talking over background noise, so there's less to fix.
* **Nail your own vocabulary.** Add names, jargon, and custom spellings to your dictionary, and InkIt gets them right every time.
* **Use it in every app you already live in.** Editor, browser, chat, terminal: your words land right at the cursor, no copy-paste.
* **Talk your way.** Hold a key to dictate, or go fully hands-free. Set whatever shortcut feels natural.
* **No ums, no filler.** Polish tidies your speech and punctuation automatically, without rewriting your words.
* **Never lose a thought.** Every dictation is saved and searchable, with insights into how much you dictate and where.
* **Make it yours.** Light or dark, your mic, your shortcut. Tune it to how you work.

## Setup

1. Download via the button above and move InkIt to your Applications folder.
2. Launch InkIt. Go through a quick onboarding to set up Microphone and Accessibility access.
3. Grab a free [Cartesia API key](https://play.cartesia.ai), good for about 15,000 words a month.
4. (Optional) Turn on Polish with your own key from Groq, Google Gemini, OpenAI, or Anthropic.

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
