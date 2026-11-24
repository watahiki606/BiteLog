import SwiftUI

extension View {
  /// 入力できる欄を枠で囲み、表示だけの値と見分けられるようにする。
  ///
  /// フォームの TextField は枠を持たず、値が入ると表示だけの行と同じ見た目になる。
  /// どこを直せるのかが分からないので、入力できる欄だけに地と縁を付ける。
  /// 入力中の欄は縁をアクセントの色にして、いまどこに打っているかを示す。
  func inputFieldStyle(isFocused: Bool = false) -> some View {
    let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
    return
      self
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .background(Color(UIColor.tertiarySystemFill), in: shape)
      .overlay(
        shape.strokeBorder(
          isFocused ? Color.accentColor : Color(UIColor.separator), lineWidth: isFocused ? 1.5 : 0.5))
  }
}

/// 数を打つ枠と、その右の単位。
///
/// 単位の幅をそろえて、kcal と g と µg の行で枠の右端が縦にそろうようにする。
struct NumberInputField<Field: Hashable>: View {
  let title: String
  @Binding var text: String
  var placeholder: String = "0"
  let unit: String
  /// キーボードの前後の欄へ移る操作と、入力中の縁の色に使う
  let focus: FocusState<Field?>.Binding
  let field: Field

  @ScaledMetric(relativeTo: .subheadline) private var fieldWidth: CGFloat = 84
  @ScaledMetric(relativeTo: .subheadline) private var unitWidth: CGFloat = 32

  var body: some View {
    HStack(spacing: 6) {
      TextField(placeholder, text: $text)
        .keyboardType(.decimalPad)
        .multilineTextAlignment(.trailing)
        .monospacedDigit()
        .accessibilityLabel(title)
        .focused(focus, equals: field)
        .frame(width: fieldWidth)
        .inputFieldStyle(isFocused: focus.wrappedValue == field)
      Text(unit)
        .foregroundStyle(.secondary)
        .frame(minWidth: unitWidth, alignment: .leading)
        .accessibilityHidden(true)
    }
  }
}
