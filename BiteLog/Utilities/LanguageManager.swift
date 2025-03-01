import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
  case system = "system"
  case english = "en"
  case japanese = "ja"

  var id: String { self.rawValue }

  var displayName: String {
    switch self {
    case .system:
      return NSLocalizedString("System Default", comment: "Language option")
    case .english:
      return "English"
    case .japanese:
      return "日本語"
    }
  }

  var localeIdentifier: String? {
    switch self {
    case .system:
      return nil
    case .english:
      return "en"
    case .japanese:
      return "ja"
    }
  }
}

class LanguageManager: ObservableObject {
  @AppStorage("appLanguage") var selectedLanguage: AppLanguage = .system {
    didSet {
      updateLocale()
    }
  }

  @Published var locale: Locale = Locale.current

  init() {
    updateLocale()
  }

  func updateLocale() {
    if let identifier = selectedLanguage.localeIdentifier {
      locale = Locale(identifier: identifier)
    } else {
      locale = Locale.current
    }
  }
}
