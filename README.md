# Family IT

Family IT is a local, senior-friendly macOS assistant that gives calm, one-step-at-a-time help with common technology problems. This first version includes scripted walkthroughs for Zoom audio, finding an app, and finding photos.

Everything runs on the Mac. The app has no account, database, API key, web view, or external service. Conversation history stays in memory and disappears when the app closes.

## What you need

- A Mac running macOS 14 or newer
- Xcode 16 or newer (the project was verified with Xcode 26.4.1)

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

## Try the scripted flow

1. Click **I can’t hear my Zoom meeting**.
2. Listen to the question, then press **Talk** and answer.
3. Follow one instruction at a time and click **I did it** after each instruction.
4. Use **I need more help**, **Repeat instruction**, or **Go back** whenever needed.

The Space bar is also a shortcut for the main talk button when the text field is not being edited.

## Project layout

- `FamilyIT/App` — app entry point
- `FamilyIT/Views` — accessible SwiftUI screens and button styles
- `FamilyIT/Services` — speech recognition, spoken replies, and view state
- `FamilyIT/Models` — assistant turns and the scripted troubleshooting engine
- `FamilyIT/Resources` — permission descriptions and sandbox entitlements

`TroubleshootingEngine` is the boundary for future assistant logic. A later local model, Codex adapter, or Mac automation adapter can replace the scripted engine without changing the screens or speech services.
