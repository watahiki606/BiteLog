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

      // 強制的に言語リソースを切り替える
      UserDefaults.standard.set([identifier], forKey: "AppleLanguages")
      UserDefaults.standard.synchronize()
    } else {
      locale = Locale.current
      // システム言語に戻す
      UserDefaults.standard.removeObject(forKey: "AppleLanguages")
      UserDefaults.standard.synchronize()
    }

    // 言語変更を通知
    objectWillChange.send()
  }
}
