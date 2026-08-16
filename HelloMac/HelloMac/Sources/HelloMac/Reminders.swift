import AppKit
import UserNotifications

extension Notification.Name {
    static let remindersShouldShowInitialPermissionPrompt = Notification.Name("remindersShouldShowInitialPermissionPrompt")
    static let remindersShouldShowPermissionLostPrompt = Notification.Name("remindersShouldShowPermissionLostPrompt")
    static let remindersSettingsDidChange = Notification.Name("remindersSettingsDidChange")
    static let reminderHistoryDidChange = Notification.Name("reminderHistoryDidChange")
}

// MARK: - Reminder Notification Models

struct ScheduledReminder: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var groupID: UUID = UUID()
    var contactName: String
    var phone: String
    var contactID: UUID? = nil
    var baseDate: Date
    var triggerDate: Date
    var message: String
    var createdAt: Date = Date()
    var wasDelivered: Bool = false
    var deliveredAt: Date? = nil
    var wasMissed: Bool = false

    var identifier: String { id.uuidString }
}

class ReminderHistoryStore {
    static let shared = ReminderHistoryStore()
    private let key = "HelloMacReminderHistory"
    private let keepHistoryKey = "keepReminderNotificationHistory"

    var keepHistoryEnabled: Bool {
        get {
            guard ReminderManager.shared.isEnabled else { return false }
            if UserDefaults.standard.object(forKey: keepHistoryKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: keepHistoryKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: keepHistoryKey)
            if !newValue {
                var list = records
                list.removeAll { $0.wasDelivered || $0.wasMissed }
                records = list
            }
            NotificationCenter.default.post(name: .reminderHistoryDidChange, object: nil)
        }
    }

    var records: [ScheduledReminder] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let decoded = try? JSONDecoder().decode([ScheduledReminder].self, from: data)
            else { return [] }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(encoded, forKey: key)
            }
        }
    }

    var upcoming: [ScheduledReminder] {
        records.filter { !$0.wasDelivered && !$0.wasMissed && $0.triggerDate > Date() }
               .sorted { $0.triggerDate < $1.triggerDate }
    }

    var missed: [ScheduledReminder] {
        records.filter { $0.wasMissed }
               .sorted { $0.triggerDate > $1.triggerDate }
    }

    var delivered: [ScheduledReminder] {
        records.filter { $0.wasDelivered }
               .sorted { ($0.deliveredAt ?? $0.triggerDate) > ($1.deliveredAt ?? $1.triggerDate) }
    }

    func add(_ reminder: ScheduledReminder) {
        guard keepHistoryEnabled || upcomingTrackingRequired else { return }
        var list = records
        list.append(reminder)
        records = list
        NotificationCenter.default.post(name: .reminderHistoryDidChange, object: nil)
    }

    private var upcomingTrackingRequired: Bool { true }

    func update(id: UUID, _ mutate: (inout ScheduledReminder) -> Void) {
        var list = records
        guard let idx = list.firstIndex(where: { $0.id == id }) else { return }
        mutate(&list[idx])
        records = list
        NotificationCenter.default.post(name: .reminderHistoryDidChange, object: nil)
    }

    func remove(id: UUID) {
        var list = records
        list.removeAll { $0.id == id }
        records = list
        NotificationCenter.default.post(name: .reminderHistoryDidChange, object: nil)
    }

    func remove(groupID: UUID) {
        var list = records
        list.removeAll { $0.groupID == groupID }
        records = list
        NotificationCenter.default.post(name: .reminderHistoryDidChange, object: nil)
    }

    @discardableResult
    func detectMissedReminders() -> Bool {
        var list = records
        var changed = false
        let now = Date()
        for i in list.indices {
            if !list[i].wasDelivered && !list[i].wasMissed && list[i].triggerDate <= now {
                list[i].wasMissed = true
                changed = true
            }
        }
        if changed {
            records = list
            NotificationCenter.default.post(name: .reminderHistoryDidChange, object: nil)
        }
        return changed
    }

    func markDelivered(id: UUID) {
        update(id: id) { r in
            r.wasDelivered = true
            r.wasMissed = false
            r.deliveredAt = Date()
        }
    }

    func clearOld() {
        var list = records
        list.removeAll { $0.wasDelivered || $0.wasMissed }
        records = list
        NotificationCenter.default.post(name: .reminderHistoryDidChange, object: nil)
    }
}

class ReminderManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderManager()

    private let didAskKey = "remindersDidAskPermission"
    private let wasAuthorizedBeforeKey = "remindersWasAuthorizedBefore"
    private let wasDeniedLastTimeKey = "remindersWasDeniedLastTime"

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "enableCallReminders") }
        set {
            UserDefaults.standard.set(newValue, forKey: "enableCallReminders")
            NotificationCenter.default.post(name: .remindersSettingsDidChange, object: nil)
        }
    }

    func setEnabledByUser(_ newValue: Bool) {
        UserDefaults.standard.set(!newValue, forKey: userExplicitlyDisabledKey)
        isEnabled = newValue
    }

    var hasAskedBefore: Bool {
        get { UserDefaults.standard.bool(forKey: didAskKey) }
        set { UserDefaults.standard.set(newValue, forKey: didAskKey) }
    }

    private(set) var wasAuthorizedBefore: Bool {
        get { UserDefaults.standard.bool(forKey: wasAuthorizedBeforeKey) }
        set { UserDefaults.standard.set(newValue, forKey: wasAuthorizedBeforeKey) }
    }

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func resumeIfNeeded() {
        ReminderHistoryStore.shared.detectMissedReminders()

        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.evaluate(status: settings.authorizationStatus)
            }
        }
    }

    private let userExplicitlyDisabledKey = "remindersUserExplicitlyDisabled"

    private func evaluate(status: UNAuthorizationStatus) {
        let wasDeniedLastTime = UserDefaults.standard.bool(forKey: wasDeniedLastTimeKey)

        if status == .authorized {
            wasAuthorizedBefore = true
            hasAskedBefore = true

            if wasDeniedLastTime {
                UserDefaults.standard.set(false, forKey: wasDeniedLastTimeKey)
                isEnabled = true
            } else if UserDefaults.standard.object(forKey: "enableCallReminders") == nil {
                isEnabled = true
            } else if !isEnabled && !UserDefaults.standard.bool(forKey: userExplicitlyDisabledKey) {
                isEnabled = true
            }
        } else if status == .denied {
            let neverEvaluatedBefore = !hasAskedBefore && !wasDeniedLastTime
            UserDefaults.standard.set(true, forKey: wasDeniedLastTimeKey)
            hasAskedBefore = true

            if isEnabled {
                isEnabled = false
                if wasAuthorizedBefore {
                    NotificationCenter.default.post(name: .remindersShouldShowPermissionLostPrompt, object: nil)
                }
            } else if neverEvaluatedBefore {
                NotificationCenter.default.post(name: .remindersShouldShowPermissionLostPrompt, object: nil)
            }
        }

        if status == .notDetermined && !hasAskedBefore {
            NotificationCenter.default.post(name: .remindersShouldShowInitialPermissionPrompt, object: nil)
        }
    }

    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        hasAskedBefore = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            DispatchQueue.main.async {
                guard let self = self else { completion?(granted); return }
                if granted {
                    self.wasAuthorizedBefore = true
                    if UserDefaults.standard.object(forKey: "enableCallReminders") == nil {
                        self.isEnabled = true
                    }
                } else {
                    self.isEnabled = false
                }
                completion?(granted)
            }
        }
    }

    func openSystemNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }

    @discardableResult
    func scheduleReminder(for contactName: String, phone: String, contactID: UUID? = nil, baseDate: Date, message: String, notifyMinutesBefore: [Int]) -> UUID {
        let groupID = UUID()
        guard isEnabled else { return groupID }

        for minutesBefore in notifyMinutesBefore {
            let triggerDate = baseDate.addingTimeInterval(TimeInterval(-minutesBefore * 60))

            guard triggerDate > Date() else { continue }

            let reminder = ScheduledReminder(
                groupID: groupID,
                contactName: contactName,
                phone: phone,
                contactID: contactID,
                baseDate: baseDate,
                triggerDate: triggerDate,
                message: message
            )
            ReminderHistoryStore.shared.add(reminder)

            let content = UNMutableNotificationContent()
            content.title = L("reminder_notification_title", contactName)
            content.body = message.isEmpty ? L("reminder_notification_default_body") : message
            content.sound = .default
            content.userInfo = ["phone": phone, "reminderID": reminder.id.uuidString]

            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: triggerDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

            let request = UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger)

            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("Σφάλμα προγραμματισμού ειδοποίησης: \(error)")
                }
            }
        }
        return groupID
    }

    func cancelReminderGroup(groupID: UUID) {
        let ids = ReminderHistoryStore.shared.records.filter { $0.groupID == groupID }.map { $0.identifier }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        ReminderHistoryStore.shared.remove(groupID: groupID)
    }

    @discardableResult
    func rescheduleReminderGroup(groupID: UUID, contactName: String, phone: String, contactID: UUID?, baseDate: Date, message: String, notifyMinutesBefore: [Int]) -> UUID {
        cancelReminderGroup(groupID: groupID)
        return scheduleReminder(for: contactName, phone: phone, contactID: contactID, baseDate: baseDate, message: message, notifyMinutesBefore: notifyMinutesBefore)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        markDeliveredIfNeeded(notification.request)
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        markDeliveredIfNeeded(response.notification.request)
        completionHandler()
    }

    private func markDeliveredIfNeeded(_ request: UNNotificationRequest) {
        guard let idString = request.content.userInfo["reminderID"] as? String, let id = UUID(uuidString: idString) else { return }
        ReminderHistoryStore.shared.markDelivered(id: id)
    }
}

// MARK: - Layout Helpers

class FlippedStackView: NSStackView {
    override var isFlipped: Bool { return true }
}

class FormDocumentContainer: NSView {
    override var isFlipped: Bool { return true }
}

// MARK: - Notifications Window Controller

class NotificationsWindowController: NSWindowController, NSWindowDelegate {

    private enum Tab: Int, CaseIterable {
        case new, upcoming, old
    }

    private let filterContact: Contact?

    private var currentTab: Tab = .new

    private var tabButtons: [Tab: NSButton] = [:]
    private var tabBar: NSStackView!
    private var oldTabButton: NSButton?
    private var clearButton: NSButton!

    private var contentContainer: NSView!
    private var newTabView: NSView!
    private var upcomingTabView: NSView!
    private var oldTabView: NSView!

    private var contactPickerControl: ContactPickerControl?
    private var newTabPickerContainer: NSView!
    private var newTabFormContainer: NSView!
    private var newTabFormController: ReminderFormEmbeddedController?
    private var selectedNewContact: Contact?

    private var upcomingStack: NSStackView!
    private var upcomingScroll: NSScrollView!
    private var upcomingEmptyLabel: NSTextField!

    private var oldStack: NSStackView!
    private var oldScroll: NSScrollView!
    private var oldEmptyLabel: NSTextField!

    private var editingWindowController: ReminderSetupWindowController?

    convenience init() {
        self.init(filterContact: nil)
    }

    convenience init(filterContact contact: Contact) {
        self.init(filterContact: Optional(contact))
    }

    private init(filterContact: Contact?) {
        self.filterContact = filterContact

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 460),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = filterContact != nil
            ? L("reminder_setup_title", (PrivacyMode.shared.isEnabled ? PrivacyMode.shared.maskedText(filterContact!.fullName) : filterContact!.fullName))
            : L("notifications_window_title")
        window.appearance = AccessibilityManager.shared.preferredWindowAppearance
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 360, height: 200)

        super.init(window: window)

        self.shouldCascadeWindows = false
        
        window.delegate = self

        setupUI()

        NotificationCenter.default.addObserver(self, selector: #selector(reminderHistoryChanged), name: .reminderHistoryDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reminderHistoryChanged), name: .remindersSettingsDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reminderHistoryChanged), name: .appTimeZoneDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applyAccessibilityToWholeWindow), name: .accessibilitySettingsDidChange, object: nil)
        applyAccessibilityToWholeWindow()
        refreshAll()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func showWindow(_ sender: Any?) {
        if filterContact == nil {
            showTab(.new)
            showContactPicker()
        }
        super.showWindow(sender)
    }
    
    @objc private func applyAccessibilityToWholeWindow() {
        guard let window = window else { return }
        let a11y = AccessibilityManager.shared
        a11y.applyPreferredAppearance(to: window)

        window.a11yBaseBackgroundColor = nil
        window.a11yHasCapturedBackgroundColor = true
        if a11y.isGrayscaleEnabled && a11y.isEffectivelyColorInverted {
            window.backgroundColor = .white
        } else if a11y.isGrayscaleEnabled {
            window.backgroundColor = .black
        } else {
            window.backgroundColor = nil
        }

        guard let contentView = window.contentView else { return }
        AccessibilityManager.shared.applyToViewTree(contentView)
    }

    @objc private func reminderHistoryChanged() {
        refreshAll()
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        let backgroundEffect = NSVisualEffectView()
        backgroundEffect.material = .underWindowBackground
        backgroundEffect.blendingMode = .withinWindow
        backgroundEffect.state = .active
        backgroundEffect.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(backgroundEffect)
        NSLayoutConstraint.activate([
            backgroundEffect.topAnchor.constraint(equalTo: contentView.topAnchor),
            backgroundEffect.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            backgroundEffect.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            backgroundEffect.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])

        let titleText = filterContact != nil
            ? (PrivacyMode.shared.isEnabled ? PrivacyMode.shared.maskedText(filterContact!.fullName) : filterContact!.fullName)
            : L("notifications_window_title")
        let titleLabel = NSTextField(labelWithString: titleText)
        titleLabel.font = AccessibilityManager.shared.adjustedFont(baseSize: 17, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        let clearImg = NSImage(systemSymbolName: "trash", accessibilityDescription: L("clear_history"))
        let clearBtn = NSButton(image: clearImg ?? NSImage(), target: self, action: #selector(clearRecordsTapped))
        clearBtn.bezelStyle = .regularSquare
        clearBtn.isBordered = false
        clearBtn.contentTintColor = NSColor.systemRed
        clearBtn.translatesAutoresizingMaskIntoConstraints = false
        if let cell = clearBtn.cell as? NSButtonCell { cell.imageScaling = .scaleProportionallyUpOrDown }
        contentView.addSubview(clearBtn)
        self.clearButton = clearBtn

        tabBar = NSStackView()
        tabBar.orientation = .horizontal
        tabBar.distribution = .fillEqually
        tabBar.spacing = 6
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(tabBar)

        func makeTab(_ tab: Tab, title: String) -> NSButton {
            let btn = NSButton(title: title, target: self, action: #selector(tabTapped(_:)))
            btn.bezelStyle = .rounded
            btn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            btn.tag = tab.rawValue
            tabButtons[tab] = btn
            return btn
        }

        let newBtn = makeTab(.new, title: L("notif_tab_new"))
        let upcomingBtn = makeTab(.upcoming, title: L("notif_tab_upcoming"))
        let oldBtn = makeTab(.old, title: L("notif_tab_old"))
        oldTabButton = oldBtn

        tabBar.addArrangedSubview(newBtn)
        tabBar.addArrangedSubview(upcomingBtn)
        tabBar.addArrangedSubview(oldBtn)

        contentContainer = NSView()
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contentContainer)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: clearBtn.leadingAnchor, constant: -16),

            clearBtn.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            clearBtn.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            clearBtn.widthAnchor.constraint(equalToConstant: 26),
            clearBtn.heightAnchor.constraint(equalToConstant: 26),

            tabBar.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            tabBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            tabBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            contentContainer.topAnchor.constraint(equalTo: tabBar.bottomAnchor, constant: 12),
            contentContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        setupNewTab()
        setupUpcomingTab()
        setupOldTab()

        showTab(.new)
    }

    private func setupNewTab() {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(view)
        pinToContainer(view)
        newTabView = view

        if let contact = filterContact {
            let formContainer = NSView()
            formContainer.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(formContainer)
            NSLayoutConstraint.activate([
                formContainer.topAnchor.constraint(equalTo: view.topAnchor),
                formContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                formContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                formContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            newTabFormContainer = formContainer
            let formController = ReminderFormEmbeddedController(contact: contact, editingGroupID: nil, prefill: nil, onResizeRequest: { [weak self] in
                self?.updateWindowSize()
            }, onDone: { [weak self] in
                self?.window?.close()
            })
            formController.embed(in: formContainer)
            newTabFormController = formController
            return
        }

        let pickerContainer = NSView()
        pickerContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pickerContainer)
        newTabPickerContainer = pickerContainer

        NSLayoutConstraint.activate([
            pickerContainer.topAnchor.constraint(equalTo: view.topAnchor),
            pickerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pickerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pickerContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        showContactPicker()
    }

    private func showContactPicker() {
        newTabFormController = nil
        newTabFormContainer?.removeFromSuperview()
        newTabFormContainer = nil
        selectedNewContact = nil

        let picker = ContactPickerControl()
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.onSelect = { [weak self] contact in
            self?.contactChosenForNewReminder(contact)
        }
        newTabPickerContainer.subviews.forEach { $0.removeFromSuperview() }
        newTabPickerContainer.addSubview(picker)
        NSLayoutConstraint.activate([
            picker.topAnchor.constraint(equalTo: newTabPickerContainer.topAnchor),
            picker.leadingAnchor.constraint(equalTo: newTabPickerContainer.leadingAnchor),
            picker.trailingAnchor.constraint(equalTo: newTabPickerContainer.trailingAnchor),
            picker.bottomAnchor.constraint(equalTo: newTabPickerContainer.bottomAnchor)
        ])
        contactPickerControl = picker
        updateWindowSize()
        if let contentView = window?.contentView {
            AccessibilityManager.shared.applyToViewTree(contentView)
        }
    }

    private func contactChosenForNewReminder(_ contact: Contact) {
        if PrivacyMode.shared.isEnabled {
            PrivacyMode.shared.showBlockedAlert()
            return
        }
        guard ReminderManager.shared.isEnabled else {
            showRemindersDisabledAlert()
            return
        }
        selectedNewContact = contact
        contactPickerControl?.removeFromSuperview()
        contactPickerControl = nil

        let formContainer = NSView()
        formContainer.translatesAutoresizingMaskIntoConstraints = false
        newTabPickerContainer.addSubview(formContainer)
        NSLayoutConstraint.activate([
            formContainer.topAnchor.constraint(equalTo: newTabPickerContainer.topAnchor),
            formContainer.leadingAnchor.constraint(equalTo: newTabPickerContainer.leadingAnchor),
            formContainer.trailingAnchor.constraint(equalTo: newTabPickerContainer.trailingAnchor),
            formContainer.bottomAnchor.constraint(equalTo: newTabPickerContainer.bottomAnchor)
        ])
        newTabFormContainer = formContainer

        let formController = ReminderFormEmbeddedController(contact: contact, editingGroupID: nil, prefill: nil, onChangeContact: { [weak self] in
            self?.showContactPicker()
        }, onResizeRequest: { [weak self] in
            self?.updateWindowSize()
        }, onDone: { [weak self] in
            self?.window?.close()
        })
        formController.embed(in: formContainer)
        newTabFormController = formController
        updateWindowSize()
    }

    private func showRemindersDisabledAlert() {
        let alert = NSAlert()
        AccessibilityManager.shared.applyAccessibility(to: alert)
        alert.messageText = L("notif_reminders_disabled_title")
        alert.informativeText = L("notif_reminders_disabled_text")
        alert.addButton(withTitle: L("ok"))
        alert.window.appearance = AccessibilityManager.shared.preferredWindowAppearance
        if let appWindow = self.window {
            alert.beginSheetModal(for: appWindow, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    private func setupUpcomingTab() {
        let emptyText = filterContact != nil ? L("notif_no_upcoming_contact") : L("notif_no_upcoming")
        let (view, scroll, stack, empty) = makeListTab(emptyText: emptyText)
        contentContainer.addSubview(view)
        pinToContainer(view)
        upcomingTabView = view
        upcomingScroll = scroll
        upcomingStack = stack
        upcomingEmptyLabel = empty
    }

    private func setupOldTab() {
        let emptyText = filterContact != nil ? L("notif_no_old_contact") : L("notif_no_old")
        let (view, scroll, stack, empty) = makeListTab(emptyText: emptyText)

        contentContainer.addSubview(view)
        pinToContainer(view)
        oldTabView = view
        oldScroll = scroll
        oldStack = stack
        oldEmptyLabel = empty
    }

    private func makeListTab(emptyText: String) -> (NSView, NSScrollView, NSStackView, NSTextField) {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        view.addSubview(scroll)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = stack

        let empty = NSTextField(labelWithString: emptyText)
        empty.alignment = .center
        empty.textColor = NSColor(white: 0.5, alpha: 1)
        empty.font = AccessibilityManager.shared.adjustedFont(baseSize: 13)
        empty.maximumNumberOfLines = 2
        empty.isEditable = false
        empty.isSelectable = false
        empty.isBezeled = false
        empty.drawsBackground = false
        empty.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(empty)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),

            empty.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: scroll.centerYAnchor, constant: -20),
            empty.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            empty.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])

        return (view, scroll, stack, empty)
    }

    private func pinToContainer(_ view: NSView) {
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])
        view.isHidden = true
    }

    @objc private func tabTapped(_ sender: NSButton) {
        guard let tab = Tab(rawValue: sender.tag) else { return }
        showTab(tab)
    }

    private func updateWindowSize() {
        guard let win = self.window, let contentView = win.contentView else { return }
        contentView.layoutSubtreeIfNeeded()
        
        var targetHeight: CGFloat = 460
        if currentTab == .new && selectedNewContact != nil {
            targetHeight = min(contentView.fittingSize.height, 560)
        }
        
        let sizedRect = win.frameRect(forContentRect: NSRect(origin: .zero, size: NSSize(width: 420, height: targetHeight)))
        guard abs(sizedRect.height - win.frame.height) > 0.5 else { return }
        
        var newFrame = win.frame
        let heightDelta = sizedRect.height - win.frame.height
        newFrame.size.height = sizedRect.height
        newFrame.origin.y -= heightDelta

        if win.isVisible {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                win.animator().setFrame(newFrame, display: true)
            }
        } else {
            win.setFrame(newFrame, display: true)
        }
    }

    private func showTab(_ tab: Tab) {
        currentTab = tab
        newTabView.isHidden = tab != .new
        upcomingTabView.isHidden = tab != .upcoming
        oldTabView.isHidden = tab != .old

        for (t, btn) in tabButtons {
            btn.contentTintColor = (t == tab) ? NSColor.systemPurple : nil
        }
        refreshClearButtonVisibility()
        updateWindowSize()
    }

    private func refreshAll() {
        let historyEnabled = ReminderHistoryStore.shared.keepHistoryEnabled
        oldTabButton?.isHidden = !historyEnabled
        if !historyEnabled && currentTab == .old {
            showTab(.new)
        }

        refreshUpcoming()
        refreshOld(historyEnabled: historyEnabled)

        if let contentView = window?.contentView {
            AccessibilityManager.shared.applyToViewTree(contentView)
        }
    }

    private func matchesFilter(_ reminder: ScheduledReminder) -> Bool {
        guard let contact = filterContact else { return true }
        if let contactID = reminder.contactID, contactID == contact.id { return true }
        if reminder.contactID == nil && reminder.phone.sanitizedForCall == contact.phone.sanitizedForCall { return true }
        return false
    }

    private func refreshClearButtonVisibility() {
        guard let clearButton = clearButton else { return }
        if currentTab == .upcoming {
            clearButton.isHidden = false
            let items = ReminderHistoryStore.shared.upcoming.filter(matchesFilter)
            clearButton.isEnabled = !items.isEmpty
        } else if currentTab == .old {
            clearButton.isHidden = false
            let delivered = ReminderHistoryStore.shared.delivered.filter(matchesFilter)
            let missed = ReminderHistoryStore.shared.missed.filter(matchesFilter)
            clearButton.isEnabled = !(delivered.isEmpty && missed.isEmpty)
        } else {
            clearButton.isHidden = true
        }
    }

    private func refreshUpcoming() {
        upcomingStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let items = ReminderHistoryStore.shared.upcoming.filter(matchesFilter)
        upcomingEmptyLabel.isHidden = !items.isEmpty
        
        let allUpcoming = ReminderHistoryStore.shared.upcoming

        for item in items {
            let fullGroup = allUpcoming.filter { $0.groupID == item.groupID }
            let row = NotificationRow(group: [item], kind: .upcoming, editAction: { [weak self] in
                self?.editUpcoming(group: fullGroup)
            }, cancelAction: { [weak self] in
                self?.cancelUpcoming(group: fullGroup)
            }, copyAction: { [weak self] text in
                self?.copyToClipboard(text)
            })
            upcomingStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: upcomingStack.widthAnchor).isActive = true
        }
        refreshClearButtonVisibility()
    }

    private func refreshOld(historyEnabled: Bool) {
        oldStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard historyEnabled else {
            refreshClearButtonVisibility()
            return
        }
        let delivered = ReminderHistoryStore.shared.delivered.filter(matchesFilter)
        let missed = ReminderHistoryStore.shared.missed.filter(matchesFilter)
        let items = (delivered + missed).sorted {
            ($0.deliveredAt ?? $0.triggerDate) > ($1.deliveredAt ?? $1.triggerDate)
        }
        oldEmptyLabel.isHidden = !items.isEmpty
        
        for reminder in items {
            let kind: NotificationRow.Kind = reminder.wasMissed ? .missed : .old
            let row = NotificationRow(group: [reminder], kind: kind, editAction: nil, cancelAction: nil, copyAction: { [weak self] text in
                self?.copyToClipboard(text)
            })
            oldStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: oldStack.widthAnchor).isActive = true
        }
        refreshClearButtonVisibility()
    }

    private func editUpcoming(group: [ScheduledReminder]) {
        if PrivacyMode.shared.isEnabled {
            PrivacyMode.shared.showBlockedAlert()
            return
        }
        guard let first = group.first else { return }
        let contact: Contact
        if let contactID = first.contactID, let existing = ContactStore.shared.contacts.first(where: { $0.id == contactID }) {
            contact = existing
        } else {
            contact = Contact(firstName: first.contactName, lastName: "", phone: first.phone)
        }
        editingWindowController = ReminderSetupWindowController(contact: contact, editingGroupID: first.groupID, groupReminders: group)
        editingWindowController?.showWindow(nil)
        editingWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    private func cancelUpcoming(group: [ScheduledReminder]) {
        guard let groupID = group.first?.groupID else { return }
        ReminderManager.shared.cancelReminderGroup(groupID: groupID)
    }

    @objc private func clearRecordsTapped() {
        let isUpcoming = (currentTab == .upcoming)

        let alert = NSAlert()
        AccessibilityManager.shared.applyAccessibility(to: alert)
        alert.messageText = isUpcoming
            ? (L("reminders_clear_upcoming_title"))
            : (L("reminders_clear_old_title"))

        alert.informativeText = isUpcoming
            ? (L("reminders_clear_upcoming_text"))
            : (L("reminders_clear_old_text"))

        alert.addButton(withTitle: L("delete_btn"))
        alert.addButton(withTitle: L("cancel_btn"))
        alert.buttons[0].hasDestructiveAction = true
        alert.window.appearance = AccessibilityManager.shared.preferredWindowAppearance

        let handle: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn, let self = self else { return }

            if isUpcoming {
                let items = ReminderHistoryStore.shared.upcoming.filter(self.matchesFilter)
                for item in items {
                    ReminderManager.shared.cancelReminderGroup(groupID: item.groupID)
                }
            } else {
                if self.filterContact != nil {
                    let toRemove = (ReminderHistoryStore.shared.delivered + ReminderHistoryStore.shared.missed).filter(self.matchesFilter)
                    for item in toRemove {
                        ReminderHistoryStore.shared.remove(id: item.id)
                    }
                } else {
                    ReminderHistoryStore.shared.clearOld()
                }
            }
        }

        if let appWindow = self.window {
            alert.beginSheetModal(for: appWindow, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - NotificationRow

class NotificationRow: NSView {
    enum Kind { case upcoming, missed, old }

    init(group: [ScheduledReminder], kind: Kind, editAction: (() -> Void)?, cancelAction: (() -> Void)?, copyAction: @escaping (String) -> Void) {
        super.init(frame: .zero)
        setupUI(group: group, kind: kind, editAction: editAction, cancelAction: cancelAction, copyAction: copyAction)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupUI(group: [ScheduledReminder], kind: Kind, editAction: (() -> Void)?, cancelAction: (() -> Void)?, copyAction: @escaping (String) -> Void) {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        guard let first = group.first else { return }

        let iconConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let iconName: String
        let iconColor: NSColor
        switch kind {
        case .upcoming: iconName = "bell.fill"; iconColor = .systemPurple
        case .missed: iconName = "bell.badge.fill"; iconColor = .systemRed
        case .old: iconName = "bell.fill"; iconColor = NSColor(white: 0.5, alpha: 1)
        }
        let iconContainer = NSView()
        iconContainer.wantsLayer = true
        iconContainer.layer?.backgroundColor = NSColor(white: 1, alpha: 0.08).cgColor
        iconContainer.layer?.cornerRadius = 17
        iconContainer.layer?.masksToBounds = true
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        let icon = NSImageView(image: NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?.withSymbolConfiguration(iconConfig) ?? NSImage())
        icon.contentTintColor = iconColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(icon)
        addSubview(iconContainer)

        let displayName = PrivacyMode.shared.isEnabled ? PrivacyMode.shared.maskedText(first.contactName) : first.contactName
        let nameLabel = NSTextField(labelWithString: displayName)
        nameLabel.font = AccessibilityManager.shared.adjustedFont(baseSize: 14, weight: .medium)
        nameLabel.textColor = .white
        nameLabel.isEditable = false
        nameLabel.isSelectable = false
        nameLabel.isBezeled = false
        nameLabel.drawsBackground = false
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        let messageText = first.message.isEmpty ? L("reminder_notification_default_body") : first.message
        let messageLabel = NSTextField(wrappingLabelWithString: PrivacyMode.shared.isEnabled ? PrivacyMode.shared.maskedText(messageText) : messageText)
        messageLabel.font = AccessibilityManager.shared.adjustedFont(baseSize: 12)
        messageLabel.textColor = NSColor(white: 0.65, alpha: 1)
        messageLabel.maximumNumberOfLines = 2
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(messageLabel)

        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        df.timeZone = AppTimeZone.current
        let timeText: String
        switch kind {
        case .upcoming: timeText = df.string(from: first.triggerDate)
        case .missed: timeText = df.string(from: first.triggerDate)
        case .old: timeText = df.string(from: first.deliveredAt ?? first.triggerDate)
        }
        let timeLabel = NSTextField(labelWithString: timeText)
        timeLabel.font = AccessibilityManager.shared.adjustedFont(baseSize: 11)
        timeLabel.textColor = NSColor(white: 0.5, alpha: 1)
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(timeLabel)

        let menuButton = NSButton(frame: .zero)
        menuButton.bezelStyle = .regularSquare
        menuButton.isBordered = false
        menuButton.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: nil)
        menuButton.contentTintColor = NSColor(white: 0.6, alpha: 1)
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        menuButton.target = self
        menuButton.action = #selector(showMenu(_:))
        addSubview(menuButton)
        self.menuButtonRef = menuButton
        self.copyText = "\(displayName): \(messageText)"
        self.copyAction = copyAction
        self.editAction = editAction
        self.cancelAction = cancelAction
        self.kind = kind

        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor(white: 1, alpha: 0.08).cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        NSLayoutConstraint.activate([
            iconContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 34),
            iconContainer.heightAnchor.constraint(equalToConstant: 34),
            icon.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),

            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            nameLabel.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 10),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: menuButton.leadingAnchor, constant: -6),

            messageLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            messageLabel.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 10),
            messageLabel.trailingAnchor.constraint(equalTo: menuButton.leadingAnchor, constant: -6),

            timeLabel.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 2),
            timeLabel.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 10),
            timeLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),

            menuButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            menuButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            menuButton.widthAnchor.constraint(equalToConstant: 22),
            menuButton.heightAnchor.constraint(equalToConstant: 22),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            heightAnchor.constraint(greaterThanOrEqualToConstant: 64)
        ])
    }

    private var menuButtonRef: NSButton?
    private var copyText: String = ""
    private var copyAction: ((String) -> Void)?
    private var editAction: (() -> Void)?
    private var cancelAction: (() -> Void)?
    private var kind: Kind = .old

    @objc private func showMenu(_ sender: NSButton) {
        let menu = NSMenu()

        let copyItem = NSMenuItem(title: L("notif_copy_message"), action: #selector(copyTapped), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)

        if editAction != nil {
            let editItem = NSMenuItem(title: L("notif_edit"), action: #selector(editTapped), keyEquivalent: "")
            editItem.target = self
            menu.addItem(editItem)
        }

        if cancelAction != nil {
            let cancelTitle = kind == .missed ? L("notif_dismiss") : L("notif_cancel_reminder")
            let cancelItem = NSMenuItem(title: cancelTitle, action: #selector(cancelTapped), keyEquivalent: "")
            cancelItem.target = self
            menu.addItem(cancelItem)
        }

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }

    @objc private func copyTapped() { copyAction?(copyText) }
    @objc private func editTapped() { editAction?() }
    @objc private func cancelTapped() { cancelAction?() }
}

// MARK: - ContactPickerControl

class ContactPickerControl: NSView, NSSearchFieldDelegate {
    var onSelect: ((Contact) -> Void)?

    private let searchField = NSSearchField()
    private let resultsScroll = NSScrollView()
    private let resultsStack = FlippedStackView()
    private let emptyLabel = NSTextField(labelWithString: L("no_contacts"))
    private var allContacts: [Contact] = []
    private var filtered: [Contact] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        let hintLabel = NSTextField(labelWithString: L("notif_new_pick_contact"))
        hintLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        hintLabel.textColor = NSColor(white: 0.75, alpha: 1)
        hintLabel.isEditable = false
        hintLabel.isSelectable = false
        hintLabel.isBezeled = false
        hintLabel.drawsBackground = false
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hintLabel)

        searchField.placeholderString = L("notif_new_search_placeholder")
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchChanged)
        addSubview(searchField)

        resultsScroll.translatesAutoresizingMaskIntoConstraints = false
        resultsScroll.hasVerticalScroller = true
        resultsScroll.autohidesScrollers = true
        resultsScroll.scrollerStyle = .overlay
        resultsScroll.drawsBackground = true
        resultsScroll.backgroundColor = NSColor(white: 1, alpha: 0.04)
        resultsScroll.wantsLayer = true
        resultsScroll.layer?.cornerRadius = 8
        resultsScroll.borderType = .noBorder
        addSubview(resultsScroll)

        resultsStack.orientation = .vertical
        resultsStack.spacing = 0
        resultsStack.translatesAutoresizingMaskIntoConstraints = false
        resultsScroll.documentView = resultsStack

        emptyLabel.alignment = .center
        emptyLabel.textColor = NSColor(white: 0.5, alpha: 1)
        emptyLabel.font = AccessibilityManager.shared.adjustedFont(baseSize: 13)
        emptyLabel.maximumNumberOfLines = 2
        emptyLabel.isEditable = false
        emptyLabel.isSelectable = false
        emptyLabel.isBezeled = false
        emptyLabel.drawsBackground = false
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            hintLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            hintLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            hintLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            searchField.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 10),
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            resultsScroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            resultsScroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            resultsScroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            resultsScroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),

            resultsStack.widthAnchor.constraint(equalTo: resultsScroll.contentView.widthAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: resultsScroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: resultsScroll.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24)
        ])

        reloadContacts()
    }

    private func reloadContacts() {
        allContacts = ContactStore.shared.contacts.sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
        applyFilter()
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(self?.searchField)
        }
    }

    @objc private func searchChanged() {
        applyFilter()
    }

    func controlTextDidChange(_ obj: Notification) {
        applyFilter()
    }

    private func applyFilter() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            filtered = allContacts
        } else {
            filtered = allContacts.filter {
                $0.fullName.localizedCaseInsensitiveContains(query) || $0.phone.contains(query)
            }
        }
        rebuildResultRows()
    }

    private func rebuildResultRows() {
        resultsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        emptyLabel.isHidden = !filtered.isEmpty
        resultsScroll.isHidden = filtered.isEmpty

        for contact in filtered {
            let row = ContactPickerRow(contact: contact) { [weak self] chosen in
                self?.onSelect?(chosen)
            }
            resultsStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: resultsStack.widthAnchor).isActive = true
        }

        if let contentView = window?.contentView {
            AccessibilityManager.shared.applyToViewTree(contentView)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.resultsScroll.contentView.scroll(to: NSPoint(x: 0, y: 0))
            self.resultsScroll.reflectScrolledClipView(self.resultsScroll.contentView)
        }
    }
}

class ContactPickerRow: NSView {
    private let contact: Contact
    private let onTap: (Contact) -> Void
    private var hovered = false

    init(contact: Contact, onTap: @escaping (Contact) -> Void) {
        self.contact = contact
        self.onTap = onTap
        super.init(frame: .zero)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        let avatarView = RoundAvatarView(diameter: 28)
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        avatarView.configure(image: contact.image, initials: contact.initials, colorOverride: contact.monogramColor, colorSeed: contact.id.uuidString)
        addSubview(avatarView)

        let displayName = PrivacyMode.shared.isEnabled ? PrivacyMode.shared.maskedText(contact.fullName) : contact.fullName
        let nameLabel = NSTextField(labelWithString: displayName)
        nameLabel.font = AccessibilityManager.shared.adjustedFont(baseSize: 13, weight: .medium)
        nameLabel.textColor = .white
        nameLabel.isEditable = false
        nameLabel.isBezeled = false
        nameLabel.drawsBackground = false
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor(white: 1, alpha: 0.06).cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            avatarView.centerYAnchor.constraint(equalTo: centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 28),
            avatarView.heightAnchor.constraint(equalToConstant: 28),

            nameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 10),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            heightAnchor.constraint(equalToConstant: 44)
        ])

        let click = NSClickGestureRecognizer(target: self, action: #selector(tapped))
        addGestureRecognizer(click)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            NotificationCenter.default.addObserver(self, selector: #selector(checkMouseLocation), name: NSView.boundsDidChangeNotification, object: enclosingScrollView?.contentView)
        } else {
            NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: nil)
        }
    }

    @objc private func checkMouseLocation() {
        guard let window = window else { return }
        let mouseLocation = window.mouseLocationOutsideOfEventStream
        let localPoint = convert(mouseLocation, from: nil)
        if !bounds.contains(localPoint) && hovered {
            hovered = false
            layer?.backgroundColor = .clear
        } else if bounds.contains(localPoint) && !hovered {
            hovered = true
            layer?.backgroundColor = NSColor(white: 1, alpha: 0.06).cgColor
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 1, alpha: 0.06).cgColor
    }
    
    override func mouseExited(with event: NSEvent) {
        hovered = false
        layer?.backgroundColor = .clear
    }

    @objc private func tapped() { onTap(contact) }
}

// MARK: - Reminder Form (embeddable)

class ReminderFormEmbeddedController: NSObject, NSTextFieldDelegate {

    private let contact: Contact
    private var editingGroupID: UUID?
    private let prefill: [ScheduledReminder]?
    private let onChangeContact: (() -> Void)?
    private let onResizeRequest: (() -> Void)?
    private let onDone: () -> Void

    private var containerView: NSView!
    private var messageField: NSTextField!
    private var datePicker: NSDatePicker!
    private var timePicker: NSDatePicker!
    private var setButton: NSButton!

    struct AlertRow {
        let label: NSTextField
        let popup: NSPopUpButton
        let customStack: NSStackView
        let customValue: NSTextField
        let customUnit: NSPopUpButton
    }
    private var alertRows: [AlertRow] = []

    init(contact: Contact, editingGroupID: UUID?, prefill: [ScheduledReminder]?, onChangeContact: (() -> Void)? = nil, onResizeRequest: (() -> Void)? = nil, onDone: @escaping () -> Void) {
        self.contact = contact
        self.editingGroupID = editingGroupID
        self.prefill = prefill
        self.onChangeContact = onChangeContact
        self.onResizeRequest = onResizeRequest
        self.onDone = onDone
        super.init()
    }

    func embed(in container: NSView) {
        containerView = container
        setupUI()
        NotificationCenter.default.addObserver(self, selector: #selector(applyAccessibility), name: .accessibilitySettingsDidChange, object: nil)
        applyAccessibility()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func applyAccessibility() {
        AccessibilityManager.shared.applyToViewTree(containerView)
    }

    private func minutesLabel(_ minutes: Int, isGreek: Bool) -> String {
        if minutes <= 0 {
            return L("reminder_at_event_time")
        } else if minutes % 1440 == 0 {
            let days = minutes / 1440
            return L2("reminder_days_value", "\(days)", days == 1 ? (isGreek ? "α" : "") : (isGreek ? "ες" : "s"))
        } else if minutes % 60 == 0 {
            let hours = minutes / 60
            return L2("reminder_hours_value", "\(hours)", hours == 1 ? (isGreek ? "α" : "") : (isGreek ? "ες" : "s"))
        } else {
            return L("reminder_minutes_value", "\(minutes)")
        }
    }
    
    private func ordinalReminderLabel(_ index: Int) -> String {
        let isGreek = Locale.preferredLanguages.first?.hasPrefix("el") ?? true
        if isGreek {
            return L2("reminder_ordinal_label", "\(index)", "η")
        } else {
            let suffixes = ["th", "st", "nd", "rd", "th", "th"]
            let suffix = (index < 6) ? suffixes[index] : "th"
            return L2("reminder_ordinal_label", "\(index)", suffix)
        }
    }

    private func buildPopup(forRow index: Int, popup: NSPopUpButton) {
        popup.removeAllItems()
        let menu = NSMenu()
        
        if index > 0 {
            let noneItem = NSMenuItem(title: L("reminder_none"), action: nil, keyEquivalent: "")
            noneItem.tag = -2
            menu.addItem(noneItem)
        }
        
        let standardOptions: [(labelKey: String, minutes: Int)] = [
            ("reminder_at_time", 0),
            ("reminder_5_min", 5),
            ("reminder_10_min", 10),
            ("reminder_30_min", 30),
            ("reminder_1_hour", 60)
        ]
        
        for opt in standardOptions {
            let item = NSMenuItem(title: L(opt.labelKey), action: nil, keyEquivalent: "")
            item.tag = opt.minutes
            menu.addItem(item)
        }
        
        let customItem = NSMenuItem(title: L("reminder_custom"), action: nil, keyEquivalent: "")
        customItem.tag = -1
        menu.addItem(customItem)
        
        popup.menu = menu
    }

    private func setupUI() {
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        containerView.addSubview(scroll)

        let documentContainer = FormDocumentContainer()
        documentContainer.translatesAutoresizingMaskIntoConstraints = false

        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 14
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        documentContainer.addSubview(mainStack)
        scroll.documentView = documentContainer

        var headerStack: NSStackView? = nil

        if onChangeContact != nil {
            let displayName = PrivacyMode.shared.isEnabled ? PrivacyMode.shared.maskedText(contact.fullName) : contact.fullName
            let stack = NSStackView()
            stack.orientation = .horizontal
            stack.spacing = 8
            stack.alignment = .firstBaseline

            let titleLabel = NSTextField(labelWithString: displayName)
            titleLabel.font = NSFont.boldSystemFont(ofSize: 15)
            titleLabel.lineBreakMode = .byTruncatingTail
            stack.addArrangedSubview(titleLabel)

            let changeBtn = NSButton(title: L("notif_new_change_contact"), target: self, action: #selector(changeContactTapped))
            changeBtn.bezelStyle = .inline
            changeBtn.isBordered = false
            changeBtn.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            changeBtn.contentTintColor = .systemPurple
            stack.addArrangedSubview(changeBtn)

            mainStack.addArrangedSubview(stack)
            headerStack = stack
        }

        let messageLabel = NSTextField(labelWithString: L("reminder_message_label"))
        messageLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        messageLabel.textColor = NSColor(white: 0.75, alpha: 1)
        mainStack.addArrangedSubview(messageLabel)

        messageField = NSTextField()
        messageField.placeholderString = L("reminder_notification_default_body")
        messageField.translatesAutoresizingMaskIntoConstraints = false
        mainStack.addArrangedSubview(messageField)

        let dateLabel = NSTextField(labelWithString: L("reminder_date_label"))
        dateLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        dateLabel.textColor = NSColor(white: 0.75, alpha: 1)
        mainStack.addArrangedSubview(dateLabel)

        datePicker = NSDatePicker()
        datePicker.datePickerStyle = .textFieldAndStepper
        datePicker.datePickerElements = .yearMonthDay
        datePicker.dateValue = Date().addingTimeInterval(3600)
        datePicker.minDate = Date()
        datePicker.isBordered = false
        datePicker.drawsBackground = false

        timePicker = NSDatePicker()
        timePicker.datePickerStyle = .textFieldAndStepper
        timePicker.datePickerElements = .hourMinute
        timePicker.dateValue = Date().addingTimeInterval(3600)
        timePicker.isBordered = false
        timePicker.drawsBackground = false

        let calendarConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let calendarIcon = NSImageView(image: NSImage(systemSymbolName: "calendar.badge.clock", accessibilityDescription: nil)?.withSymbolConfiguration(calendarConfig) ?? NSImage())
        calendarIcon.contentTintColor = NSColor(white: 0.55, alpha: 1)

        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor(white: 1, alpha: 0.1).cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.widthAnchor.constraint(equalToConstant: 1).isActive = true
        separator.heightAnchor.constraint(equalToConstant: 14).isActive = true

        let dateTimeStack = NSStackView(views: [calendarIcon, datePicker, separator, timePicker])
        dateTimeStack.orientation = .horizontal
        dateTimeStack.spacing = 12
        dateTimeStack.alignment = .centerY

        let dateTimeContainer = NSView()
        dateTimeContainer.wantsLayer = true
        dateTimeContainer.layer?.backgroundColor = NSColor(white: 1, alpha: 0.05).cgColor
        dateTimeContainer.layer?.cornerRadius = 8
        dateTimeContainer.layer?.borderWidth = 1
        dateTimeContainer.layer?.borderColor = NSColor(white: 1, alpha: 0.1).cgColor
        dateTimeContainer.translatesAutoresizingMaskIntoConstraints = false

        dateTimeStack.translatesAutoresizingMaskIntoConstraints = false
        dateTimeContainer.addSubview(dateTimeStack)

        NSLayoutConstraint.activate([
            dateTimeStack.topAnchor.constraint(equalTo: dateTimeContainer.topAnchor, constant: 6),
            dateTimeStack.bottomAnchor.constraint(equalTo: dateTimeContainer.bottomAnchor, constant: -6),
            dateTimeStack.leadingAnchor.constraint(equalTo: dateTimeContainer.leadingAnchor, constant: 12),
            dateTimeStack.trailingAnchor.constraint(equalTo: dateTimeContainer.trailingAnchor, constant: -12)
        ])

        mainStack.addArrangedSubview(dateTimeContainer)

        func createCustomUI() -> (stack: NSStackView, valueField: NSTextField, unitPopup: NSPopUpButton) {
            let valueField = NSTextField()
            valueField.stringValue = "1"
            valueField.translatesAutoresizingMaskIntoConstraints = false
            valueField.widthAnchor.constraint(equalToConstant: 45).isActive = true
            valueField.delegate = self

            let unitPopup = NSPopUpButton(frame: .zero, pullsDown: false)
            unitPopup.addItems(withTitles: [L("reminder_minutes"), L("reminder_hours"), L("reminder_days")])
            unitPopup.selectItem(at: 1)
            unitPopup.target = self
            unitPopup.action = #selector(customUnitChanged(_:))

            let beforeLabel = NSTextField(labelWithString: L("reminder_before"))
            beforeLabel.textColor = .secondaryLabelColor
            beforeLabel.isEditable = false
            beforeLabel.isBordered = false
            beforeLabel.drawsBackground = false

            let stack = NSStackView(views: [valueField, unitPopup, beforeLabel])
            stack.orientation = .horizontal
            stack.spacing = 8
            stack.isHidden = true

            return (stack, valueField, unitPopup)
        }

        for i in 0..<2 {
            let alertLabel = NSTextField(labelWithString: ordinalReminderLabel(i + 1))
            alertLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            alertLabel.textColor = NSColor(white: 0.75, alpha: 1)
            mainStack.addArrangedSubview(alertLabel)

            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            buildPopup(forRow: i, popup: popup)
            popup.target = self
            popup.action = #selector(alertPopupChanged(_:))
            mainStack.addArrangedSubview(popup)

            let custom = createCustomUI()
            mainStack.addArrangedSubview(custom.stack)

            alertRows.append(AlertRow(label: alertLabel, popup: popup, customStack: custom.stack, customValue: custom.valueField, customUnit: custom.unitPopup))
            
            NSLayoutConstraint.activate([
                popup.widthAnchor.constraint(equalTo: mainStack.widthAnchor)
            ])
        }

        let hintStack = NSStackView()
        hintStack.orientation = .horizontal
        hintStack.spacing = 6
        hintStack.alignment = .firstBaseline

        let hintIconConfig = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
        let hintIcon = NSImageView(image: NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)?.withSymbolConfiguration(hintIconConfig) ?? NSImage())
        hintIcon.contentTintColor = NSColor(white: 0.5, alpha: 1)
        hintStack.addArrangedSubview(hintIcon)

        let hintLabel = NSTextField(wrappingLabelWithString: L("reminder_only_if_on_hint"))
        hintLabel.font = NSFont.systemFont(ofSize: 10.5)
        hintLabel.textColor = NSColor(white: 0.5, alpha: 1)
        hintLabel.preferredMaxLayoutWidth = 340 
        hintStack.addArrangedSubview(hintLabel)
        mainStack.addArrangedSubview(hintStack)

        let cancelButton = NSButton(title: L("cancel_btn"), target: self, action: #selector(cancelTapped))
        cancelButton.bezelStyle = .rounded

        setButton = NSButton(title: editingGroupID != nil ? L("save_btn") : L("set_reminder_tooltip"), target: self, action: #selector(setTapped))
        setButton.bezelStyle = .rounded
        setButton.keyEquivalent = "\r"

        let buttonsStack = NSStackView(views: [cancelButton, setButton])
        buttonsStack.orientation = .horizontal
        buttonsStack.spacing = 10
        buttonsStack.translatesAutoresizingMaskIntoConstraints = false
        documentContainer.addSubview(buttonsStack)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: containerView.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),

            mainStack.topAnchor.constraint(equalTo: documentContainer.topAnchor, constant: 16),
            mainStack.leadingAnchor.constraint(equalTo: documentContainer.leadingAnchor, constant: 16),
            mainStack.trailingAnchor.constraint(equalTo: documentContainer.trailingAnchor, constant: -16),

            buttonsStack.topAnchor.constraint(equalTo: mainStack.bottomAnchor, constant: 20),
            buttonsStack.trailingAnchor.constraint(equalTo: documentContainer.trailingAnchor, constant: -16),
            buttonsStack.bottomAnchor.constraint(equalTo: documentContainer.bottomAnchor, constant: -16),

            documentContainer.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            documentContainer.heightAnchor.constraint(equalTo: scroll.heightAnchor),

            messageField.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            hintStack.widthAnchor.constraint(equalTo: mainStack.widthAnchor)
        ])

        if let headerStack = headerStack {
            headerStack.widthAnchor.constraint(lessThanOrEqualTo: mainStack.widthAnchor).isActive = true
        }

        if let prefill = prefill, !prefill.isEmpty {
            let minutesList = prefill.map { r -> Int in
                Int(r.baseDate.timeIntervalSince(r.triggerDate) / 60)
            }
            applyPrefill(minutesList: minutesList)
        } else {
            applyPrefill(minutesList: [0])
        }
    }

    private func collectActiveMinutes() -> [Int] {
        var minutesBefore: [Int] = []
        for row in alertRows {
            let tag = row.popup.selectedTag()
            if tag == -2 { continue }

            let finalMinutes: Int
            if tag == -1 {
                let rawValue = row.customValue.stringValue.trimmingCharacters(in: .whitespaces)
                let val = max(0, Int(rawValue) ?? 0)
                let unitIdx = row.customUnit.indexOfSelectedItem
                let multiplier = [1, 60, 1440][max(0, unitIdx)]
                finalMinutes = val * multiplier
            } else {
                finalMinutes = tag
            }

            if finalMinutes >= 0, !minutesBefore.contains(finalMinutes) {
                minutesBefore.append(finalMinutes)
            }
        }
        return minutesBefore
    }

    @objc private func changeContactTapped() { onChangeContact?() }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, alertRows.contains(where: { $0.customValue === field }) else { return }
        requestResize()
    }
    
    @objc private func customUnitChanged(_ sender: NSPopUpButton) {
        requestResize()
    }

    private func requestResize() {
        if let onResize = onResizeRequest {
            onResize()
        } else {
            guard let win = containerView.window, let contentView = win.contentView else { return }
            contentView.layoutSubtreeIfNeeded()
            var newSize = contentView.fittingSize
            newSize.width = win.frame.width
            
            var frame = win.frame
            let oldHeight = frame.height
            guard abs(oldHeight - newSize.height) > 1 else { return }
            
            frame.origin.y += (oldHeight - newSize.height)
            frame.size.height = newSize.height
            
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.allowsImplicitAnimation = true
                win.animator().setFrame(frame, display: true)
            }
        }
    }

    @objc private func alertPopupChanged(_ sender: NSPopUpButton) {
        let isCustom = (sender.selectedTag() == -1)
        if let row = alertRows.first(where: { $0.popup === sender }) {
            row.customStack.isHidden = !isCustom
        }
        requestResize()
    }

    @objc private func cancelTapped() {
        onDone()
    }

    @objc private func setTapped() {
        if PrivacyMode.shared.isEnabled {
            PrivacyMode.shared.showBlockedAlert()
            return
        }

        let minutesBefore = collectActiveMinutes().sorted(by: <)

        guard !minutesBefore.isEmpty else {
            onDone()
            return
        }

        let dateComps = Calendar.current.dateComponents([.year, .month, .day], from: datePicker.dateValue)
        let timeComps = Calendar.current.dateComponents([.hour, .minute], from: timePicker.dateValue)
        var finalComps = DateComponents()
        finalComps.year = dateComps.year
        finalComps.month = dateComps.month
        finalComps.day = dateComps.day
        finalComps.hour = timeComps.hour
        finalComps.minute = timeComps.minute

        let finalDate = Calendar.current.date(from: finalComps) ?? Date()
        
        if finalDate < Date() {
            let alert = NSAlert()
            AccessibilityManager.shared.applyAccessibility(to: alert)
            alert.messageText = L("reminder_invalid_time_title")
            alert.informativeText = L("reminder_invalid_time_text")
            alert.addButton(withTitle: L("ok"))
            alert.window.appearance = AccessibilityManager.shared.preferredWindowAppearance
            if let win = containerView?.window ?? NSApp.mainWindow {
                alert.beginSheetModal(for: win, completionHandler: nil)
            } else {
                alert.runModal()
            }
            return
        }

        let unreachable = minutesBefore.filter { finalDate.addingTimeInterval(TimeInterval(-$0 * 60)) <= Date() }
        let reachable = minutesBefore.filter { finalDate.addingTimeInterval(TimeInterval(-$0 * 60)) > Date() }

        if !unreachable.isEmpty {
            let isGreek = Locale.preferredLanguages.first?.hasPrefix("el") ?? true
            let alert = NSAlert()
            AccessibilityManager.shared.applyAccessibility(to: alert)
            alert.messageText = L("reminder_some_dont_fit_title")
            let labels = unreachable.sorted(by: <).map { minutesLabel($0, isGreek: isGreek) }.joined(separator: ", ")
            alert.informativeText = L("reminder_unreachable_text", labels)
            alert.addButton(withTitle: L("reminder_continue_btn"))
            alert.addButton(withTitle: L("cancel_btn"))
            alert.window.appearance = AccessibilityManager.shared.preferredWindowAppearance
            let response = alert.runModal()
            guard response == .alertFirstButtonReturn else { return }

            guard !reachable.isEmpty else {
                onDone()
                return
            }
        }

        let finalMinutesBefore = unreachable.isEmpty ? minutesBefore : reachable
        let trimmedMessage = messageField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if let editingGroupID = editingGroupID {
            ReminderManager.shared.rescheduleReminderGroup(
                groupID: editingGroupID,
                contactName: contact.fullName,
                phone: contact.phone,
                contactID: contact.id,
                baseDate: finalDate,
                message: trimmedMessage,
                notifyMinutesBefore: finalMinutesBefore
            )
        } else {
            ReminderManager.shared.scheduleReminder(
                for: contact.fullName,
                phone: contact.phone,
                contactID: contact.id,
                baseDate: finalDate,
                message: trimmedMessage,
                notifyMinutesBefore: finalMinutesBefore
            )
        }

        onDone()
    }

    private func applyPrefill(minutesList: [Int]) {
        let firstResponderField = containerView?.window?.firstResponder as? NSTextView
        let focusedCustomField = alertRows.first { row in
            guard let fieldEditor = firstResponderField else { return false }
            return row.customValue.currentEditor() === fieldEditor
        }?.customValue

        for i in 0..<2 {
            let row = alertRows[i]
            if row.customValue === focusedCustomField { continue }

            if i < minutesList.count {
                let mins = minutesList[i]
                let idx = row.popup.indexOfItem(withTag: mins)

                if idx >= 0, mins != -1 {
                    row.popup.selectItem(at: idx)
                    row.customStack.isHidden = true
                } else {
                    row.popup.selectItem(withTag: -1)
                    row.customStack.isHidden = false
                    if mins > 0 && mins % 1440 == 0 {
                        row.customValue.stringValue = "\(mins / 1440)"
                        row.customUnit.selectItem(at: 2)
                    } else if mins > 0 && mins % 60 == 0 {
                        row.customValue.stringValue = "\(mins / 60)"
                        row.customUnit.selectItem(at: 1)
                    } else {
                        row.customValue.stringValue = "\(max(mins, 0))"
                        row.customUnit.selectItem(at: 0)
                    }
                }
            } else {
                row.popup.selectItem(withTag: i == 0 ? 0 : -2)
                row.customStack.isHidden = true
            }
        }
    }
}

// MARK: - Reminder Setup Window

class ReminderSetupWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {

    private let contact: Contact
    private var editingGroupID: UUID?

    private var messageField: NSTextField!
    private var datePicker: NSDatePicker!
    private var timePicker: NSDatePicker!
    
    private var setButton: NSButton!
    private var cancelButton: NSButton!

    struct AlertRow {
        let label: NSTextField
        let popup: NSPopUpButton
        let customStack: NSStackView
        let customValue: NSTextField
        let customUnit: NSPopUpButton
    }
    private var alertRows: [AlertRow] = []

    convenience init(contact: Contact) {
        self.init(contact: contact, editingGroup: nil, prefill: nil)
    }

    convenience init(contact: Contact, editingGroupID: UUID, groupReminders: [ScheduledReminder]) {
        self.init(contact: contact, editingGroup: editingGroupID, prefill: groupReminders)
    }

    private convenience init(contact: Contact, editingGroup: UUID?, prefill: [ScheduledReminder]?) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 440),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false

        self.init(window: window, contact: contact)
        self.editingGroupID = editingGroup
        window.delegate = self
        
        let displayName = PrivacyMode.shared.isEnabled ? PrivacyMode.shared.maskedText(contact.fullName) : contact.fullName
        window.title = L("reminder_setup_title", displayName)
        
        setupUI()
        
        if let prefill = prefill, !prefill.isEmpty {
            let minutesList = prefill.map { r -> Int in
                Int(r.baseDate.timeIntervalSince(r.triggerDate) / 60)
            }
            applyPrefill(minutesList: minutesList)
        } else {
            applyPrefill(minutesList: [0])
        }

        resizeToFit(animate: false)

        if let mainWindow = NSApp.mainWindow ?? NSApp.windows.first(where: { $0.title == "HelloMac" }) {
            let x = mainWindow.frame.midX - window.frame.width / 2
            let y = mainWindow.frame.midY - window.frame.height / 2
            window.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            window.center()
        }

        NotificationCenter.default.addObserver(self, selector: #selector(applyAccessibilityToWholeWindow), name: .accessibilitySettingsDidChange, object: nil)
        applyAccessibilityToWholeWindow()
    }

    private init(window: NSWindow?, contact: Contact) {
        self.contact = contact
        super.init(window: window)
        self.shouldCascadeWindows = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func applyAccessibilityToWholeWindow() {
        guard let window = window else { return }
        let a11y = AccessibilityManager.shared
        a11y.applyPreferredAppearance(to: window)

        window.a11yBaseBackgroundColor = nil
        window.a11yHasCapturedBackgroundColor = true
        if a11y.isGrayscaleEnabled && a11y.isEffectivelyColorInverted {
            window.backgroundColor = .white
        } else if a11y.isGrayscaleEnabled {
            window.backgroundColor = .black
        } else {
            window.backgroundColor = nil
        }

        guard let contentView = window.contentView else { return }
        AccessibilityManager.shared.applyToViewTree(contentView)
    }
    
    private func resizeToFit(animate: Bool = false) {
        guard let win = window, let contentView = win.contentView else { return }
        contentView.layoutSubtreeIfNeeded()
        
        let targetHeight = min(contentView.fittingSize.height, 520)
        
        var frame = win.frame
        let oldHeight = frame.height
        guard abs(oldHeight - targetHeight) > 1 else { return }
        
        frame.origin.y += (oldHeight - targetHeight)
        frame.size.height = targetHeight
        
        if animate {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.allowsImplicitAnimation = true
                win.animator().setFrame(frame, display: true)
            }
        } else {
            win.setFrame(frame, display: true)
        }
    }

    private func minutesLabel(_ minutes: Int, isGreek: Bool) -> String {
        if minutes <= 0 {
            return L("reminder_at_event_time")
        } else if minutes % 1440 == 0 {
            let days = minutes / 1440
            return L2("reminder_days_value", "\(days)", days == 1 ? (isGreek ? "α" : "") : (isGreek ? "ες" : "s"))
        } else if minutes % 60 == 0 {
            let hours = minutes / 60
            return L2("reminder_hours_value", "\(hours)", hours == 1 ? (isGreek ? "α" : "") : (isGreek ? "ες" : "s"))
        } else {
            return L("reminder_minutes_value", "\(minutes)")
        }
    }
    
    private func ordinalReminderLabel(_ index: Int) -> String {
        let isGreek = Locale.preferredLanguages.first?.hasPrefix("el") ?? true
        if isGreek {
            return L2("reminder_ordinal_label", "\(index)", "η")
        } else {
            let suffixes = ["th", "st", "nd", "rd", "th", "th"]
            let suffix = (index < 6) ? suffixes[index] : "th"
            return L2("reminder_ordinal_label", "\(index)", suffix)
        }
    }

    private func buildPopup(forRow index: Int, popup: NSPopUpButton) {
        popup.removeAllItems()
        let menu = NSMenu()
        
        if index > 0 {
            let noneItem = NSMenuItem(title: L("reminder_none"), action: nil, keyEquivalent: "")
            noneItem.tag = -2
            menu.addItem(noneItem)
        }
        
        let standardOptions: [(labelKey: String, minutes: Int)] = [
            ("reminder_at_time", 0),
            ("reminder_5_min", 5),
            ("reminder_10_min", 10),
            ("reminder_30_min", 30),
            ("reminder_1_hour", 60)
        ]
        
        for opt in standardOptions {
            let item = NSMenuItem(title: L(opt.labelKey), action: nil, keyEquivalent: "")
            item.tag = opt.minutes
            menu.addItem(item)
        }
        
        let customItem = NSMenuItem(title: L("reminder_custom"), action: nil, keyEquivalent: "")
        customItem.tag = -1
        menu.addItem(customItem)
        
        popup.menu = menu
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        let backgroundEffect = NSVisualEffectView()
        backgroundEffect.material = .underWindowBackground
        backgroundEffect.blendingMode = .withinWindow
        backgroundEffect.state = .active
        backgroundEffect.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(backgroundEffect)
        NSLayoutConstraint.activate([
            backgroundEffect.topAnchor.constraint(equalTo: contentView.topAnchor),
            backgroundEffect.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            backgroundEffect.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            backgroundEffect.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        contentView.addSubview(scroll)

        let documentContainer = FormDocumentContainer()
        documentContainer.translatesAutoresizingMaskIntoConstraints = false

        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 16
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        documentContainer.addSubview(mainStack)
        scroll.documentView = documentContainer
        
        let displayName = PrivacyMode.shared.isEnabled ? PrivacyMode.shared.maskedText(contact.fullName) : contact.fullName
        let titleLabel = NSTextField(labelWithString: L("reminder_setup_title", displayName))
        titleLabel.font = NSFont.boldSystemFont(ofSize: 15)
        titleLabel.lineBreakMode = .byTruncatingTail
        mainStack.addArrangedSubview(titleLabel)

        let messageLabel = NSTextField(labelWithString: L("reminder_message_label"))
        messageLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        messageLabel.textColor = NSColor(white: 0.75, alpha: 1)
        mainStack.addArrangedSubview(messageLabel)

        messageField = NSTextField()
        messageField.placeholderString = L("reminder_notification_default_body")
        messageField.translatesAutoresizingMaskIntoConstraints = false
        mainStack.addArrangedSubview(messageField)

        let dateLabel = NSTextField(labelWithString: L("reminder_date_label"))
        dateLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        dateLabel.textColor = NSColor(white: 0.75, alpha: 1)
        mainStack.addArrangedSubview(dateLabel)

        datePicker = NSDatePicker()
        datePicker.datePickerStyle = .textFieldAndStepper
        datePicker.datePickerElements = .yearMonthDay
        datePicker.dateValue = Date().addingTimeInterval(3600)
        datePicker.minDate = Date()
        datePicker.isBordered = false
        datePicker.drawsBackground = false
        
        timePicker = NSDatePicker()
        timePicker.datePickerStyle = .textFieldAndStepper
        timePicker.datePickerElements = .hourMinute
        timePicker.dateValue = Date().addingTimeInterval(3600)
        timePicker.isBordered = false
        timePicker.drawsBackground = false
        
        let calendarConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let calendarIcon = NSImageView(image: NSImage(systemSymbolName: "calendar.badge.clock", accessibilityDescription: nil)?.withSymbolConfiguration(calendarConfig) ?? NSImage())
        calendarIcon.contentTintColor = NSColor(white: 0.55, alpha: 1)
        
        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor(white: 1, alpha: 0.1).cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.widthAnchor.constraint(equalToConstant: 1).isActive = true
        separator.heightAnchor.constraint(equalToConstant: 14).isActive = true
        
        let dateTimeStack = NSStackView(views: [calendarIcon, datePicker, separator, timePicker])
        dateTimeStack.orientation = .horizontal
        dateTimeStack.spacing = 12
        dateTimeStack.alignment = .centerY
        
        let dateTimeContainer = NSView()
        dateTimeContainer.wantsLayer = true
        dateTimeContainer.layer?.backgroundColor = NSColor(white: 1, alpha: 0.05).cgColor
        dateTimeContainer.layer?.cornerRadius = 8
        dateTimeContainer.layer?.borderWidth = 1
        dateTimeContainer.layer?.borderColor = NSColor(white: 1, alpha: 0.1).cgColor
        dateTimeContainer.translatesAutoresizingMaskIntoConstraints = false
        
        dateTimeStack.translatesAutoresizingMaskIntoConstraints = false
        dateTimeContainer.addSubview(dateTimeStack)
        
        NSLayoutConstraint.activate([
            dateTimeStack.topAnchor.constraint(equalTo: dateTimeContainer.topAnchor, constant: 6),
            dateTimeStack.bottomAnchor.constraint(equalTo: dateTimeContainer.bottomAnchor, constant: -6),
            dateTimeStack.leadingAnchor.constraint(equalTo: dateTimeContainer.leadingAnchor, constant: 12),
            dateTimeStack.trailingAnchor.constraint(equalTo: dateTimeContainer.trailingAnchor, constant: -12)
        ])
        
        mainStack.addArrangedSubview(dateTimeContainer)

        func createCustomUI() -> (stack: NSStackView, valueField: NSTextField, unitPopup: NSPopUpButton) {
            let valueField = NSTextField()
            valueField.stringValue = "1"
            valueField.translatesAutoresizingMaskIntoConstraints = false
            valueField.widthAnchor.constraint(equalToConstant: 45).isActive = true
            valueField.delegate = self
            
            let unitPopup = NSPopUpButton(frame: .zero, pullsDown: false)
            unitPopup.addItems(withTitles: [L("reminder_minutes"), L("reminder_hours"), L("reminder_days")])
            unitPopup.selectItem(at: 1)
            unitPopup.target = self
            unitPopup.action = #selector(customUnitChanged(_:))
            
            let beforeLabel = NSTextField(labelWithString: L("reminder_before"))
            beforeLabel.textColor = .secondaryLabelColor
            beforeLabel.isEditable = false
            beforeLabel.isBordered = false
            beforeLabel.drawsBackground = false
            
            let stack = NSStackView(views: [valueField, unitPopup, beforeLabel])
            stack.orientation = .horizontal
            stack.spacing = 8
            stack.isHidden = true
            
            return (stack, valueField, unitPopup)
        }

        for i in 0..<2 {
            let alertLabel = NSTextField(labelWithString: ordinalReminderLabel(i + 1))
            alertLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            alertLabel.textColor = NSColor(white: 0.75, alpha: 1)
            mainStack.addArrangedSubview(alertLabel)

            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            buildPopup(forRow: i, popup: popup)
            popup.target = self
            popup.action = #selector(alertPopupChanged(_:))
            mainStack.addArrangedSubview(popup)

            let custom = createCustomUI()
            mainStack.addArrangedSubview(custom.stack)

            alertRows.append(AlertRow(label: alertLabel, popup: popup, customStack: custom.stack, customValue: custom.valueField, customUnit: custom.unitPopup))
            
            NSLayoutConstraint.activate([
                popup.widthAnchor.constraint(equalTo: mainStack.widthAnchor)
            ])
        }

        let hintStack = NSStackView()
        hintStack.orientation = .horizontal
        hintStack.spacing = 6
        hintStack.alignment = .firstBaseline

        let hintIconConfig = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
        let hintIcon = NSImageView(image: NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)?.withSymbolConfiguration(hintIconConfig) ?? NSImage())
        hintIcon.contentTintColor = NSColor(white: 0.5, alpha: 1)
        hintStack.addArrangedSubview(hintIcon)

        let hintLabel = NSTextField(wrappingLabelWithString: L("reminder_only_if_on_hint"))
        hintLabel.font = NSFont.systemFont(ofSize: 10.5)
        hintLabel.textColor = NSColor(white: 0.5, alpha: 1)
        hintLabel.preferredMaxLayoutWidth = 340
        hintStack.addArrangedSubview(hintLabel)
        mainStack.addArrangedSubview(hintStack)

        cancelButton = NSButton(title: L("cancel_btn"), target: self, action: #selector(cancelTapped))
        cancelButton.bezelStyle = .rounded
        
        setButton = NSButton(title: editingGroupID != nil ? L("save_btn") : L("set_reminder_tooltip"), target: self, action: #selector(setTapped))
        setButton.bezelStyle = .rounded
        setButton.keyEquivalent = "\r"

        let buttonsStack = NSStackView(views: [cancelButton, setButton])
        buttonsStack.orientation = .horizontal
        buttonsStack.spacing = 10
        buttonsStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(buttonsStack)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: contentView.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            mainStack.topAnchor.constraint(equalTo: documentContainer.topAnchor, constant: 16),
            mainStack.leadingAnchor.constraint(equalTo: documentContainer.leadingAnchor, constant: 16),
            mainStack.trailingAnchor.constraint(equalTo: documentContainer.trailingAnchor, constant: -16),
            
            buttonsStack.topAnchor.constraint(equalTo: mainStack.bottomAnchor, constant: 16),
            buttonsStack.trailingAnchor.constraint(equalTo: documentContainer.trailingAnchor, constant: -16),
            buttonsStack.bottomAnchor.constraint(equalTo: documentContainer.bottomAnchor, constant: -16),

            documentContainer.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),

            messageField.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            hintStack.widthAnchor.constraint(equalTo: mainStack.widthAnchor)
        ])
    }

    private func collectActiveMinutes() -> [Int] {
        var minutesBefore: [Int] = []
        for row in alertRows {
            let tag = row.popup.selectedTag()
            if tag == -2 { continue }

            let finalMinutes: Int
            if tag == -1 {
                let rawValue = row.customValue.stringValue.trimmingCharacters(in: .whitespaces)
                let val = max(0, Int(rawValue) ?? 0)
                let unitIdx = row.customUnit.indexOfSelectedItem
                let multiplier = [1, 60, 1440][max(0, unitIdx)]
                finalMinutes = val * multiplier
            } else {
                finalMinutes = tag
            }

            if finalMinutes >= 0, !minutesBefore.contains(finalMinutes) {
                minutesBefore.append(finalMinutes)
            }
        }
        return minutesBefore
    }

    @objc private func alertPopupChanged(_ sender: NSPopUpButton) {
        let isCustom = (sender.selectedTag() == -1)
        if let row = alertRows.first(where: { $0.popup === sender }) {
            row.customStack.isHidden = !isCustom
        }
        resizeToFit(animate: true)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, alertRows.contains(where: { $0.customValue === field }) else { return }
        resizeToFit(animate: true)
    }
    
    @objc private func customUnitChanged(_ sender: NSPopUpButton) {
        resizeToFit(animate: true)
    }

    @objc private func cancelTapped() {
        window?.close()
    }

    @objc private func setTapped() {
        if PrivacyMode.shared.isEnabled {
            PrivacyMode.shared.showBlockedAlert()
            return
        }

        let minutesBefore = collectActiveMinutes().sorted(by: <)

        guard !minutesBefore.isEmpty else {
            window?.close()
            return
        }

        let dateComps = Calendar.current.dateComponents([.year, .month, .day], from: datePicker.dateValue)
        let timeComps = Calendar.current.dateComponents([.hour, .minute], from: timePicker.dateValue)
        var finalComps = DateComponents()
        finalComps.year = dateComps.year
        finalComps.month = dateComps.month
        finalComps.day = dateComps.day
        finalComps.hour = timeComps.hour
        finalComps.minute = timeComps.minute

        let finalDate = Calendar.current.date(from: finalComps) ?? Date()
        
        if finalDate < Date() {
            let alert = NSAlert()
            AccessibilityManager.shared.applyAccessibility(to: alert)
            alert.messageText = L("reminder_invalid_time_title")
            alert.informativeText = L("reminder_invalid_time_text")
            alert.addButton(withTitle: L("ok"))
            alert.window.appearance = AccessibilityManager.shared.preferredWindowAppearance
            if let win = window {
                alert.beginSheetModal(for: win, completionHandler: nil)
            } else {
                alert.runModal()
            }
            return
        }

        let unreachable = minutesBefore.filter { finalDate.addingTimeInterval(TimeInterval(-$0 * 60)) <= Date() }
        let reachable = minutesBefore.filter { finalDate.addingTimeInterval(TimeInterval(-$0 * 60)) > Date() }

        if !unreachable.isEmpty {
            let isGreek = Locale.preferredLanguages.first?.hasPrefix("el") ?? true
            let alert = NSAlert()
            AccessibilityManager.shared.applyAccessibility(to: alert)
            alert.messageText = L("reminder_some_dont_fit_title")
            let labels = unreachable.sorted(by: <).map { minutesLabel($0, isGreek: isGreek) }.joined(separator: ", ")
            alert.informativeText = L("reminder_unreachable_text", labels)
            alert.addButton(withTitle: L("reminder_continue_btn"))
            alert.addButton(withTitle: L("cancel_btn"))
            alert.window.appearance = AccessibilityManager.shared.preferredWindowAppearance
            let response = alert.runModal()
            guard response == .alertFirstButtonReturn else { return }

            guard !reachable.isEmpty else {
                window?.close()
                return
            }
        }

        let finalMinutesBefore = unreachable.isEmpty ? minutesBefore : reachable

        let trimmedMessage = messageField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if let editingGroupID = editingGroupID {
            ReminderManager.shared.rescheduleReminderGroup(
                groupID: editingGroupID,
                contactName: contact.fullName,
                phone: contact.phone,
                contactID: contact.id,
                baseDate: finalDate,
                message: trimmedMessage,
                notifyMinutesBefore: finalMinutesBefore
            )
        } else {
            ReminderManager.shared.scheduleReminder(
                for: contact.fullName,
                phone: contact.phone,
                contactID: contact.id,
                baseDate: finalDate,
                message: trimmedMessage,
                notifyMinutesBefore: finalMinutesBefore
            )
        }

        window?.close()
    }

    private func applyPrefill(minutesList: [Int]) {
        let firstResponderField = window?.firstResponder as? NSTextView
        let focusedCustomField = alertRows.first { row in
            guard let fieldEditor = firstResponderField else { return false }
            return row.customValue.currentEditor() === fieldEditor
        }?.customValue

        for i in 0..<2 {
            let row = alertRows[i]
            if row.customValue === focusedCustomField { continue }

            if i < minutesList.count {
                let mins = minutesList[i]
                let idx = row.popup.indexOfItem(withTag: mins)

                if idx >= 0, mins != -1 {
                    row.popup.selectItem(at: idx)
                    row.customStack.isHidden = true
                } else {
                    row.popup.selectItem(withTag: -1)
                    row.customStack.isHidden = false
                    if mins > 0 && mins % 1440 == 0 {
                        row.customValue.stringValue = "\(mins / 1440)"
                        row.customUnit.selectItem(at: 2)
                    } else if mins > 0 && mins % 60 == 0 {
                        row.customValue.stringValue = "\(mins / 60)"
                        row.customUnit.selectItem(at: 1)
                    } else {
                        row.customValue.stringValue = "\(max(mins, 0))"
                        row.customUnit.selectItem(at: 0)
                    }
                }
            } else {
                row.popup.selectItem(withTag: i == 0 ? 0 : -2)
                row.customStack.isHidden = true
            }
        }
    }
}