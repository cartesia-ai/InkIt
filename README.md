<div align="center">

<img src=".github/media/icon.png" width="88" height="88" alt="InkIt icon" />

# Just ink it.

Type at the speed of talking.<br>
InkIt catches every word, even over a hissing espresso machine, a chattering open office, or a rumbling train.

https://github.com/user-attachments/assets/0b10a071-c07c-466d-b1ee-ce993f581722

<a href="https://github.com/cartesia-ai/InkIt/releases/latest/download/InkIt.dmg">
  <img src=".github/media/download-macos.svg" height="48" alt="Download for macOS" />
</a>

<sub>Requires macOS 14+ · Apple silicon</sub>

<sub>Powered by [Ink-2](https://www.cartesia.ai/ink) Speech to Text from Cartesia.</sub>
</div>


## Setup

All you need is a free [Cartesia API key](https://play.cartesia.ai), good for about 15,000 words of dictation a month.

On first launch, onboarding walks you through the permissions and your key.

Optionally, you can turn on Polish to clean up filler, punctuation, and formatting without rewriting your words. Bring your own key from Groq, Google Gemini, OpenAI, or Anthropic.

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
