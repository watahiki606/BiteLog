import Foundation
import SwiftUI

/// アプリの表示言語。
///
/// 言語は iOS の「優先する言語」で選ぶ。アプリ内に選択肢を持って
/// `AppleLanguages` を書き換えると、次回起動まで反映されないため
/// アプリを終了させるしかなくなる。設定アプリ側なら OS が切り替えを行う。
class LanguageManager: ObservableObject {
  @Published private(set) var locale: Locale = Locale.current

  init() {
    Self.clearLegacyLanguageOverride()
  }

  /// アプリ内に言語選択があった頃のバージョンが書いた `AppleLanguages` を消す。
  ///
  /// 残したままだと設定アプリの「優先する言語」より優先され、
  /// 選択肢を消したあとは二度と言語を変えられなくなる。
  /// 目印は同時に保存していた `appLanguage`。これが無ければ何もしない
  /// （設定アプリ経由で選ばれた `AppleLanguages` を消さないため）。
  private static func clearLegacyLanguageOverride() {
    let defaults = UserDefaults.standard
    guard let legacy = defaults.string(forKey: "appLanguage") else { return }
    defaults.removeObject(forKey: "appLanguage")
    if legacy != "system" {
      defaults.removeObject(forKey: "AppleLanguages")
    }
  }

  /// 設定画面に出す、いま使われている言語の名前。
  var currentLanguageName: String {
    guard let code = Bundle.main.preferredLocalizations.first else {
      return locale.identifier
    }
    return Locale.current.localizedString(forLanguageCode: code) ?? code
  }

  /// 設定アプリのこのアプリのページ。「優先する言語」はここにある。
  func openSystemSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
  }
}
