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

      Text("\(NutritionFormatter.formatNutrition(value))g")
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

// カロリーリングビュー
struct CalorieRingView: View {
  let calories: Double
  let targetCalories: Double

  init(calories: Double, targetCalories: Double = 2000) {
    self.calories = calories
    self.targetCalories = targetCalories
  }

  private var ratio: Double {
    guard targetCalories > 0 else { return 0 }
    return calories / targetCalories
  }

  private var progress: Double {
    min(ratio, 1.0)
  }

  private var isOverTarget: Bool {
    ratio > 1.0
  }

  private var overAmount: Double {
    max(calories - targetCalories, 0)
  }

  private var ringColor: Color {
    isOverTarget ? .red : .orange
  }

  var body: some View {
    ZStack {
      Circle()
        .stroke(ringColor.opacity(0.15), lineWidth: 10)

      Circle()
        .trim(from: 0, to: progress)
        .stroke(
          ringColor,
          style: StrokeStyle(lineWidth: 10, lineCap: .round)
        )
        .rotationEffect(.degrees(-90))
        .animation(.easeInOut(duration: 0.6), value: progress)

      VStack(spacing: 2) {
        Text(NutritionFormatter.formatNutrition(calories))
          .font(.system(size: 20, weight: .bold, design: .rounded))
          .foregroundColor(isOverTarget ? .red : .primary)

        Text("kcal")
          .font(.system(size: 11, weight: .medium))
          .foregroundColor(.secondary)

        if isOverTarget {
          Text("+\(NutritionFormatter.formatNutrition(overAmount))")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundColor(.red)
        }
      }
    }
    .frame(width: 90, height: 90)
  }
}

// マクロ栄養素バー
struct MacroBarView: View {
  let label: String
  let value: Double
  let maxValue: Double
  let color: Color
  let icon: String

  // 超過時の最大表示倍率
  private let maxDisplayRatio: Double = 1.5

  private var ratio: Double {
    guard maxValue > 0 else { return 0 }
    return value / maxValue
  }

  private var isOverTarget: Bool {
    ratio > 1.0
  }

  private var overAmount: Double {
    max(value - maxValue, 0)
  }

  private var barColor: Color {
    isOverTarget ? .red : color
  }

  // バーの幅（通常時は0〜1、超過時は最大1.5まで表示し、バー全体で正規化）
  private var barWidth: Double {
    if isOverTarget {
      // 超過時：全体を150%として表示
      return min(ratio / maxDisplayRatio, 1.0)
    } else {
      return ratio
    }
  }

  // 目標ラインの位置（超過時のみ）
  private var targetLinePosition: Double {
    // 100%の位置 = 1.0 / maxDisplayRatio
    1.0 / maxDisplayRatio
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Image(systemName: icon)
          .font(.system(size: 11, weight: .medium))
          .foregroundColor(barColor)
          .frame(width: 14)

        Text(label)
          .font(.system(size: 12, weight: .medium))
          .foregroundColor(.primary.opacity(0.8))

        Spacer()

        if isOverTarget {
          Text("+\(NutritionFormatter.formatNutrition(overAmount))g")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundColor(.red)
        }

        Text("\(NutritionFormatter.formatNutrition(value))g")
          .font(.system(size: 12, weight: .semibold, design: .rounded))
          .foregroundColor(isOverTarget ? .red : .primary)
      }

      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          // 背景バー
          RoundedRectangle(cornerRadius: 3)
            .fill(barColor.opacity(0.12))
            .frame(height: 5)

          // 進捗バー
          RoundedRectangle(cornerRadius: 3)
            .fill(barColor)
            .frame(
              width: geometry.size.width * barWidth,
              height: 5
            )
            .animation(.easeInOut(duration: 0.5), value: barWidth)

          // 目標ライン（超過時のみ表示）
          if isOverTarget {
            Rectangle()
              .fill(Color.primary.opacity(0.6))
              .frame(width: 2, height: 9)
              .offset(x: geometry.size.width * targetLinePosition - 1)
          }
        }
      }
      .frame(height: 9)
    }
  }
}

// マクロ栄養素チップ (ItemRowView/FoodMasterRow共用)
struct MacroChip: View {
  let label: String
  let value: Double
  let color: Color

  var body: some View {
    HStack(spacing: 2) {
      Circle()
        .fill(color)
        .frame(width: 5, height: 5)

      Text("\(label):\(NutritionFormatter.formatNutrition(value))g")
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(.primary.opacity(0.7))
        .lineLimit(1)
        .fixedSize()
    }
    .padding(.vertical, 2)
    .padding(.horizontal, 5)
    .background(color.opacity(0.08))
    .cornerRadius(4)
  }
}
