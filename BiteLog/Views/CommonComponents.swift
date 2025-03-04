import SwiftData
import SwiftUI

// カードビュー
struct CardView<Content: View>: View {
  let title: String
  let content: Content

  init(title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(title)
        .font(.headline)
        .foregroundColor(.primary)

      content
    }
    .padding()
    .background(Color(UIColor.systemBackground))
    .cornerRadius(16)
    .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
  }
}

// カスタムテキストフィールド
struct CustomTextField: View {
  let icon: String
  let placeholder: String
  @Binding var text: String

  var body: some View {
    HStack {
      Image(systemName: icon)
        .foregroundColor(.blue)
        .frame(width: 24)

      TextField(placeholder, text: $text)
        .padding(.vertical, 8)
    }
    .padding(.horizontal, 12)
    .background(Color(UIColor.secondarySystemBackground))
    .cornerRadius(10)
  }
}

// 栄養素入力フィールド
struct NutrientInputField: View {
  let icon: String
  let iconColor: Color
  let label: String
  @Binding var value: String
  let unit: String
  @FocusState private var isFocused: Bool
  var isReadOnly: Bool = true  // デフォルトで読み取り専用

  var body: some View {
    HStack {
      Image(systemName: icon)
        .foregroundColor(iconColor)
        .frame(width: 24)

      Text(label)
        .foregroundColor(.primary)

      Spacer()

      if isReadOnly {
        Text(value.isEmpty ? "0" : value)
          .multilineTextAlignment(.trailing)
          .frame(width: 80)
      } else {
        TextField("0", text: $value)
          .keyboardType(.decimalPad)
          .multilineTextAlignment(.trailing)
          .frame(width: 80)
          .focused($isFocused)
      }

      Text(unit)
        .foregroundColor(.secondary)
        .frame(width: 40, alignment: .leading)
    }
    .padding(.vertical, 12)
    .padding(.horizontal, 12)
    .background(Color(UIColor.secondarySystemBackground))
    .cornerRadius(10)
  }
}

// マクロ栄養素バッジ
struct MacroNutrientBadge: View {
  let label: String
  let value: Double
  let color: Color

  var body: some View {
    HStack(spacing: 4) {
      Text(label)
        .font(.footnote.bold())
        .foregroundColor(color)

      Text("\(value, specifier: "%.2f")g")
        .font(.footnote)
    }
    .padding(.vertical, 4)
    .padding(.horizontal, 8)
    .background(color.opacity(0.1))
    .cornerRadius(8)
  }
}

// ボタンスケールスタイル
struct ScaleButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.98 : 1)
      .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
  }
}
