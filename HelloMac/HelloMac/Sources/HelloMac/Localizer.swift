import Foundation

func L(_ key: String, _ arg: String = "") -> String {
    // Ελέγχει αν η γλώσσα του macOS είναι τα Ελληνικά
    let isGreek = Locale.preferredLanguages.first?.hasPrefix("el") ?? true
    
    // Το λεξικό με τα Ελληνικά και τα Αγγλικά
    let strings: [String: (el: String, en: String)] = [
        "about_menu": ("Σχετικά με το HelloMac", "About HelloMac"),
        "about_text": ("Έκδοση 1.1\n\nΠρογραμματιστής: Konstantinos2106\n\nΓρήγορη κλήση επαφών απευθείας από το Mac!", "Version 1.1\n\nDeveloper: Konstantinos2106\n\nQuickly call contacts directly from your Mac!"),
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
        "ok": ("OK", "OK")
    ]
    
    guard let translation = strings[key] else { return key }
    let text = isGreek ? translation.el : translation.en
    
    // Αν υπάρχει παράμετρος (π.χ. το όνομα στη διαγραφή), την ενσωματώνει
    return arg.isEmpty ? text : String(format: text, arg)
}