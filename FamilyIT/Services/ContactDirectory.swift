@preconcurrency import Contacts
import Foundation

nonisolated struct ContactChoice: Identifiable, Equatable, Codable, Sendable {
    var id: String { contactID + ":" + destination }
    let contactID: String
    let name: String
    let nickname: String
    let destination: String
    let label: String
    var displayLabel: String { "\(name) — \(label) …\(destination.suffix(4))" }
}

nonisolated struct ContactSelectionNeeded: Error, Sendable {
    let query: String
    let choices: [ContactChoice]
}

@MainActor final class ContactDirectory: ObservableObject {
    @Published private(set) var choices: [ContactChoice] = []
    private var loaded = false
    private var observer: NSObjectProtocol?
    init() {
        observer = NotificationCenter.default.addObserver(forName: .CNContactStoreDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.loaded = false; self?.choices = [] }
        }
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    func load() async throws {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .notDetermined {
            guard try await CNContactStore().requestAccess(for: .contacts) else { throw AssistantFailure("Allow Contacts access to find people by name.") }
        } else if status == .denied || status == .restricted {
            throw AssistantFailure("Contacts access is off. Enable Family IT in Privacy & Security → Contacts, or provide the recipient’s address.")
        }
        guard !loaded else { return }
        choices = try await Task.detached { try Self.fetch() }.value
        loaded = true
    }

    func resolve(_ query: String) async throws -> ContactChoice {
        // Literal destinations work even if Contacts access was declined.
        if Self.isAddress(query) {
            if let known = choices.first(where: { $0.destination == query }) { return known }
            return .init(contactID: "literal", name: query, nickname: "", destination: query, label: "address")
        }
        try await load()
        let key = Self.normalize(query)
        if let data = UserDefaults.standard.data(forKey: "contactAlias.\(key)"),
           let saved = try? JSONDecoder().decode(ContactChoice.self, from: data),
           let current = choices.first(where: { $0.id == saved.id }) { return current }
        let matches = Self.matches(query: query, choices: choices)
        if matches.count == 1 { return matches[0] }
        if !matches.isEmpty { throw ContactSelectionNeeded(query: query, choices: matches) }
        throw AssistantFailure("I couldn’t find “\(query)” in the contacts shared with Family IT. Choose a contact alias in Settings or give the full name.")
    }

    func saveAlias(_ alias: String, choice: ContactChoice) {
        let key = Self.normalize(alias)
        guard !key.isEmpty else { return }
        UserDefaults.standard.set(try? JSONEncoder().encode(choice), forKey: "contactAlias.\(key)")
    }
    nonisolated static func matches(query: String, choices: [ContactChoice]) -> [ContactChoice] {
        let key = normalize(query)
        guard !key.isEmpty else { return [] }
        let exact = choices.filter { normalize($0.name) == key || normalize($0.nickname) == key }
        return exact.isEmpty ? choices.filter { normalize($0.name).split(separator: " ").contains(Substring(key)) } : exact
    }

    nonisolated private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    nonisolated private static func isAddress(_ text: String) -> Bool {
        if text.contains("@"), !text.contains(" ") { return true }
        let digits = text.filter(\.isNumber)
        return digits.count >= 7 && text.allSatisfy { $0.isNumber || "+()- .".contains($0) }
    }
    nonisolated private static func fetch() throws -> [ContactChoice] {
        let keys = [CNContactIdentifierKey, CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey,
                    CNContactPhoneNumbersKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.unifyResults = true
        var result: [ContactChoice] = []
        try CNContactStore().enumerateContacts(with: request) { contact, _ in
            let name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            for phone in contact.phoneNumbers {
                result.append(.init(contactID: contact.identifier, name: name, nickname: contact.nickname,
                    destination: phone.value.stringValue, label: phone.label.map(CNLabeledValue<NSString>.localizedString(forLabel:)) ?? "phone"))
            }
            for email in contact.emailAddresses {
                result.append(.init(contactID: contact.identifier, name: name, nickname: contact.nickname,
                    destination: email.value as String, label: "email"))
            }
        }
        return Array(Dictionary(grouping: result, by: \.id).compactMap { $0.value.first }).sorted { $0.name < $1.name }
    }
}
