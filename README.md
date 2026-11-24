# Family IT

A native macOS voice assistant with immediate local actions and Codex/Claude planning for unfamiliar requests. The floating window stays beside the apps it opens.

## Run with your team

Requires macOS 14+, Xcode with Swift 6.2+, and either Codex CLI or Claude Code installed and signed in to the teammate's own account. No separate API key is required. Provider account limits still apply.

1. Clone the team repository and open `FamilyIT.xcodeproj`.
2. Select the shared **FamilyIT** scheme, **My Mac**, then press Command-R.
3. In Settings, choose Automatic, Codex, or Claude and use **Check AI setup**.
4. If setup reports a missing executable, install the provider CLI in a standard location: `~/.local/bin`, `/opt/homebrew/bin`, or `/usr/local/bin`. Sign in outside the app with `codex login` or `claude auth login`.
5. Grant permissions when the requested feature needs them. Each teammate grants permissions on their own Mac.

The checked-out working changes must be shared before another person can clone them. This implementation does not commit or push. The app uses local/ad-hoc development signing; rebuilding can invalidate macOS permissions. Use a stable Apple Development identity when available. Signed/notarized public distribution is a separate release.

## Try these requests

- “Open Safari.”
- “Open Safari then open Notes.”
- “Check if I am connected to Wi-Fi.”
- “Text John that I’m joining my appointment.”
- “Open Messages and text John that I will be there soon.”
- “Draft a message to John saying see you tomorrow.”
- “Create a note called Shopping list saying milk and eggs.”
- “Help me join my doctor’s meeting.” (Have the invitation open in Safari.)
- “Can you take meeting notes?”
- “Stop recording.”
- “Send the notes to my son.”

Every spoken/typed request enters the same router, including follow-ups. Complete common commands run locally without AI. Other wording goes to one structured planner request returning up to eight ordered actions. The executor runs the plan without asking “I did it” between automated steps. Unknown tasks get an explanation or an essential question.

## Contacts and Messages

Contacts are looked up locally by full name, unique first name, or nickname. Multiple people or multiple destinations produce a choice. The selected name/destination is remembered locally and revalidated against Contacts. Configure relationships such as **my son** in Settings → Notes and contacts: enter the alias, load contacts, and choose a person/destination.

An explicit send/text/tell request submits immediately when recipient and message are clear. A draft/write request opens the conversation and displays the draft in Family IT; choosing Continue submits it. Family IT never converts a draft request into an automatic send.

The fixed Messages implementation currently submits through an iMessage service. Availability of SMS relay depends on the user's Mac/iPhone setup and is not guaranteed. A successful script means submission to Messages, not delivery. If submission is uncertain, inspect the conversation before requesting another send. No automatic mutation retries occur.

## Telehealth and notes

The real workflow is flexible; it has no predetermined next act or hardcoded meeting URL.

- Wi-Fi checks open settings and read CoreWLAN locally. Hidden/redacted network names are reported as unavailable. Joining a network remains a separate guided flow; passwords are entered only in System Settings.
- Safari invitation lookup reads accessible URLs from the front Safari window, bounded by a time/node limit. It recognizes Zoom, Google Meet, and Teams meeting URLs. Multiple links produce a choice; inaccessible Gmail content produces an honest request to open/paste the link. It does not search the Gmail account or require Safari JavaScript automation.
- Meeting notes capture **Zoom audio** with ScreenCaptureKit plus microphone audio with AVAudioEngine. Microphone, Speech Recognition, and Screen & System Audio Recording permissions are required. Joining a call never starts capture automatically.
- A persistent **Taking meeting notes** indicator and **Stop notes** control remain visible. Response speech is suppressed during recording. Headphones reduce duplicate transcription when the microphone would otherwise hear speaker audio.
- English recognition runs on-device. Each audio source rolls its recognition requests every 45 seconds and retains late final updates by segment identifier. Notes include source labels and timestamps, not verified speaker identities.
- Stop ends capture, summarizes the actual transcript through the selected AI, and opens the saved Apple Note. Long transcripts are summarized in chunks rather than silently dropping the end. Empty capture never creates invented care instructions.
- Notes are saved in the configured folder, default **Family IT**. Sharing uses the same cached summary; it does not summarize a second time or duplicate the saved note.
- Raw audio is never saved. Transcript data remains in memory until a new recording/app termination; summaries persist in Apple Notes. A 200,000-character visit limit stops capture with a visible status.

The current recorder targets Zoom. Other meeting apps can have their links opened but are not audio capture sources in this release.

## Permissions and privacy

- **Microphone / Speech Recognition:** requested when dictating or taking meeting notes.
- **Contacts:** requested for a named recipient or loading contacts in Settings.
- **Accessibility:** needed for Safari invitation lookup and the retained Zoom preview hover explanations.
- **Screen & System Audio Recording:** needed to capture Zoom audio. No screen image output is registered.
- **Automation:** macOS prompts when Family IT controls Messages or Notes.
- **Location:** optional to expose Wi-Fi SSIDs; coordinates are not requested.

Permission links/status are available under Settings & help → Permissions. Contact addresses, Wi-Fi status, and Safari accessibility trees are not automatically sent to the planner. Request text is sent when AI interpretation is needed; actual meeting transcripts are sent for summarization. Provider account data policies apply.

The model selects typed actions and parameters. It has no execution tools. App-owned script templates receive literal arguments, not generated executable source. Validation rejects unknown actions, unsupported URL schemes/embedded credentials, and unbounded plans. External page/transcript text is treated as data.

The runner uses fixed argument arrays/stdin, isolated temporary directories, disabled CLI tools/customizations, deadlines, and cancellation. Temporary schema/results are removed after requests. Accounts are used through their own installed CLI; credentials are not read by Family IT.

## Verification

```bash
swift test
xcodebuild -project FamilyIT.xcodeproj -scheme FamilyIT -configuration Debug build
```

The package compiles the same native services as Xcode so coordinator tests can inject fake planners/executors. Offline tests do not send messages or start meeting capture.

Opt-in provider tests generate plans only:

```bash
FAMILY_IT_LIVE_PLANNER=1 FAMILY_IT_BACKEND=codex swift test --filter livePlannerReturnsCompleteMessageTask
FAMILY_IT_LIVE_PLANNER=1 FAMILY_IT_BACKEND=claude swift test --filter livePlannerReturnsCompleteMessageTask
```

Help & privacy shows recent local routing, AI planning, and action durations. Local routing and app-launch latency are measured separately. A local-routing benchmark is included; AI/network timing is not promised to be sub-second.

Before a team release, perform a fresh-user walkthrough with each provider, a consenting message recipient, Contacts denied/duplicate-name cases, an actual Gmail invitation, and a Zoom call with headphones lasting longer than 45 seconds. Verify both audio sources, Stop, summary contents, note foregrounding, and no duplicate sends. Automated success alone does not certify these live integrations.

## Restore the original scripted demo

The exact original source snapshot is stored locally in the ignored archive:

`.demo-snapshots/telehealth-demo-2026-11-20.tar.gz`

SHA-256: `bbfd43cdef1a68239a44a9d868ef32561a417bd34bceaa9a1ad9954cc898b1df`

Extract into a separate folder and open its Xcode project. Keep the current project untouched. The archive is intentionally not included in Git clones; share it separately when teammates need the original recording workflow.
