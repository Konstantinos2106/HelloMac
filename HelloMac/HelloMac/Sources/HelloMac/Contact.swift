import Foundation
import AppKit

struct Contact: Codable, Identifiable {
    var id: UUID = UUID()
    var firstName: String
    var lastName: String
    var phone: String
    var isFavorite: Bool = false
    var favoritedAt: Date? = nil
    var favoriteSortIndex: Int? = nil
    var imageFileName: String? = nil
    var monogramColorHex: String? = nil
    var notes: String? = nil
    var externalIdentifier: String? = nil
    var groupIDs: [UUID] = []

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
        case id, firstName, lastName, phone, isFavorite, favoritedAt, favoriteSortIndex, imageFileName, monogramColorHex, notes, externalIdentifier, groupIDs
        case legacyName = "name"
    }

    init(id: UUID = UUID(), firstName: String, lastName: String, phone: String, isFavorite: Bool = false, favoritedAt: Date? = nil, favoriteSortIndex: Int? = nil, imageFileName: String? = nil, monogramColorHex: String? = nil, notes: String? = nil, externalIdentifier: String? = nil, groupIDs: [UUID] = []) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.phone = phone
        self.isFavorite = isFavorite
        self.favoritedAt = favoritedAt
        self.favoriteSortIndex = favoriteSortIndex
        self.imageFileName = imageFileName
        self.monogramColorHex = monogramColorHex
        self.notes = notes
        self.externalIdentifier = externalIdentifier
        self.groupIDs = groupIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        phone = try container.decodeIfPresent(String.self, forKey: .phone) ?? ""
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        favoritedAt = try container.decodeIfPresent(Date.self, forKey: .favoritedAt)
        favoriteSortIndex = try container.decodeIfPresent(Int.self, forKey: .favoriteSortIndex)
        imageFileName = try container.decodeIfPresent(String.self, forKey: .imageFileName)
        monogramColorHex = try container.decodeIfPresent(String.self, forKey: .monogramColorHex)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        externalIdentifier = try container.decodeIfPresent(String.self, forKey: .externalIdentifier)
        groupIDs = try container.decodeIfPresent([UUID].self, forKey: .groupIDs) ?? []

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
        try container.encodeIfPresent(favoriteSortIndex, forKey: .favoriteSortIndex)
        try container.encodeIfPresent(imageFileName, forKey: .imageFileName)
        try container.encodeIfPresent(monogramColorHex, forKey: .monogramColorHex)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(externalIdentifier, forKey: .externalIdentifier)
        if !groupIDs.isEmpty {
            try container.encode(groupIDs, forKey: .groupIDs)
        }
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

    private static let memoryCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 500
        return cache
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
            memoryCache.removeObject(forKey: fileName as NSString)
            return fileName
        } catch {
            return nil
        }
    }

    static func loadImage(fileName: String) -> NSImage? {
        let key = fileName as NSString
        if let cached = memoryCache.object(forKey: key) {
            return cached
        }
        let fileURL = directoryURL.appendingPathComponent(fileName)
        guard let image = ImageOrientationFix.normalizedImage(contentsOf: fileURL) ?? NSImage(contentsOf: fileURL) else {
            return nil
        }
        memoryCache.setObject(image, forKey: key)
        return image
    }

    static func deleteImage(fileName: String?) {
        guard let fileName = fileName else { return }
        memoryCache.removeObject(forKey: fileName as NSString)
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
        list[idx].favoriteSortIndex = nil
        contacts = list
        NotificationCenter.default.post(name: .contactsDidChange, object: nil, userInfo: ["isFavoriteToggle": true])
    }
    
    func updateContact(_ updatedContact: Contact) {
        var list = contacts
        if let idx = list.firstIndex(where: { $0.id == updatedContact.id }) {
            list[idx] = updatedContact
            contacts = list
            NotificationCenter.default.post(name: .contactsDidChange, object: nil)
        }
    }

    func reorderFavorites(orderedIDs: [UUID]) {
        var list = contacts
        for (index, id) in orderedIDs.enumerated() {
            if let idx = list.firstIndex(where: { $0.id == id }) {
                list[idx].favoriteSortIndex = index
            }
        }
        contacts = list
        NotificationCenter.default.post(name: .contactsDidChange, object: nil, userInfo: ["isFavoriteToggle": true])
    }

    func contacts(inGroup groupID: UUID) -> [Contact] {
        contacts.filter { $0.groupIDs.contains(groupID) }
            .sorted { $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending }
    }
}

// MARK: - Προσαρμοσμένες Ομάδες Επαφών

struct ContactGroup: Codable, Identifiable, Equatable {
    static let nameCharacterLimit = 20

    var id: UUID = UUID()
    var name: String
    var colorHex: String? = nil

    var color: NSColor? {
        guard let colorHex else { return nil }
        return NSColor(hexString: colorHex)
    }

    static func sanitizedName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(nameCharacterLimit))
    }
}

final class ContactGroupStore {
    static let shared = ContactGroupStore()
    private let key = "HelloMacContactGroups"
    static let enabledDefaultsKey = "contactGroupsEnabled"

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledDefaultsKey)
            NotificationCenter.default.post(name: .contactGroupsDidChange, object: nil)
        }
    }

    var groups: [ContactGroup] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let decoded = try? JSONDecoder().decode([ContactGroup].self, from: data)
            else { return [] }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(encoded, forKey: key)
            }
        }
    }

    var sortedGroups: [ContactGroup] {
        groups.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func group(withID id: UUID) -> ContactGroup? {
        groups.first { $0.id == id }
    }

    @discardableResult
    func addGroup(name: String, colorHex: String? = nil) -> ContactGroup? {
        let sanitized = ContactGroup.sanitizedName(name)
        guard !sanitized.isEmpty else { return nil }
        guard !groups.contains(where: { $0.name.caseInsensitiveCompare(sanitized) == .orderedSame }) else { return nil }
        let newGroup = ContactGroup(name: sanitized, colorHex: colorHex)
        var list = groups
        list.append(newGroup)
        groups = list
        NotificationCenter.default.post(name: .contactGroupsDidChange, object: nil)
        return newGroup
    }

    func renameGroup(id: UUID, to newName: String) {
        let sanitized = ContactGroup.sanitizedName(newName)
        guard !sanitized.isEmpty else { return }
        var list = groups
        guard let idx = list.firstIndex(where: { $0.id == id }) else { return }
        list[idx].name = sanitized
        groups = list
        NotificationCenter.default.post(name: .contactGroupsDidChange, object: nil)
    }

    func updateColor(id: UUID, colorHex: String?) {
        var list = groups
        guard let idx = list.firstIndex(where: { $0.id == id }) else { return }
        list[idx].colorHex = colorHex
        groups = list
        NotificationCenter.default.post(name: .contactGroupsDidChange, object: nil)
    }

    func deleteGroup(id: UUID) {
        var list = groups
        list.removeAll { $0.id == id }
        groups = list

        var contacts = ContactStore.shared.contacts
        var changed = false
        for i in contacts.indices where contacts[i].groupIDs.contains(id) {
            contacts[i].groupIDs.removeAll { $0 == id }
            changed = true
        }
        if changed {
            ContactStore.shared.contacts = contacts
            NotificationCenter.default.post(name: .contactsDidChange, object: nil)
        }
        NotificationCenter.default.post(name: .contactGroupsDidChange, object: nil)
    }
}

extension Notification.Name {
    static let contactGroupsDidChange = Notification.Name("contactGroupsDidChange")
    static let speedDialSettingsDidChange = Notification.Name("speedDialSettingsDidChange")
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

enum TimeZoneOption: Int, CaseIterable {
    case system = 0
    case custom

    static let defaultsKey = "timeZonePreference"
    static let customIdentifierKey = "customTimeZoneIdentifier"

    var localizedTitle: String {
        switch self {
        case .system: return L("timezone_option_system")
        case .custom: return L("timezone_option_custom")
        }
    }

    static var current: TimeZoneOption {
        let raw = UserDefaults.standard.integer(forKey: defaultsKey)
        return TimeZoneOption(rawValue: raw) ?? .system
    }
}

enum AppTimeZone {
    static var current: TimeZone {
        switch TimeZoneOption.current {
        case .system:
            return TimeZone.current
        case .custom:
            if let identifier = UserDefaults.standard.string(forKey: TimeZoneOption.customIdentifierKey),
               let tz = TimeZone(identifier: identifier) {
                return tz
            }
            return TimeZone.current
        }
    }

    static var calendar: Calendar {
        var cal = Calendar.current
        cal.timeZone = current
        return cal
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

    func records(forContactID contactID: UUID, phone: String? = nil) -> [CallRecord] {
        let sanitizedPhone = phone?.sanitizedForCall
        return records.filter { record in
            if record.contactID == contactID { return true }
            if record.contactID == nil, let sanitizedPhone, !sanitizedPhone.isEmpty {
                return record.phone.sanitizedForCall == sanitizedPhone
            }
            return false
        }
    }

    func records(forPhone phone: String) -> [CallRecord] {
        let target = phone.sanitizedForCall
        return records.filter { $0.contactID == nil && $0.phone.sanitizedForCall == target }
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

extension Array where Element == Contact {
    func sortedByFavoriteOrder() -> [Contact] {
        sorted {
            switch ($0.favoriteSortIndex, $1.favoriteSortIndex) {
            case let (lhs?, rhs?):
                return lhs < rhs
            case (nil, nil):
                break
            case (nil, _):
                return false
            case (_, nil):
                return true
            }
            switch ($0.favoritedAt, $1.favoritedAt) {
            case let (lhs?, rhs?):
                return lhs > rhs
            case (nil, nil):
                return false
            case (nil, _):
                return false
            case (_, nil):
                return true
            }
        }
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

// MARK: - Λειτουργία Απόρρητου (Privacy Mode)
final class PrivacyMode {
    static let shared = PrivacyMode()
    private let key = "privacyModeEnabled"

    private init() {}

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            NotificationCenter.default.post(name: .privacyModeDidChange, object: nil)
        }
    }

    func maskedText(_ original: String) -> String {
        let trimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return original }
        let count = min(max(trimmed.count, 3), 10)
        return String(repeating: "•", count: count)
    }

    var maskedInitials: String { "••" }

    func showBlockedAlert() {
        let alert = NSAlert()
        AccessibilityManager.shared.applyAccessibility(to: alert)
        alert.messageText = L("privacy_mode_blocked_title")
        alert.informativeText = L("privacy_mode_blocked_text")
        alert.addButton(withTitle: L("privacy_mode_blocked_btn"))
        alert.window.appearance = AccessibilityManager.shared.preferredWindowAppearance
        alert.runModal()
    }
}

extension Notification.Name {
    static let privacyModeDidChange = Notification.Name("privacyModeDidChange")
    static let appTimeZoneDidChange = Notification.Name("appTimeZoneDidChange")
}

enum DialerSound {
    private static let sampleRate: Double = 44_100
    private static let toneDuration: Double = 0.09
    private static let rowFrequencies: [Character: Double] = [
        "1": 697, "2": 697, "3": 697,
        "4": 770, "5": 770, "6": 770,
        "7": 852, "8": 852, "9": 852,
        "*": 941, "0": 941, "#": 941
    ]
    private static let colFrequencies: [Character: Double] = [
        "1": 1209, "4": 1209, "7": 1209, "*": 1209,
        "2": 1336, "5": 1336, "8": 1336, "0": 1336,
        "3": 1477, "6": 1477, "9": 1477, "#": 1477
    ]

    private static let fallbackDigit: Character = "0"

    private static var cache: [Character: NSSound] = [:]

    private static func makeWAVData(f1: Double, f2: Double) -> Data {
        let frameCount = Int(sampleRate * toneDuration)
        let fadeSamples = max(1, Int(sampleRate * 0.008))

        var samples = [Int16](repeating: 0, count: frameCount)
        for n in 0..<frameCount {
            let t = Double(n) / sampleRate
            var sample = 0.5 * (sin(2 * .pi * f1 * t) + sin(2 * .pi * f2 * t))
            if n < fadeSamples {
                sample *= Double(n) / Double(fadeSamples)
            } else if n > frameCount - fadeSamples {
                sample *= Double(frameCount - n) / Double(fadeSamples)
            }
            samples[n] = Int16(max(-1, min(1, sample * 0.3)) * Double(Int16.max))
        }

        var data = Data()
        let byteRate = Int(sampleRate) * 2
        let dataSize = frameCount * 2

        func appendLE(_ value: UInt32) { data.append(contentsOf: withUnsafeBytes(of: value.littleEndian, Array.init)) }
        func appendLE(_ value: UInt16) { data.append(contentsOf: withUnsafeBytes(of: value.littleEndian, Array.init)) }

        data.append(contentsOf: "RIFF".utf8)
        appendLE(UInt32(36 + dataSize))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        appendLE(UInt32(16))
        appendLE(UInt16(1))
        appendLE(UInt16(1))
        appendLE(UInt32(sampleRate))
        appendLE(UInt32(byteRate))
        appendLE(UInt16(2))
        appendLE(UInt16(16))
        data.append(contentsOf: "data".utf8)
        appendLE(UInt32(dataSize))
        for sample in samples {
            appendLE(UInt16(bitPattern: sample))
        }

        return data
    }

    private static func sound(for digit: Character) -> NSSound? {
        let key = rowFrequencies[digit] != nil ? digit : fallbackDigit
        if let cached = cache[key] { return cached }
        guard let f1 = rowFrequencies[key], let f2 = colFrequencies[key] else { return nil }
        let wav = makeWAVData(f1: f1, f2: f2)
        guard let sound = NSSound(data: wav) else { return nil }
        cache[key] = sound
        return sound
    }

    private static func play(digit: Character) {
        guard let sound = sound(for: digit) else { return }
        sound.stop()
        sound.play()
    }

    static func playAppKeypadSoundIfEnabled(digit: Character) {
        guard UserDefaults.standard.object(forKey: "playAppKeypadSound") as? Bool ?? true else { return }
        play(digit: digit)
    }

    static func playMenuBarKeypadSoundIfEnabled(digit: Character) {
        guard UserDefaults.standard.object(forKey: "playMenuBarKeypadSound") as? Bool ?? true else { return }
        play(digit: digit)
    }
}