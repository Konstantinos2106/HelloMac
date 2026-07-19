import Foundation
import AppKit

struct Contact: Codable, Identifiable {
    var id: UUID = UUID()
    var firstName: String
    var lastName: String
    var phone: String
    var isFavorite: Bool = false
    var favoritedAt: Date? = nil
    var imageFileName: String? = nil
    var monogramColorHex: String? = nil

    var fullName: String {
        let trimmedLast = lastName.trimmingCharacters(in: .whitespaces)
        return trimmedLast.isEmpty ? firstName : "\(firstName) \(trimmedLast)"
    }

    var initials: String {
        let firstInitial = firstName.trimmingCharacters(in: .whitespaces).first
        let lastInitial = lastName.trimmingCharacters(in: .whitespaces).first
        let combined = [firstInitial, lastInitial].compactMap { $0 }.map { String($0) }.joined()
        if combined.isEmpty { return "?" }
        return combined.uppercased()
    }

    var image: NSImage? {
        guard let fileName = imageFileName else { return nil }
        return ContactImageStore.loadImage(fileName: fileName)
    }

    var monogramColor: NSColor? {
        guard let hex = monogramColorHex else { return nil }
        return NSColor(hexString: hex)
    }

    enum CodingKeys: String, CodingKey {
        case id, firstName, lastName, phone, isFavorite, favoritedAt, imageFileName, monogramColorHex
        case legacyName = "name"
    }

    init(id: UUID = UUID(), firstName: String, lastName: String, phone: String, isFavorite: Bool = false, favoritedAt: Date? = nil, imageFileName: String? = nil, monogramColorHex: String? = nil) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.phone = phone
        self.isFavorite = isFavorite
        self.favoritedAt = favoritedAt
        self.imageFileName = imageFileName
        self.monogramColorHex = monogramColorHex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        phone = try container.decodeIfPresent(String.self, forKey: .phone) ?? ""
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        favoritedAt = try container.decodeIfPresent(Date.self, forKey: .favoritedAt)
        imageFileName = try container.decodeIfPresent(String.self, forKey: .imageFileName)
        monogramColorHex = try container.decodeIfPresent(String.self, forKey: .monogramColorHex)

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
        try container.encodeIfPresent(favoritedAt, forKey: .favoritedAt)
        try container.encodeIfPresent(imageFileName, forKey: .imageFileName)
        try container.encodeIfPresent(monogramColorHex, forKey: .monogramColorHex)
    }
}

enum ContactImageStore {
    static var directoryURL: URL = {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("HelloMac/ContactImages", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func saveImage(_ image: NSImage, existingFileName: String? = nil) -> String? {
        let fileName = existingFileName ?? "\(UUID().uuidString).jpg"
        let fileURL = directoryURL.appendingPathComponent(fileName)

        let maxDimension: CGFloat = 400
        let size = image.size
        let scale = min(1.0, maxDimension / max(size.width, size.height))
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(newSize.width),
            pixelsHigh: Int(newSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(origin: .zero, size: newSize),
                    from: NSRect(origin: .zero, size: size),
                    operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        guard let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        else { return nil }

        do {
            try jpegData.write(to: fileURL)
            return fileName
        } catch {
            return nil
        }
    }

    // ★ Σημαντική διόρθωση: Χρησιμοποιούμε τον υπάρχοντα ImageOrientationFix
    static func loadImage(fileName: String) -> NSImage? {
        let fileURL = directoryURL.appendingPathComponent(fileName)
        return ImageOrientationFix.normalizedImage(contentsOf: fileURL) ?? NSImage(contentsOf: fileURL)
    }

    static func deleteImage(fileName: String?) {
        guard let fileName = fileName else { return }
        let fileURL = directoryURL.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileURL)
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
        list[idx].favoritedAt = list[idx].isFavorite ? Date() : nil
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

struct CallRecord: Codable, Identifiable {
    var id: UUID = UUID()
    var phone: String
    var contactName: String?
    var contactID: UUID? = nil
    var date: Date

    enum CodingKeys: String, CodingKey {
        case id, phone, contactName, contactID, date
    }

    init(id: UUID = UUID(), phone: String, contactName: String? = nil, contactID: UUID? = nil, date: Date) {
        self.id = id
        self.phone = phone
        self.contactName = contactName
        self.contactID = contactID
        self.date = date
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        phone = try container.decodeIfPresent(String.self, forKey: .phone) ?? ""
        contactName = try container.decodeIfPresent(String.self, forKey: .contactName)
        contactID = try container.decodeIfPresent(UUID.self, forKey: .contactID)
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? Date()
    }
}

enum HistoryAutoDeleteInterval: Int, CaseIterable {
    case never = 0
    case afterOneDay
    case afterOneWeek
    case afterTwoWeeks
    case afterOneMonth
    case afterThreeMonths
    case afterSixMonths
    case afterOneYear

    static let defaultsKey = "historyAutoDeleteInterval"

    var days: Int? {
        switch self {
        case .never: return nil
        case .afterOneDay: return 1
        case .afterOneWeek: return 7
        case .afterTwoWeeks: return 14
        case .afterOneMonth: return 30
        case .afterThreeMonths: return 90
        case .afterSixMonths: return 182
        case .afterOneYear: return 365
        }
    }

    var localizedTitle: String {
        switch self {
        case .never: return L("history_autodelete_never")
        case .afterOneDay: return L("history_autodelete_1_day")
        case .afterOneWeek: return L("history_autodelete_1_week")
        case .afterTwoWeeks: return L("history_autodelete_2_weeks")
        case .afterOneMonth: return L("history_autodelete_1_month")
        case .afterThreeMonths: return L("history_autodelete_3_months")
        case .afterSixMonths: return L("history_autodelete_6_months")
        case .afterOneYear: return L("history_autodelete_1_year")
        }
    }

    static var current: HistoryAutoDeleteInterval {
        let raw = UserDefaults.standard.integer(forKey: defaultsKey)
        return HistoryAutoDeleteInterval(rawValue: raw) ?? .never
    }
}

class HistoryStore {
    static let shared = HistoryStore()
    private let key = "HelloMacCallHistory"

    var records: [CallRecord] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let decoded = try? JSONDecoder().decode([CallRecord].self, from: data)
            else { return [] }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(encoded, forKey: key)
            }
        }
    }
    
    func addRecord(phone: String, name: String?, contactID: UUID? = nil) {
        var list = records
        list.insert(CallRecord(phone: phone, contactName: name, contactID: contactID, date: Date()), at: 0)
        if list.count > 100 { list = Array(list.prefix(100)) }
        records = list
        NotificationCenter.default.post(name: NSNotification.Name("historyDidChange"), object: nil)
        purgeExpiredRecords()
    }

    func records(forContactID contactID: UUID) -> [CallRecord] {
        records.filter { $0.contactID == contactID }
    }

    @discardableResult
    func purgeExpiredRecords() -> Bool {
        guard let days = HistoryAutoDeleteInterval.current.days else { return false }
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return false }
        let list = records
        let filtered = list.filter { $0.date >= cutoff }
        guard filtered.count != list.count else { return false }
        records = filtered
        NotificationCenter.default.post(name: NSNotification.Name("historyDidChange"), object: nil)
        return true
    }
    
    func clear() {
        records = []
        NotificationCenter.default.post(name: NSNotification.Name("historyDidChange"), object: nil)
    }
}

extension NSColor {
    var hexString: String? {
        guard let rgb = usingColorSpace(.deviceRGB) else { return nil }
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    convenience init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >> 8) & 0xFF) / 255
        let b = CGFloat(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

extension String {
    var sanitizedForCall: String {
        return self.filter { "0123456789+".contains($0) }
    }
}