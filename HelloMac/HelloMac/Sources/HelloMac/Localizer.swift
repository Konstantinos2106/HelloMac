import Foundation

func L(_ key: String, _ arg: String = "") -> String {
    let isGreek = Locale.preferredLanguages.first?.hasPrefix("el") ?? true
    
    let strings: [String: (el: String, en: String)] = [
        "about_menu": ("Σχετικά με το HelloMac", "About HelloMac"),
        "about_text": ("Έκδοση: 2.0\n\nKonstantinos2106\n\nΠραγματοποιήστε κλήσεις απευθείας από το Mac σας μέσω του iPhone", "Version: 2.0\n\nKonstantinos2106\n\nMake calls directly from your Mac via your iPhone"),
        "check_updates": ("Έλεγχος για Ενημερώσεις...", "Check for Updates..."),
        "exit": ("Έξοδος", "Quit"),
        "tools": ("Εργαλεία", "Tools"),
        "contacts": ("Επαφές", "Contacts"),
        "keypad": ("Πληκτρολόγιο", "Keypad"),
        "add_contact_menu": ("Προσθήκη Επαφής", "Add Contact"),
        "remove_contact_menu": ("Διαγραφή Επαφής", "Remove Contact"),
        "add_tooltip": ("Προσθήκη", "Add"),
        "remove_tooltip": ("Διαγραφή", "Delete"),
        "no_contacts": ("Δεν υπάρχουν επαφές.\nΠάτα + για να προσθέσεις.", "No contacts.\nPress + to add."),
        "call_tooltip": ("Κλήση", "Call"),
        "new_contact": ("Νέα Επαφή", "New Contact"),
        "name": ("Όνομα", "Name"),
        "phone_placeholder": ("Τηλέφωνο (π.χ. 6971234567)", "Phone (e.g. +123456789)"),
        "add_btn": ("Προσθήκη", "Add"),
        "cancel_btn": ("Άκυρο", "Cancel"),
        "fill_fields": ("Συμπλήρωσε όνομα και τηλέφωνο", "Please fill in both name and phone number"),
        "select_to_delete": ("Επίλεξε επαφή για διαγραφή", "Select a contact to delete"),
        "delete_btn": ("🗑 Διαγραφή", "🗑 Delete"),
        "close_btn": ("Κλείσιμο", "Close"),
        "select_one_to_delete": ("Επίλεξε μια επαφή για διαγραφή", "Please select a contact to delete"),
        "delete_alert_title": ("Διαγραφή επαφής", "Delete contact"),
        "delete_alert_text": ("Σίγουρα θέλεις να διαγράψεις τον/την \"%@\";", "Are you sure you want to delete \"%@\"?"),
        "ok": ("OK", "OK"),
        
        // --- UPDATER ---
        "update_available": ("Νέα Έκδοση Διαθέσιμη", "Update Available"),
        "update_text": ("Η έκδοση %@ είναι διαθέσιμη!\nΘέλετε να την εγκαταστήσετε τώρα;", "Version %@ is available!\nDo you want to install it now?"),
        "download": ("Εγκατάσταση & Επανεκκίνηση", "Install & Relaunch"),
        "up_to_date": ("Είστε Ενημερωμένοι", "Up to Date"),
        "up_to_date_text": ("Έχετε την πιο πρόσφατη έκδοση του HelloMac.", "You have the latest version of HelloMac."),
        "update_error": ("Σφάλμα Ελέγχου", "Check Failed"),
        "update_error_text": ("Δεν ήταν δυνατός ο έλεγχος για νέες εκδόσεις. Ελέγξτε τη σύνδεσή σας στο διαδίκτυο.", "Could not check for updates. Please check your internet connection."),
        "downloading": ("Λήψη Ενημέρωσης...", "Downloading Update..."),
        "installing": ("Εγκατάσταση... Παρακαλώ περιμένετε.", "Installing... Please wait."),
        "download_error": ("Σφάλμα Λήψης", "Download Error"),
        "download_error_text": ("Υπήρξε πρόβλημα κατά τη λήψη της ενημέρωσης.", "There was a problem downloading the update."), // <-- Εδώ έλειπε το κόμμα!
        
        // --- ΡΥΘΜΙΣΕΙΣ ---
        "settings_menu": ("Ρυθμίσεις...", "Settings..."),
        "settings_title": ("Ρυθμίσεις", "Settings"),
        "tab_updates": ("Ενημερώσεις", "Updates"),
        "tab_appearance": ("Εμφάνιση", "Appearance"),
        "current_version": ("Τρέχουσα έκδοση: %@", "Current version: %@"),
        "check_now": ("Έλεγχος τώρα", "Check Now"),
        "show_contacts_tab": ("Εμφάνιση μενού 'Επαφές'", "Show 'Contacts' menu"),
        "show_keypad_tab": ("Εμφάνιση μενού 'Πληκτρολόγιο'", "Show 'Keypad' menu"),
        "all_features_disabled": ("Όλες οι λειτουργίες είναι κρυφές.", "All features are hidden."),
        "enable_features_btn": ("Άνοιγμα Ρυθμίσεων", "Open Settings")
    ]
    
    guard let translation = strings[key] else { return key }
    let text = isGreek ? translation.el : translation.en
    return arg.isEmpty ? text : String(format: text, arg)
}