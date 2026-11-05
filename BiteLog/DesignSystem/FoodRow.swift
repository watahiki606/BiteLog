import SwiftUI

/// 食品1件を表す一覧行。ログ・食品管理・検索結果で共通に使う。
///
/// 左端を上から読めば済むよう、名前・カロリーと量・栄養素を縦に積む。
/// 右端には読み飛ばしてよい補足だけを置く。記録なら時刻、追加の一覧なら追加の印。
/// カロリーを右端に置くと、名前を読んだあと視線が行の端まで飛ぶ。
struct FoodRow: View {
  let title: String
  /// 摂取量や1食分の量。「2 個」「100 g」など。
  let subtitle: String
  let values: NutritionValues
  var isDeleted: Bool = false
  /// 行頭に出す SF Symbol。自分で登録した食品を示す場合などに使う。
  var leadingSymbol: String?
  var leadingSymbolLabel: String?
  /// 名前の行数。一覧では2行に抑えるが、似た名前から1つ選ばせる場面では
  /// 途中で切ると見分けがつかなくなるので nil を渡して全部出す。
  var titleLineLimit: Int? = 2
  /// 名前の右に出す補足。記録した時刻など。
  var trailingText: String?
  /// 行の右端に追加の印を出す。押すとすぐ記録される一覧で、押せることを示す。
  var showsAddIndicator: Bool = false

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      // 行どうしを詰めると、3行が1つの塊に見えて硬くなる。
      // 名前とカロリーは近く、栄養素は一段離して、読む単位ごとに間を取る
      VStack(alignment: .leading, spacing: 0) {
        titleRow

        if isDeleted && dynamicTypeSize.isAccessibilitySize {
          deletedBadge
            .padding(.top, 4)
        }

        amountLine
          .padding(.top, 4)

        NutrientIconRow(values: values)
          .padding(.top, 10)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      if showsAddIndicator {
        Image(systemName: "plus.circle")
          .font(.title2)
          .foregroundStyle(.tint)
          .accessibilityHidden(true)
      }
    }
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private var titleRow: some View {
    // 大きな文字では名前と時刻を横に並べると名前が潰れる。時刻を下へ逃がす
    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: 2) {
        nameLine
        trailingLabel
      }
    } else {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        nameLine
        Spacer(minLength: 0)
        trailingLabel
      }
    }
  }

  @ViewBuilder
  private var trailingLabel: some View {
    if let trailingText {
      Text(trailingText)
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }
  }

  /// 「128 kcal · 1 tbsp」。カロリーは記録で一番見たい数字なので大きく、量は灰色で添える。
  private var amountLine: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        calorieWithIcon
        if !subtitle.isEmpty {
          Text(verbatim: "·")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
          subtitleText
        }
      }

      VStack(alignment: .leading, spacing: 2) {
        calorieWithIcon
        if !subtitle.isEmpty {
          subtitleText
        }
      }
    }
  }

  /// 下の行の栄養素と同じく、カロリーにも色つきの形を添える。
  /// 形が無いのがカロリーだけだと、数字が何の値か一瞬迷う。
  private var calorieWithIcon: some View {
    HStack(alignment: .firstTextBaseline, spacing: 4) {
      Image(systemName: Nutrient.calories.symbolName)
        .font(.subheadline)
        .foregroundStyle(Nutrient.calories.color)
        .accessibilityHidden(true)

      HStack(alignment: .firstTextBaseline, spacing: 2) {
        Text(NutritionFormatter.formatCalories(values.calories))
          .font(.system(.title3, design: .rounded, weight: .bold))
          .monospacedDigit()
          .foregroundStyle(isDeleted ? .secondary : .primary)
        Text(Nutrient.calories.unit)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Nutrient.calories.accessibilityLabel(for: values.calories))
    }
  }

  private var nameLine: some View {
    HStack(alignment: .firstTextBaseline, spacing: 4) {
      if let leadingSymbol {
        Image(systemName: leadingSymbol)
          .font(.caption2)
          .foregroundStyle(.tint)
          .accessibilityLabel(leadingSymbolLabel ?? "")
          .accessibilityHidden(leadingSymbolLabel == nil)
      }

      Text(title)
        .font(.body.weight(.semibold))
        .lineSpacing(3)
        .foregroundStyle(isDeleted ? .secondary : .primary)
        .strikethrough(isDeleted)
        .lineLimit(titleLineLimit)
        // 行数を制限しない場合だけ、必要な高さを確保させる。
        // これが無いと親の提案した高さに収まるよう2行で切られる。
        .fixedSize(horizontal: false, vertical: titleLineLimit == nil)

      if isDeleted && !dynamicTypeSize.isAccessibilitySize {
        deletedBadge
      }
    }
  }

  private var subtitleText: some View {
    Text(subtitle)
      .font(.caption)
      .monospacedDigit()
      .foregroundStyle(.secondary)
  }

  private var deletedBadge: some View {
    Text(NSLocalizedString("(Deleted)", comment: "Deleted Food indicator"))
      .font(.caption2)
      .foregroundStyle(.red)
      .lineLimit(1)
      .fixedSize()
      .padding(.horizontal, 4)
      .padding(.vertical, 2)
      .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
  }
}

extension FoodRow {
  /// 「ブランド名 商品名」の組み立て。
  ///
  /// 実データではブランド名を使わず商品名と同じ語を入れている行が多く、
  /// そのまま連結すると「ゆで卵 ゆで卵」のように同じ語が2回出る。
  /// ブランド名が空か商品名と同じときは商品名だけにする。
  static func displayName(brand: String, product: String) -> String {
    let trimmedBrand = brand.trimmingCharacters(in: .whitespaces)
    let trimmedProduct = product.trimmingCharacters(in: .whitespaces)
    if trimmedBrand.isEmpty || trimmedBrand == trimmedProduct { return trimmedProduct }
    return "\(trimmedBrand) \(trimmedProduct)"
  }

  /// 「2 個」「100 g」のような量の表記。
  static func amountText(_ amount: Double, unit: String) -> String {
    "\(NutritionFormatter.formatNutrition(amount)) \(unit)"
  }

  /// 記録の時刻。0時ちょうどは出さない。
  ///
  /// 以前は日付を動かすと時刻が 00:00 に固定される不具合があり、
  /// 古い記録の多くが 0時ちょうどになっている。食べた時刻ではないので見せない。
  static func timeText(_ date: Date, calendar: Calendar = .current) -> String? {
    let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
    if parts.hour == 0 && parts.minute == 0 && parts.second == 0 { return nil }
    return date.formatted(date: .omitted, time: .shortened)
  }
}
