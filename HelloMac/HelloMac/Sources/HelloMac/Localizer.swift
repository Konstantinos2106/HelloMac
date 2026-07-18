import Foundation

func L(_ key: String, _ arg: String = "") -> String {
    let isGreek = Locale.preferredLanguages.first?.hasPrefix("el") ?? true
    
    let strings: [String: (el: String, en: String)] = [
        "about_menu": ("Σχετικά με το HelloMac", "About HelloMac"),
        "about_text": ("Έκδοση: 2.2\n\nKonstantinos2106\n\nΠραγματοποιήστε κλήσεις απευθείας από το Mac σας μέσω του iPhone", "Version: 2.2\n\nKonstantinos2106\n\nMake calls directly from your Mac via your iPhone"),
        "check_updates": ("Έλεγχος για Ενημερώσεις...", "Check for Updates..."),
        "exit": ("Έξοδος", "Quit"),
        "tools": ("Εργαλεία", "Tools"),
        "contacts": ("Επαφές", "Contacts"),
        "keypad": ("Πληκτρολόγιο", "Keypad"),
        "favorites": ("Αγαπημένα", "Favorites"),
        "add_contact_menu": ("Προσθήκη Επαφής", "Add Contact"),
        "remove_contact_menu": ("Διαγραφή Επαφής", "Remove Contact"),
        "show_favorites_menu": ("Αγαπημένα", "Favorites"),
        "add_tooltip": ("Προσθήκη", "Add"),
        "remove_tooltip": ("Διαγραφή", "Delete"),
        "no_contacts": ("Δεν υπάρχουν επαφές.\nΠάτα + για να προσθέσεις.", "No contacts.\nPress + to add."),
        "no_favorites": ("Δεν έχεις αγαπημένες επαφές.\nΠάτα τις 3 τελίτσες σε μια επαφή για προσθήκη.", "No favorite contacts.\nTap the 3 dots on a contact to add one."),
        "call_tooltip": ("Κλήση", "Call"),
        "favorite_add_tooltip": ("Προσθήκη στα Αγαπημένα", "Add to Favorites"),
        "favorite_remove_tooltip": ("Αφαίρεση από τα Αγαπημένα", "Remove from Favorites"),
        "new_contact": ("Νέα Επαφή", "New Contact"),
        "name": ("Όνομα", "Name"),
        "last_name": ("Επώνυμο", "Last Name"),
        "phone": ("Τηλέφωνο", "Phone"),
        "first_name_placeholder": ("Όνομα", "First name"),
        "last_name_placeholder": ("Επώνυμο", "Last name"),
        "phone_placeholder": ("Τηλέφωνο", "Phone"),
        "add_btn": ("Προσθήκη", "Add"),
        "cancel_btn": ("Άκυρο", "Cancel"),
        "fill_fields": ("Συμπλήρωσε τουλάχιστον όνομα και τηλέφωνο", "Please fill in at least first name and phone number"),
        "select_to_delete": ("Επίλεξε επαφή για διαγραφή", "Select a contact to delete"),
        "delete_btn": ("Διαγραφή", "Delete"),
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
        "download_error_text": ("Υπήρξε πρόβλημα κατά τη λήψη της ενημέρωσης.", "There was a problem downloading the update."),
        
        // --- ΡΥΘΜΙΣΕΙΣ ---
        "settings_menu": ("Ρυθμίσεις...", "Settings..."),
        "settings_title": ("Ρυθμίσεις", "Settings"),
        "tab_updates": ("Ενημερώσεις", "Updates"),
        "tab_appearance": ("Εμφάνιση", "Appearance"),
        "current_version": ("Τρέχουσα έκδοση: %@", "Current version: %@"),
        "check_now": ("Έλεγχος τώρα", "Check Now"),
        "show_favorites_tab": ("Εμφάνιση μενού «Αγαπημένα»", "Show “Favorites” menu"),
        "show_contacts_tab": ("Εμφάνιση μενού «Επαφές»", "Show “Contacts” menu"),
        "show_keypad_tab": ("Εμφάνιση μενού «Πληκτρολόγιο»", "Show “Keypad” menu"),
        "show_plus_tab": ("Εμφάνιση πλήκτρου «+»", "Show “+” button"),
        "all_features_disabled": ("Όλες οι λειτουργίες είναι κρυφές.", "All features are hidden."),
        "enable_features_btn": ("Άνοιγμα Ρυθμίσεων", "Open Settings"),

        "search_placeholder": ("Αναζήτηση...", "Search..."),
        "no_search_results": ("Δεν βρέθηκαν αποτελέσματα", "No results found"),
        "no_favorites_search": ("Δεν βρέθηκαν αποτελέσματα στα αγαπημένα\nΑναζητήστε την επαφή στις Επαφές", "No results found in favorites\nSearch for the contact in Contacts"),
        "search_visibility": ("Εμφάνιση αναζήτησης:", "Search Bar Visibility:"),
        "search_everywhere": ("Παντού", "Everywhere"),
        "search_favorites": ("Μόνο στα Αγαπημένα", "Only Favorites"),
        "search_contacts": ("Μόνο στις Επαφές", "Only Contacts"),
        "search_hidden": ("Πουθενά", "Nowhere"),
        "edit_contact": ("Επεξεργασία Επαφής", "Edit Contact"),
        "save_btn": ("Αποθήκευση", "Save"),
        "paste": ("Επικόλληση", "Paste"),
        "call_in_progress": ("Τερματίστε την τρέχουσα κλήση για να πραγματοποιήσετε μια νέα", "Please end the current call to start a new one")
    ]
    
    guard let translation = strings[key] else { return key }
    let text = isGreek ? translation.el : translation.en
    return arg.isEmpty ? text : String(format: text, arg)
}