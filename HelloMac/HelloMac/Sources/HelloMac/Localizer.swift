import Foundation

func L(_ key: String, _ arg: String = "") -> String {
    let isGreek = Locale.preferredLanguages.first?.hasPrefix("el") ?? true
    
    let strings: [String: (el: String, en: String)] = [
        "about_menu": ("Σχετικά με το HelloMac", "About HelloMac"),
        "about_text": ("Έκδοση: 2.3\n\nKonstantinos2106\n\nΠραγματοποιήστε κλήσεις απευθείας από το Mac σας\n\nΣυντόμευση: Ctrl + Option + Cmd + H", "Version: 2.3\n\nKonstantinos2106\n\nMake calls directly from your Mac via your iPhone\n\nShortcut: Ctrl + Option + Cmd + H"),
        "learn_more": ("Δείτε περισσότερα", "Learn More"),
        "check_updates": ("Έλεγχος για Ενημερώσεις...", "Check for Updates..."),
        "exit": ("Έξοδος", "Quit"),
        "tools": ("Εργαλεία", "Tools"),
        "contacts": ("Επαφές", "Contacts"),
        "keypad": ("Πλήκτρα", "Keypad"),
        "favorites": ("Αγαπημένα", "Favorites"),
        "history": ("Ιστορικό", "History"),
        "add_contact_menu": ("Προσθήκη Επαφής", "Add Contact"),
        "remove_contact_menu": ("Διαγραφή Επαφής", "Remove Contact"),
        "show_favorites_menu": ("Αγαπημένα", "Favorites"),
        "add_tooltip": ("Προσθήκη", "Add"),
        "remove_tooltip": ("Διαγραφή", "Delete"),
        "clear_history": ("Καθαρισμός", "Clear"),
        "no_contacts": ("Δεν υπάρχουν επαφές.\nΠάτα + για να προσθέσεις.", "No contacts.\nPress + to add."),
        "no_favorites": ("Δεν έχεις αγαπημένες επαφές.\nΠάτα τις 3 τελίτσες σε μια επαφή για προσθήκη.", "No favorite contacts.\nTap the 3 dots on a contact to add one."),
        "no_history": ("Δεν υπάρχει ιστορικό κλήσεων.", "No call history."),
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
        "clear_history_alert_title": ("Καθαρισμός ιστορικού", "Clear history"),
        "clear_history_alert_text": ("Σίγουρα θέλεις να διαγράψεις όλο το ιστορικό κλήσεων;", "Are you sure you want to clear all call history?"),
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
        "tab_speed_dial": ("Ταχεία Κλήση", "Speed Dial"),
        "tab_info": ("Πληροφορίες", "Info"),
        "app_tagline": ("Εφαρμογή κλήσεων", "Calling app"),
        "app_description": ("Πραγματοποιήστε κλήσεις απευθείας από το Mac σας μέσω του iPhone.\n\nΜια ταχύτατη και ελαφριά εφαρμογή, με μενού αγαπημένων επαφών, ιστορικού κλήσεων, πλήρη λίστα επαφών και κλασικό πληκτρολόγιο.", "Make calls directly from your Mac via your iPhone.\n\nA fast and lightweight app, with a favorites menu, call history, a full contact list, and a classic keypad."),
        "app_website_label": ("Ιστοσελίδα εφαρμογής", "App Website"),
        "app_github_label": ("GitHub", "GitHub"),
        "app_shortcut_label": ("Συντόμευση: Ctrl + Option + Cmd + H", "Shortcut: Ctrl + Option + Cmd + H"),
        "current_version": ("Τρέχουσα έκδοση: %@", "Current version: %@"),
        "check_now": ("Έλεγχος τώρα", "Check Now"),
        "show_favorites_tab": ("Εμφάνιση μενού «Αγαπημένα»", "Show “Favorites” menu"),
        "show_contacts_tab": ("Εμφάνιση μενού «Επαφές»", "Show “Contacts” menu"),
        "show_keypad_tab": ("Εμφάνιση μενού «Πληκτρολόγιο»", "Show “Keypad” menu"),
        "show_history_tab": ("Εμφάνιση μενού «Ιστορικό»", "Show “History” menu"),
        "show_plus_tab": ("Εμφάνιση πλήκτρου «+»", "Show “+” button"),
        "show_contact_history_detail": ("Εμφάνιση ιστορικού στις λεπτομέρειες επαφής", "Show history in contact details"),
        "all_features_disabled": ("Όλες οι λειτουργίες είναι κρυφές.", "All features are hidden."),
        "enable_features_btn": ("Άνοιγμα Ρυθμίσεων", "Open Settings"),
        "enable_speed_dial": ("Ενεργοποίηση Ταχείας Κλήσης", "Enable Speed Dial"),

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
        "call_in_progress": ("Τερματίστε την τρέχουσα κλήση για να πραγματοποιήσετε μια νέα", "Please end the current call to start a new one"),

        // --- ΦΩΤΟΓΡΑΦΙΑ ΕΠΑΦΗΣ / DETAIL PANEL ---
        "choose_photo": ("Επιλογή φωτογραφίας", "Choose photo"),
        "remove_photo": ("Αφαίρεση φωτογραφίας", "Remove photo"),
        "contact_details": ("Στοιχεία Επαφής", "Contact Details"),
        "recent_calls": ("Πρόσφατες κλήσεις", "Recent calls"),
        "no_calls_yet": ("Δεν υπάρχουν κλήσεις ακόμα", "No calls yet"),
        "close_details": ("Κλείσιμο λεπτομερειών", "Close details"),
        "info_tooltip": ("Λεπτομέρειες", "Details"),

        // --- ΠΕΡΙΚΟΠΗ ΦΩΤΟΓΡΑΦΙΑΣ ---
        "crop_photo_title": ("Προσαρμογή Φωτογραφίας", "Adjust Photo"),
        "crop_photo_subtitle": ("Σύρε για μετακίνηση, χρησιμοποίησε το ρυθμιστικό για ζουμ", "Drag to reposition, use the slider to zoom"),
        "use_photo_btn": ("Χρήση Φωτογραφίας", "Use Photo"),
        "adjust_photo": ("Προσαρμογή / Ζουμ...", "Adjust / Zoom..."),

        // --- ΧΡΩΜΑ ΜΟΝΟΓΡΑΜΜΑΤΟΣ ---
        "monogram_color_swatch": ("Χρώμα μονογράμματος", "Monogram color"),
        "monogram_color_wheel": ("Περισσότερα χρώματα...", "More colors..."),

        // --- ΑΥΤΟΜΑΤΗ ΔΙΑΓΡΑΦΗ ΙΣΤΟΡΙΚΟΥ ---
        "history_autodelete_label": ("Αυτόματη διαγραφή ιστορικού:", "Auto-delete history:"),
        "history_autodelete_never": ("Ποτέ", "Never"),
        "history_autodelete_1_day": ("Μετά από 1 ημέρα", "After 1 day"),
        "history_autodelete_1_week": ("Μετά από 1 εβδομάδα", "After 1 week"),
        "history_autodelete_2_weeks": ("Μετά από 2 εβδομάδες", "After 2 weeks"),
        "history_autodelete_1_month": ("Μετά από 1 μήνα", "After 1 month"),
        "history_autodelete_3_months": ("Μετά από 3 μήνες", "After 3 months"),
        "history_autodelete_6_months": ("Μετά από 6 μήνες", "After 6 months"),
        "history_autodelete_1_year": ("Μετά από 1 χρόνο", "After 1 year")
    ]
    
    guard let translation = strings[key] else { return key }
    let text = isGreek ? translation.el : translation.en
    return arg.isEmpty ? text : String(format: text, arg)
}