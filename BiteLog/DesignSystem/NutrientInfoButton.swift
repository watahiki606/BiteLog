import SwiftUI

extension View {
  /// 押すと栄養素の説明を開く。統計の栄養素のリングや行に付ける。
  ///
  /// 見た目はそのままにして、全体を押せる範囲にする。文字の隙間や余白を押しても開くよう、範囲は矩形にする。
  /// ログの合計のカードには付けない。カードは List の1行で、行の中に押せる部品を重ねると「その他の栄養素」の開閉と取り合う
  func opensNutrientInfo(_ action: @escaping () -> Void) -> some View {
    Button(action: action) {
      self.contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityHint(NSLocalizedString("Shows what this nutrient does", comment: "Hint for tapping a nutrient"))
  }
}
