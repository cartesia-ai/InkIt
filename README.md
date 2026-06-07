<div align="center">

<img src=".github/media/icon.png" width="88" height="88" alt="InkIt icon" />

# Just ink it.

Type at the speed of talking.<br>
InkIt catches every word, even over a hissing espresso machine, a chattering open office, or a rumbling train.

Powered by [Ink 2](https://www.cartesia.ai/ink) from Cartesia.

<!-- HERO: replace with a ~6s GIF of the full loop (hold Fn → speak → text pastes).
     Drop the file at .github/media/demo.gif and uncomment the line below. -->
<!-- <img src=".github/media/demo.gif" width="720" alt="InkIt in action" /> -->

<br />

<a href="https://github.com/cartesia-ai/InkIt/releases/latest/download/InkIt.dmg">
  <img src=".github/media/download-macos.svg" height="48" alt="Download for macOS" />
</a>

<sub>Requires macOS 14+ · Apple silicon & Intel</sub>

</div>

---

## Setup

All you need is a free [Cartesia API key](https://play.cartesia.ai), good for about 15,000 words of dictation a month.

On first launch, onboarding walks you through the permissions and your key.

Optionally, you can turn on Polish to clean up filler, punctuation, and formatting without rewriting your words. Bring your own key from Groq, Google Gemini, OpenAI, or Anthropic.

## For developers

InkIt is open source but not open contribution.

Fork and modify it for your own use. Pull requests aren't guaranteed a review: see [CONTRIBUTING.md](CONTRIBUTING.md). Bug reports and feedback go [here](https://forms.gle/jXNtDsTaLt2rKQ8N9).

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
