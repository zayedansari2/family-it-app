# Family IT

Family IT is a senior-friendly macOS assistant that uses the Codex account already signed in on the Mac to create calm, one-step-at-a-time help for everyday technology problems. It is not limited to scripted topics. It can also open an installed Mac app when asked.

Family IT does not store an API key, use a database, or show a web view. Each guidance request runs through the local Codex CLI in ephemeral, read-only mode. Conversation history stays in the app’s memory and disappears when the app closes. Codex still needs an internet connection and uses the OpenAI account already signed in through the CLI.

## What you need

- A Mac running macOS 14 or newer
- Xcode 16 or newer (the project was verified with Xcode 26.4.1)
- Codex CLI installed and signed in on this Mac

Check Codex before running Family IT:

    codex --version
    codex login

If `codex login` says you are already signed in, no further action is needed. Family IT automatically finds Codex in `~/.local/bin`, `/opt/homebrew/bin`, or `/usr/local/bin`.

## Open and run in Xcode

1. Open Terminal.
2. Go to this project folder:

   ```sh
   cd /Users/zayed/Code/family-it-app
   ```

3. Open the project:

   ```sh
   open FamilyIT.xcodeproj
   ```

4. In the top toolbar in Xcode, make sure the scheme says **FamilyIT** and the run destination says **My Mac**.
5. Press **Command-R**, or click the triangular Run button.
6. The first time you press **Tap to talk**, macOS asks for microphone and speech-recognition permission. Click **Allow** for both.

If a permission was previously denied, open **System Settings → Privacy & Security**, then enable Family IT under both **Microphone** and **Speech Recognition**.

## Build from Terminal

From the project folder, run:

```sh
xcodebuild \
  -project FamilyIT.xcodeproj \
  -scheme FamilyIT \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/FamilyIT-DerivedData \
  build
```

The built app will be at:

```text
/tmp/FamilyIT-DerivedData/Build/Products/Debug/FamilyIT.app
```

To launch that build from Terminal:

```sh
open /tmp/FamilyIT-DerivedData/Build/Products/Debug/FamilyIT.app
```

## Try the Codex guidance flow

1. Type or say a technology question, such as **How do I download Zoom?**
2. Family IT gives one short instruction or asks one clarifying question.
3. Complete only that instruction.
4. Click **I did it**, or press **Talk** and say **I did it**, to receive the next step.
5. Click **I need more help** if the instruction does not work. Codex will try a different approach using the conversation so far.

To try computer control, say or type **Open Safari**, **Launch Zoom**, or **Start Photos**. Family IT recognizes common Apple and third-party apps and can also find apps by their exact installed name.

The Space bar is also a shortcut for the main talk button when the text field is not being edited.

## Project layout

- `FamilyIT/App` — app entry point
- `FamilyIT/Views` — accessible SwiftUI screens and button styles
- `FamilyIT/Services` — Codex guidance, speech recognition, spoken replies, local app launching, and view state
- `FamilyIT/Models` — assistant turns and the troubleshooting-engine boundary
- `FamilyIT/Resources` — microphone and speech-recognition permission settings

`TroubleshootingEngine` keeps the Codex integration separate from the screens and speech services. Codex is instructed to return one structured turn at a time: a question, one instruction, or completion.
