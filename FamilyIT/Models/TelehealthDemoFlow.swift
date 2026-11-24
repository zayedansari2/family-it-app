import Foundation

/// The fixed care workflow behind the voice-first interface.
nonisolated struct TelehealthDemoFlow: Equatable {
    enum Act: Int, CaseIterable, Equatable {
        case wifiAndAudio
        case notifyFamily
        case openAppointment
        case startVisitNotes
        case captureVisitNotes
        case shareSummary
        case complete
    }

    private(set) var act: Act = .wifiAndAudio

    var actNumber: Int { min(act.rawValue + 1, 6) }
    var progress: Double { act == .complete ? 1 : Double(act.rawValue) / 6 }
    var isComplete: Bool { act == .complete }

    var title: String {
        switch act {
        case .wifiAndAudio: "Wi-Fi check"
        case .notifyFamily: "Notify family"
        case .openAppointment: "Find the appointment"
        case .startVisitNotes: "Start visit notes"
        case .captureVisitNotes: "Visit notes"
        case .shareSummary: "Share the care plan"
        case .complete: "Ready"
        }
    }

    var cue: String {
        switch act {
        case .wifiAndAudio: "Check if I am connected to the Wi-Fi."
        case .notifyFamily: "Tell John I’m joining my doctor’s call."
        case .openAppointment: "Open my doctor’s email. Can you make it bigger?"
        case .startVisitNotes: "Can you record meeting notes while I am in the meeting?"
        case .captureVisitNotes: "The doctor is giving me the care instructions now."
        case .shareSummary: "I’m done. Send the notes to John."
        case .complete: "What else can I help with?"
        }
    }

    var workingMessage: String {
        switch act {
        case .wifiAndAudio: "Checking Wi-Fi…"
        case .notifyFamily: "Preparing a family message…"
        case .openAppointment: "Finding the email from your doctor…"
        case .startVisitNotes: "Getting ready to take meeting notes…"
        case .captureVisitNotes: "Summarizing the visit and creating the note…"
        case .shareSummary: "Preparing the visit summary…"
        case .complete: "Preparing a response…"
        }
    }

    var resultTitle: String? {
        switch act {
        case .wifiAndAudio: nil
        case .notifyFamily: "Wi-Fi connected"
        case .openAppointment: "Your family has been notified"
        case .startVisitNotes: "Your doctor’s appointment is open"
        case .captureVisitNotes: "Ready to take meeting notes"
        case .shareSummary: "Visit notes are ready"
        case .complete: "Visit summary sent"
        }
    }

    var resultDetail: String? {
        switch act {
        case .wifiAndAudio: nil
        case .notifyFamily: "Connected to Wi-Fi"
        case .openAppointment: "“I’m joining my doctor’s video call now.”"
        case .startVisitNotes: "Found the appointment email in Safari • Zoom is opening"
        case .captureVisitNotes: "I’m listening for the doctor’s care instructions."
        case .shareSummary: "Take blood pressure every morning\nFollow up in 4 weeks"
        case .complete: "Your family received the care instructions."
        }
    }

    var symbolName: String {
        switch act {
        case .wifiAndAudio: "wifi"
        case .notifyFamily: "message.fill"
        case .openAppointment: "video.fill"
        case .startVisitNotes, .captureVisitNotes: "mic.fill"
        case .shareSummary: "note.text"
        case .complete: "checkmark.circle.fill"
        }
    }

    mutating func advance() {
        guard let next = Act(rawValue: act.rawValue + 1) else { return }
        act = next
    }

    mutating func reset() { act = .wifiAndAudio }
}
