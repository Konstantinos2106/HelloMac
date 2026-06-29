import Foundation

struct Contact: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var phone: String
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
}
extension String {
    /// Καθαρίζει τον αριθμό αφήνοντας μόνο νούμερα και το σύμβολο '+'
    var sanitizedForCall: String {
        return self.filter { "0123456789+".contains($0) }
    }
}
