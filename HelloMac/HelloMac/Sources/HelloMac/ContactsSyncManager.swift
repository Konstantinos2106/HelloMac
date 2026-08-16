import Foundation
import Contacts
import AppKit

// MARK: - Συγχρονισμός με το native Contacts framework (iCloud / iPhone)
final class ContactsSyncManager {
    static let shared = ContactsSyncManager()

    private let store = CNContactStore()
    private let didAskKey = "contactsSyncDidAskPermission"
    private let wasAuthorizedBeforeKey = "contactsSyncWasAuthorizedBefore"
    private let autoSyncEnabledKey = "contactsSyncAutoSyncEnabled"
    private let featureEnabledKey = "contactsSyncFeatureEnabled"
    private let lastSyncDateKey = "contactsSyncLastSyncDate"
    private let didShowFeatureAnnouncementKey = "contactsSyncDidShowFeatureAnnouncement"

    private var autoSyncTimer: Timer?
    private let autoSyncInterval: TimeInterval = 15 * 60 // 15 λεπτά

    private init() {
        if isFeatureEnabled && isAutoSyncEnabled {
            startAutoSyncTimer()
        }
    }

    // MARK: - Κύριος διακόπτης λειτουργίας

    var isFeatureEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: featureEnabledKey) }
        set {
            let oldValue = UserDefaults.standard.bool(forKey: featureEnabledKey)
            UserDefaults.standard.set(newValue, forKey: featureEnabledKey)

            if newValue && !oldValue {
                if UserDefaults.standard.object(forKey: autoSyncEnabledKey) == nil {
                    isAutoSyncEnabled = true
                }
                if isAutoSyncEnabled {
                    startAutoSyncTimer()
                }
            } else if !newValue {
                stopAutoSyncTimer()
            }

            NotificationCenter.default.post(name: .contactsSyncSettingsDidChange, object: nil)
        }
    }

    // MARK: - Δικαιώματα

    var authorizationStatus: CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    var isAuthorized: Bool {
        return authorizationStatus == .authorized
    }

    var hasAskedBefore: Bool {
        get { UserDefaults.standard.bool(forKey: didAskKey) }
        set { UserDefaults.standard.set(newValue, forKey: didAskKey) }
    }

    private(set) var wasAuthorizedBefore: Bool {
        get { UserDefaults.standard.bool(forKey: wasAuthorizedBeforeKey) }
        set { UserDefaults.standard.set(newValue, forKey: wasAuthorizedBeforeKey) }
    }

    var hasShownFeatureAnnouncement: Bool {
        get { UserDefaults.standard.bool(forKey: didShowFeatureAnnouncementKey) }
        set { UserDefaults.standard.set(newValue, forKey: didShowFeatureAnnouncementKey) }
    }

    var isAutoSyncEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: autoSyncEnabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: autoSyncEnabledKey)
            if newValue && isFeatureEnabled {
                startAutoSyncTimer()
            } else {
                stopAutoSyncTimer()
            }
            NotificationCenter.default.post(name: .contactsSyncSettingsDidChange, object: nil)
        }
    }

    private(set) var lastSyncDate: Date? {
        get { UserDefaults.standard.object(forKey: lastSyncDateKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastSyncDateKey) }
    }

    var lastSyncDisplayText: String {
        guard let date = lastSyncDate else { return L("contacts_sync_never") }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: Locale.preferredLanguages.first?.hasPrefix("el") ?? true ? "el_GR" : "en_US")
        formatter.timeZone = AppTimeZone.current
        return formatter.string(from: date)
    }

    // MARK: - Background auto-sync

    private func startAutoSyncTimer() {
        stopAutoSyncTimer()
        guard isFeatureEnabled, isAutoSyncEnabled, isAuthorized else { return }
        autoSyncTimer = Timer.scheduledTimer(withTimeInterval: autoSyncInterval, repeats: true) { [weak self] _ in
            self?.performBackgroundSync()
        }
    }

    private func stopAutoSyncTimer() {
        autoSyncTimer?.invalidate()
        autoSyncTimer = nil
    }

    private func performBackgroundSync() {
        guard isFeatureEnabled, isAutoSyncEnabled, isAuthorized else { return }
        syncNow { _ in
        }
    }

   func resumeAutoSyncIfNeeded() {
        let status = authorizationStatus
        let wasDeniedLastTime = UserDefaults.standard.bool(forKey: "contactsSyncWasDeniedLastTime")

        if status == .authorized {
            wasAuthorizedBefore = true
            if wasDeniedLastTime {
                UserDefaults.standard.set(false, forKey: "contactsSyncWasDeniedLastTime")
                isFeatureEnabled = true
                DispatchQueue.main.async {
                    (NSApp.delegate as? AppDelegate)?.syncWithSystemContacts()
                }
            }
        } else if status == .denied || status == .restricted {
            UserDefaults.standard.set(true, forKey: "contactsSyncWasDeniedLastTime")
        }

        if isFeatureEnabled {
            switch status {
            case .authorized:
                if isAutoSyncEnabled {
                    startAutoSyncTimer()
                }
            case .notDetermined:
                requestAccess { [weak self] granted in
                    guard let self = self else { return }
                    if granted {
                        self.wasAuthorizedBefore = true
                        if self.isAutoSyncEnabled {
                            self.startAutoSyncTimer()
                        }
                        (NSApp.delegate as? AppDelegate)?.syncWithSystemContacts()
                    } else {
                        self.isFeatureEnabled = false
                    }
                }
            case .denied, .restricted:
                isFeatureEnabled = false
                if wasAuthorizedBefore {
                    NotificationCenter.default.post(name: .contactsSyncShouldShowPermissionLostPrompt, object: nil)
                }
            @unknown default:
                break
            }
        }
    }

    func requestAccess(completion: @escaping (Bool) -> Void) {
        hasAskedBefore = true

        switch authorizationStatus {
        case .authorized:
            wasAuthorizedBefore = true
            completion(true)
        case .notDetermined:
            store.requestAccess(for: .contacts) { [weak self] granted, _ in
                DispatchQueue.main.async {
                    if granted {
                        self?.wasAuthorizedBefore = true
                    }
                    completion(granted)
                }
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    func openSystemPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Ανάγνωση επαφών

    private func fetchSystemContacts() throws -> [CNContact] {
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactImageDataKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor,
            CNContactIdentifierKey as CNKeyDescriptor
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .givenName

        var results: [CNContact] = []
        try store.enumerateContacts(with: request) { contact, _ in
            if !contact.phoneNumbers.isEmpty {
                results.append(contact)
            }
        }
        return results
    }

    struct SyncResult {
        var added: Int = 0
        var updated: Int = 0
        var total: Int = 0
    }

    func syncNow(completion: @escaping (Result<SyncResult, Error>) -> Void) {
        requestAccess { granted in
            guard granted else {
                completion(.failure(ContactsSyncError.notAuthorized))
                return
            }

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let systemContacts = try self.fetchSystemContacts()
                    let result = self.merge(systemContacts: systemContacts)
                    DispatchQueue.main.async {
                        self.lastSyncDate = Date()
                        NotificationCenter.default.post(name: .contactsDidChange, object: nil)
                        NotificationCenter.default.post(name: .contactsSyncSettingsDidChange, object: nil)
                        completion(.success(result))
                    }
                } catch {
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                }
            }
        }
    }

    private func merge(systemContacts: [CNContact]) -> SyncResult {
        var localContacts = ContactStore.shared.contacts
        var result = SyncResult()
        result.total = systemContacts.count

        var indexByExternalID: [String: Int] = [:]
        for (idx, c) in localContacts.enumerated() {
            if let ext = c.externalIdentifier {
                indexByExternalID[ext] = idx
            }
        }

        for cn in systemContacts {
            let firstName = cn.givenName
            let lastName = cn.familyName
            let phone = cn.phoneNumbers.first?.value.stringValue ?? ""
            guard !phone.isEmpty else { continue }

            var imageFileName: String? = nil
            if let data = cn.imageData ?? cn.thumbnailImageData, let nsImage = NSImage(data: data) {
                imageFileName = ContactImageStore.saveImage(nsImage)
            }

            if let existingIdx = indexByExternalID[cn.identifier] {
                var existing = localContacts[existingIdx]
                var changed = false
                if existing.firstName != firstName { existing.firstName = firstName; changed = true }
                if existing.lastName != lastName { existing.lastName = lastName; changed = true }
                if existing.phone != phone { existing.phone = phone; changed = true }
                if let img = imageFileName, existing.imageFileName == nil {
                    existing.imageFileName = img
                    changed = true
                }
                if changed {
                    localContacts[existingIdx] = existing
                    result.updated += 1
                }
            } else {
                var newContact = Contact(
                    firstName: firstName,
                    lastName: lastName,
                    phone: phone,
                    imageFileName: imageFileName
                )
                newContact.externalIdentifier = cn.identifier
                localContacts.append(newContact)
                result.added += 1
            }
        }

        if result.added > 0 || result.updated > 0 {
            ContactStore.shared.contacts = localContacts
        }
        return result
    }

    // MARK: - Επαναφορά εργοστασιακών ρυθμίσεων

    func factoryReset() {
        stopAutoSyncTimer()

        // 1. Επαφές & ιστορικό
        ContactStore.shared.contacts = []
        HistoryStore.shared.clear()

        // 2. Αποθηκευμένες φωτογραφίες επαφών
        let fm = FileManager.default
        if let items = try? fm.contentsOfDirectory(at: ContactImageStore.directoryURL, includingPropertiesForKeys: nil) {
            for item in items {
                try? fm.removeItem(at: item)
            }
        }

        // 3. Όλες οι ρυθμίσεις της εφαρμογής
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        } else {
            let defaults = UserDefaults.standard
            for key in defaults.dictionaryRepresentation().keys {
                defaults.removeObject(forKey: key)
            }
        }
        UserDefaults.standard.synchronize()

        NotificationCenter.default.post(name: .contactsDidChange, object: nil)
        NotificationCenter.default.post(name: NSNotification.Name("historyDidChange"), object: nil)
        NotificationCenter.default.post(name: .contactsSyncSettingsDidChange, object: nil)
        NotificationCenter.default.post(name: NSNotification.Name("UpdateUIVisibility"), object: nil)
    }
}

enum ContactsSyncError: LocalizedError {
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return L("contacts_sync_not_authorized")
        }
    }
}

extension Notification.Name {
    static let contactsSyncSettingsDidChange = Notification.Name("contactsSyncSettingsDidChange")
    static let contactsSyncShouldShowPermissionLostPrompt = Notification.Name("contactsSyncShouldShowPermissionLostPrompt")
}
