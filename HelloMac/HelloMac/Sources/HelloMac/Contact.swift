import Foundation

struct Contact: Codable, Identifiable {
    var id: UUID = UUID()
    var firstName: String
    var lastName: String
    var phone: String
    var isFavorite: Bool = false

    /// Πλήρες όνομα για εμφάνιση (Όνομα + Επώνυμο)
    var fullName: String {
        let trimmedLast = lastName.trimmingCharacters(in: .whitespaces)
        return trimmedLast.isEmpty ? firstName : "\(firstName) \(trimmedLast)"
    }

    enum CodingKeys: String, CodingKey {
        case id, firstName, lastName, phone, isFavorite
        case legacyName = "name" // Παλιό πεδίο από προηγούμενες εκδόσεις
    }

    init(id: UUID = UUID(), firstName: String, lastName: String, phone: String, isFavorite: Bool = false) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.phone = phone
        self.isFavorite = isFavorite
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        phone = try container.decodeIfPresent(String.self, forKey: .phone) ?? ""
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false

        if let first = try container.decodeIfPresent(String.self, forKey: .firstName) {
            firstName = first
            lastName = try container.decodeIfPresent(String.self, forKey: .lastName) ?? ""
        } else if let legacy = try container.decodeIfPresent(String.self, forKey: .legacyName) {
            let parts = legacy.split(separator: " ", maxSplits: 1).map(String.init)
            firstName = parts.first ?? legacy
            lastName = parts.count > 1 ? parts[1] : ""
        } else {
            firstName = ""
            lastName = ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(firstName, forKey: .firstName)
        try container.encode(lastName, forKey: .lastName)
        try container.encode(phone, forKey: .phone)
        try container.encode(isFavorite, forKey: .isFavorite)
    }
}

class ContactStore {
    static let shared = ContactStore()
    private let key = "HelloMacContacts"

    var contacts: [Contact] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let decoded = try? JSONDecoder().decode([Contact].self, from: data)
            else { return [] }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(encoded, forKey: key)
            }
        }
    }

    var favorites: [Contact] {
        contacts.filter { $0.isFavorite }
    }

    func toggleFavorite(id: UUID) {
        var list = contacts
        guard let idx = list.firstIndex(where: { $0.id == id }) else { return }
        list[idx].isFavorite.toggle()
        contacts = list
        NotificationCenter.default.post(name: .contactsDidChange, object: nil)
    }
    
    func updateContact(_ updatedContact: Contact) {
        var list = contacts
        if let idx = list.firstIndex(where: { $0.id == updatedContact.id }) {
            list[idx] = updatedContact
            contacts = list
            NotificationCenter.default.post(name: .contactsDidChange, object: nil)
        }
    }
}

extension String {
    /// Καθαρίζει τον αριθμό αφήνοντας μόνο νούμερα και το σύμβολο '+'
    var sanitizedForCall: String {
        return self.filter { "0123456789+".contains($0) }
    }
}