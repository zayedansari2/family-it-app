# Family IT

A native macOS SwiftUI voice guide for everyday technology questions. Warm off-white, deep teal, muted green-gray text, terracotta accents, system typography, and one response at a time.

The interface uses a translucent sidebar, native Liquid Glass microphone/composer surfaces, and native glass buttons on macOS 26 and later. macOS 14–15 use system materials and standard native buttons. Reduce Transparency uses opaque custom surfaces, and Reduce Motion disables view transitions.

## Open and run

Requires macOS 14 or later and Xcode with Swift 6.2 or later. Verified with Xcode 26.4.1. No package downloads or API key are needed.

1. Open Terminal and run:

       cd /Users/zayed/Code/family-it-app
       open FamilyIT.xcodeproj

2. Select the FamilyIT scheme and My Mac destination.
3. Press Command-R. To stop a previous run first, press Command-period.
4. Type a question and choose Get help, or choose Tap to talk.
5. Finish the current instruction, then choose I did it or say “I did it.” If it fails, choose That didn’t work. Explain that differently offers another explanation.

The local development build uses “Sign to Run Locally” and needs no signing team. If you later choose development signing, select the FamilyIT project, the FamilyIT target, Signing & Capabilities, and your own development team. Run on My Mac.

## Permissions

Microphone and Speech Recognition prompts appear when you first choose Tap to talk. Grant them yourself if you want voice input. Typing works without either permission.

Open Permissions inside Family IT for status and explanations. Each settings link shows a confirmation request. Continue opens the corresponding System Settings page; enable Family IT manually under Privacy & Security → Microphone, Speech Recognition, or Accessibility. Accessibility is only required for the limited accessibility actions, not opening apps.

If you rebuild with a different signing identity or move the app, macOS may ask again. You can turn all access off in System Settings at any time.

## Backend selection

Automatic mode checks installed, authenticated Codex first, Claude second, and then uses Demo mode. CLI locations checked: ~/.local/bin, /opt/homebrew/bin, and /usr/local/bin.

Use Family IT → Settings (Command-comma) to select a provider. The choice applies to the next new question. For Xcode environment configuration: Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables. Add FAMILY_IT_BACKEND with codex, claude, or mock. Remove it for automatic selection. The environment takes precedence over Settings.

The .env.example file documents these names; the application does not load .env files.

Sign in outside the app if needed:

    codex login
    codex login status

Or:

    claude auth login
    claude auth status

Forced providers show an error and Retry if unavailable; they do not silently change to Demo mode.

## Try Demo mode

1. Choose Settings → Response provider → Demo mode.
2. Start a new question and choose “I can’t hear my Zoom meeting.”
3. Answer “Mac,” then answer whether Zoom is already open.
4. If Zoom is closed, approve or cancel the explicit opening request.
5. Follow the sound instructions one at a time.
6. Answer whether you can hear the meeting. The demonstration finishes only after explicit confirmation.

The demo intentionally covers Zoom audio on a Mac. Other questions need Codex or Claude. Demo mode is always visibly labeled.

## Voice and accessibility

Apple Speech provides push-to-talk recognition. Pressing the microphone stops speech playback. No audio files are saved. Apple speech processing may use the network depending on installed language support and system settings.

Native speech synthesis uses the highest-quality installed English voice by default. Settings offers voice on/off, installed voice selection, speed, and larger text. Read again replays the response. Additional system voices can be installed through macOS Accessibility → Spoken Content.

Both screens retain typed input. Buttons support keyboard focus, system VoiceOver semantics, and generous hit areas. Larger text and small windows may scroll the current screen, never a conversation transcript. Reduced Motion removes screen-transition animation.

## Computer actions

All actions become a typed enum, pass local validation, and require an explicit Continue click. Cancel performs no action. The executor validates again immediately before execution.

- Open/focus Zoom, System Settings, Photos, Finder, Safari, or App Store.
- Open General, Sound, Wi-Fi, or selected privacy permission pages.
- Read the focused accessibility label in Finder or Photos, locally.
- Press a uniquely matched Search or Back button in Finder or Photos.
- Set exact confirmed text in a uniquely matched Finder/Photos search field.

The Open… menu also lets the user select an allowlisted application directly. Unlisted apps, arbitrary URLs, arbitrary AX selectors, shell commands, AppleScript, destructive controls, and secure text fields are rejected. Click/type operations refuse ambiguous or missing targets and may be unavailable for controls whose accessibility labels differ by macOS version or language.

An action outcome asks what the user sees. Opening an app does not establish that the original problem is solved. Accessibility label contents are displayed locally and are never automatically sent to a backend. The in-memory action log contains generic human-readable descriptions and never typed text or screen contents.

## CLI isolation and privacy

The runner invokes a known executable using Swift Process, fixed argument arrays, and stdin. User text is never placed in command arguments or a shell. Each request gets a dedicated temporary working directory. Output is bounded; stderr is discarded, and raw errors never reach the interface.

Codex uses exec, ephemeral mode, a read-only sandbox, ignored user configuration/rules, disabled shell and unified execution, disabled editing tools, plugins, apps, browser/computer/image tools, hooks, and multi-agent tools. Claude uses print, safe mode, no tools, plan permissions, empty MCP configuration, and no session persistence. CLI feature settings follow the installed version; upgrades should be revalidated before distributing the app.

Requests time out after 60 seconds. Cancel terminates the child, with a force-termination fallback after 0.5 seconds. Authentication probes have an 8-second timeout. Late responses cannot replace a newer conversation.

Conversation history stays in memory. Temporary schema/response files are removed on success, failure, or cancellation. A forced process crash can leave a temporary directory for macOS to clean up. The existing CLI account is used without reading or displaying authentication credentials. Family IT does not store API keys. Codex/Claude process conversation content online and their own account retention and usage policies apply. Local CLI operational files may still be maintained by those tools.

There is no camera, screenshot, screen sharing, analytics, database, hosting, or cloud account setup. The local app is not App Store sandboxed because it must invoke the existing CLI. Codex requests have their own read-only execution sandbox.

## Build and tests

Build the app:

    xcodebuild -project FamilyIT.xcodeproj -scheme FamilyIT -configuration Debug build

Or use an explicit output directory:

    xcodebuild -project FamilyIT.xcodeproj -scheme FamilyIT -configuration Debug -derivedDataPath /tmp/FamilyIT-Product build
    open /tmp/FamilyIT-Product/Build/Products/Debug/FamilyIT.app

Run the offline Swift Testing suite:

    swift test

Package.swift compiles the exact app model/backend sources as FamilyITCore. The suite checks conversation confirmation, mock flow, fallback order, action allowlisting, malicious/unknown actions, safe typing, invalid responses, literal stdin, timeout termination, and cancellation before and during launch. No account or network is required.

Optional authenticated Codex integration test:

    FAMILY_IT_LIVE_CODEX=1 FAMILY_IT_BACKEND=codex swift test --filter liveCodexResponse

The Xcode project is the application entry point. Package.swift provides a separate core test harness, not a second application. The app-icon placeholder is native generated artwork; regenerate with:

    swift Scripts/GenerateIcon.swift FamilyIT/Resources/Assets.xcassets/AppIcon.appiconset

## Architecture

- Views: home, single-response assistant, settings, help/privacy, permissions.
- VoiceAssistantViewModel: main-actor UI state, explicit completion, pending confirmations, retry/cancel.
- TroubleshootingEngine: conversation boundary; Codex/Claude engine or mock engine.
- CLIProcess: background subprocess supervision, stdin, timeout, cancellation.
- ComputerAction / GuidanceResponse: typed, validated response contract.
- SafeComputerExecutor / PermissionManager: narrow native actions and permission state.
- SpeechRecognitionService / SpeechSynthesizerService: Apple voice input/output.

## Verification and limits

The native build and automated core tests pass. A real authenticated Codex response passed with restricted arguments. Both CLIs are detected; Claude is installed but not authenticated on this Mac, so a live Claude reply has not been verified.

The running UI was checked for home layout, typed Demo questions/answers, settings, action confirmation/cancellation, permission guidance, and speech-status transitions. Actual voice recognition, audible playback quality, and AX click/type operations still need a manual check after the user grants permissions. Automated tests do not toggle privacy permissions or mutate other apps.

AI replies can be mistaken. Current installed-voice quality, app accessibility trees, and settings deep links depend on macOS. The action allowlist is deliberately small and English-only. The native placeholder icon is ready to replace with final branding.
