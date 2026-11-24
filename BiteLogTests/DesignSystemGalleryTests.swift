import SwiftUI
import Testing
import UIKit

@testable import BiteLog

/// デザインシステムのコンポーネントを実際に描画して PNG に書き出す。
///
/// ライト/ダークと文字サイズの両極端で崩れないかは目で見ないと分からないが、
/// アプリ本体はサインインしないと主要画面に入れない。表示コンポーネントは
/// 素のデータしか受け取らないので、ここで単体で描画して確認する。
///
/// 書き出し先はシミュレータの一時ディレクトリ。実行ログに絶対パスを出すので、
/// そこを開けば4枚の PNG を確認できる。
struct DesignSystemGalleryTests {

  @Test @MainActor func renderGallery() throws {
    let base = FileManager.default.temporaryDirectory
      .appendingPathComponent("bitelog-design-gallery", isDirectory: true)
    try? FileManager.default.removeItem(at: base)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    print("DESIGN_GALLERY_DIR=\(base.path)")

    let cases: [(String, ColorScheme, DynamicTypeSize)] = [
      ("light-default", .light, .large),
      ("dark-default", .dark, .large),
      ("light-ax5", .light, .accessibility5),
      ("dark-ax5", .dark, .accessibility5),
    ]

    for (name, scheme, typeSize) in cases {
      try render(GalleryView(), to: base, name: name, scheme: scheme, typeSize: typeSize)
      try render(RowGalleryView(), to: base, name: "rows-\(name)", scheme: scheme, typeSize: typeSize)
      // 体組成は別の絵にする。1枚にまとめると AX5 で PNG に書き出せない高さになる
      try render(ScreenPartsGalleryView(), to: base, name: "parts-\(name)", scheme: scheme, typeSize: typeSize)
      try render(BodyGalleryView(), to: base, name: "body-\(name)", scheme: scheme, typeSize: typeSize)
      // 統計の「食塩と飽和脂肪酸」は別の絵にする。合計のカードと並べると AX5 で書き出せない高さになる
      if typeSize.isAccessibilitySize {
        // 統計は栄養素を全部1段に並べるので、AX5 の1列では1枚に書き出せない高さになる。見出しごとに分けて描く
        for section in NutrientRingGrid.Section.allCases {
          for withGoals in [true, false] {
            try render(
              AddedNutrientSectionGalleryView(section: section, withGoals: withGoals), to: base,
              name: "added-\(section)\(withGoals ? "" : "-noprofile")-\(name)", scheme: scheme, typeSize: typeSize)
          }
        }
      } else {
        try render(
          AddedNutrientGoalsGalleryView(withGoals: true), to: base, name: "added-\(name)", scheme: scheme,
          typeSize: typeSize)
        try render(
          AddedNutrientGoalsGalleryView(withGoals: false), to: base, name: "added-noprofile-\(name)",
          scheme: scheme, typeSize: typeSize)
      }
      try render(DayRingGalleryView(), to: base, name: "day-rings-\(name)", scheme: scheme, typeSize: typeSize)
      try render(NutrientRowsGalleryView(), to: base, name: "nutrient-rows-\(name)", scheme: scheme, typeSize: typeSize)
      try render(DietQualityScoreGalleryView(), to: base, name: "score-\(name)", scheme: scheme, typeSize: typeSize)
      // 1件の画面は2通りを別の絵にする。並べると AX5 で書き出せない高さになる
      try render(
        BodyDetailGalleryView(withReference: true), to: base, name: "body-detail-\(name)",
        scheme: scheme, typeSize: typeSize)
      try render(
        BodyDetailGalleryView(withReference: false), to: base, name: "body-detail-partial-\(name)",
        scheme: scheme, typeSize: typeSize)
    }
  }

  @MainActor
  private func render(
    _ content: some View, to base: URL, name: String, scheme: ColorScheme,
    typeSize: DynamicTypeSize
  ) throws {
    let renderer = ImageRenderer(
      content:
        content
          .frame(width: 390)
          .background(Color(UIColor.systemGroupedBackground))
          .environment(\.colorScheme, scheme)
          .environment(\.dynamicTypeSize, typeSize)
    )
    renderer.scale = 2
    guard let image = renderer.uiImage, let data = image.pngData() else {
      Issue.record("failed to render \(name)")
      return
    }
    try data.write(to: base.appendingPathComponent("\(name).png"))
  }
}

/// 一覧の行を並べたビュー。サインインしないと実画面を見られないので、
/// 行の見た目だけここで確認できるようにする。
private struct RowGalleryView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(Self.logItems.enumerated()), id: \.offset) { _, item in
        ItemRowView(item: item)
          .padding(.horizontal, 16)
          .padding(.vertical, 8)
        Divider().padding(.leading, 16)
      }

      FoodMasterRow(foodMaster: Self.foodMaster(name: "オートミール", mine: true))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    .padding(.vertical, 8)
    .background(Color(UIColor.secondarySystemGroupedBackground))
  }

  static var logItems: [LogItemDTO] {
    [
      logItem(name: "サラダチキン プレーン", brand: "セブンプレミアム", servings: 1),
      logItem(name: "ごはん", brand: "", servings: 1.5),
      logItem(name: "とても長い商品名のテスト用ダミー食品データ", brand: "ブランド名も長い場合", servings: 2),
      logItem(name: "削除済みマスタの記録", brand: "", servings: 1, deleted: true),
    ]
  }

  static func foodMaster(name: String, mine: Bool) -> FoodMasterDTO {
    FoodMasterDTO(
      id: UUID(), brandName: "", productName: name, calories: 380, dietaryFiber: 9.4,
      netCarbs: 59.5, fat: 7.7, protein: 13.7, portionSize: 100, portionUnit: "g",
      uniqueKey: "|\(name)|g", createdBy: nil, isMine: mine, usageCount: 3,
      lastUsedDate: nil, lastNumberOfServings: 30)
  }

  static func logItem(
    name: String, brand: String, servings: Double, deleted: Bool = false
  ) -> LogItemDTO {
    let snapshot = NutritionSnapshot(
      brandName: brand, productName: name, calories: 114, netCarbs: 0.2, dietaryFiber: 0,
      fat: 1.9, protein: 24.1, portionSize: 1, portionUnit: "個")
    return LogItemDTO(
      id: UUID(), timestamp: Date(), logDate: "2026-09-24", mealType: .lunch,
      numberOfServings: servings, isMasterDeleted: deleted, foodMaster: nil,
      nutritionSnapshot: snapshot)
  }
}

/// 確認用にコンポーネントを一通り並べたビュー。
private struct GalleryView: View {
  private let sample = NutritionValues(
    calories: 523, netCarbs: 62.4, dietaryFiber: 4.2, fat: 18.6, protein: 31.5)

  private let overSample = NutritionValues(
    calories: 2840, netCarbs: 310, dietaryFiber: 12, fat: 92, protein: 155)

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      group("Nutrients") {
        NutrientIconRow(values: sample)
      }

      group("Calorie") {
        VStack(alignment: .leading, spacing: 12) {
          HStack(spacing: 20) {
            CalorieRingView(calories: sample.calories, targetCalories: 2000)
            CalorieRingView(calories: overSample.calories, targetCalories: 2000)
          }
          CalorieLabel(calories: sample.calories)
        }
      }

      group("Bars") {
        VStack(spacing: 8) {
          NutrientBar(nutrient: .protein, value: sample.protein, target: 120)
          NutrientBar(nutrient: .fat, value: overSample.fat, target: 60)
          NutrientBar(nutrient: .netCarbs, value: sample.netCarbs, target: 250)
          NutrientBar(nutrient: .fiber, value: sample.dietaryFiber, target: 20)
        }
      }

      group("Daily Totals") {
        DailyTotalsSample()
      }

      group("Card") {
        CardView(title: "Daily Total") {
          NutrientIconRow(values: overSample)
        }
      }

    }
    .padding()
  }

  private func group<Content: View>(
    _ title: String, @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      content()
    }
  }
}

/// 要約ビューは Binding を持つので、確認用に State を持つ入れ物を挟む。
private struct DailyTotalsSample: View {
  /// 畳みの中は DayRingGalleryView で描く。開くと AX5 で書き出せない高さになる
  @State private var showsAllNutrients = false

  /// 食塩は5品中3品だけ分かっていて目標量を超え、カルシウムは推奨量に届き、ビタミン D はどの品も分からない日
  static let addedTotals: NutrientTotals = {
    func item(salt: Double?, calcium: Double?) -> NutritionValues {
      var amounts = NutrientAmounts(calories: 300, protein: 10, fat: 10, netCarbs: 30, dietaryFiber: 2)
      amounts[.saltEquivalent] = salt
      amounts[.saturatedFat] = 2.4
      amounts[.potassium] = 420
      amounts[.calcium] = calcium
      amounts[.magnesium] = 48
      amounts[.iron] = 1.1
      amounts[.vitaminA] = 120
      amounts[.vitaminC] = 18
      amounts[.zinc] = 1.6
      amounts[.folate] = 44
      return NutritionValues(amounts)
    }
    return NutrientTotals(items: [
      item(salt: 3.1, calcium: 220), item(salt: 2.8, calcium: 180), item(salt: nil, calcium: 150),
      item(salt: 2.4, calcium: 90), item(salt: nil, calcium: 60),
    ])
  }()

  /// 30〜49歳の女性の基準値
  static let goals: [NutrientID: DietaryReferenceIntakes.Goal] = [
    .saltEquivalent: .init(nutrient: .saltEquivalent, indicator: .tentativeDietaryGoal, comparison: .lessThan, value: 6.5),
    .saturatedFat: .init(
      nutrient: .saturatedFat, indicator: .tentativeDietaryGoal, comparison: .atMostPercentOfEnergy, value: 7),
    .potassium: .init(nutrient: .potassium, indicator: .tentativeDietaryGoal, comparison: .atLeast, value: 2600),
    .calcium: .init(nutrient: .calcium, indicator: .recommendedDietaryAllowance, comparison: .reference, value: 650),
    .magnesium: .init(nutrient: .magnesium, indicator: .recommendedDietaryAllowance, comparison: .reference, value: 290),
    .iron: .init(
      nutrient: .iron, indicator: .recommendedDietaryAllowance, comparison: .reference, value: 6.0,
      menstruatingValue: 10.5),
    .vitaminA: .init(nutrient: .vitaminA, indicator: .recommendedDietaryAllowance, comparison: .reference, value: 700),
    .vitaminD: .init(nutrient: .vitaminD, indicator: .adequateIntake, comparison: .reference, value: 9),
    .vitaminC: .init(nutrient: .vitaminC, indicator: .recommendedDietaryAllowance, comparison: .reference, value: 100),
    .zinc: .init(nutrient: .zinc, indicator: .recommendedDietaryAllowance, comparison: .reference, value: 8),
    .folate: .init(nutrient: .folate, indicator: .recommendedDietaryAllowance, comparison: .reference, value: 240),
    .vitaminE: .init(nutrient: .vitaminE, indicator: .adequateIntake, comparison: .reference, value: 6),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      DailyTotalsView(
        totals: NutritionValues(
          calories: 1642, netCarbs: 186.3, dietaryFiber: 14.2, fat: 52.8, protein: 94.5),
        goals: NutritionGoalsTargets(
          calories: 2000, protein: 120, fat: 60, netCarbs: 250, fiber: 20),
        showsAllNutrients: $showsAllNutrients,
        addedTotals: Self.addedTotals, referenceGoals: Self.goals)
    }
  }
}

/// 体組成まわりの部品。栄養と重ねた二軸グラフと、記録の画面に置くカード。
private struct BodyGalleryView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      group("Body Card") {
        VStack(alignment: .leading, spacing: 16) {
          // 同じ日に3回乗った日。乗った回数だけ行が並ぶ
          ForEach(Array(Self.dayMeasurements.enumerated()), id: \.element.id) { index, item in
            BodyMeasurementRow(measurement: item, showsLabels: index == 0)
            Divider()
          }

          BodyLastMeasuredRow(
            last: .init(weightKg: 61.0, bodyFatPercent: 18.2, daysAgo: 3))

          BodyCompositionActionView(
            hasMeasurementToday: false, activity: .idle, canMeasure: true, failure: nil,
            onMeasure: {}, onStop: {})
          BodyCompositionActionView(
            hasMeasurementToday: true, activity: .idle, canMeasure: true,
            failure: "体組成計が見つかりませんでした。電源が入っていない状態で通信ボタンを押してから、もう一度試してください",
            onMeasure: {}, onStop: {})
        }
      }
    }
    .padding()
  }

  /// 同じ日に3回乗った日。値は架空。
  ///
  /// 探している間の表示はここに並べられない。`ProgressView` は `ImageRenderer` で
  /// 描けず、AX5 では書き出し自体が失敗する。実機で見るしかない。
  static var dayMeasurements: [BodyMeasurementDTO] {
    [
      measurement("2026-09-24", at: "22:02", weight: 60.9, bodyFat: 18.1, muscle: 47.4),
      measurement("2026-09-25", at: "03:30", weight: 61.4, bodyFat: 18.3, muscle: 47.5),
      measurement("2026-09-25", at: "12:45", weight: 61.9, bodyFat: 18.6, muscle: 47.6),
    ]
  }

  /// `day` は UTC 側の日付。`measuredAt` は UTC なので、朝いちばんの計測は
  /// 暦日より前の日付になる。暦日は `sourceDate` に固定で入れる
  private static func measurement(
    _ day: String, at time: String, weight: Double, bodyFat: Double, muscle: Double
  ) -> BodyMeasurementDTO {
    BodyMeasurementDTO(
      id: "\(day)T\(time)", sourceDate: "2026-09-25", measuredAt: "\(day)T\(time):00.000Z",
      weightKg: weight, bodyFatPercent: bodyFat, muscleMassKg: muscle, muscleScore: 2,
      visceralFatLevel: 6.5, basalMetabolismKcal: 1480, metabolicAge: 34, boneMassKg: 2.7,
      bodyWaterPercent: 57.3)
  }

  private func group<Content: View>(
    _ title: String, @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      content()
    }
  }
}

/// 測定1件の画面。前の日と比べられる回と、比べる相手が無く項目も欠けた回。
private struct BodyDetailGalleryView: View {
  let withReference: Bool

  var body: some View {
    Group {
      if withReference {
        BodyMeasurementDetailContent(
          measurement: Self.measurement(
            "2026-09-25", at: "22:12", weight: 63.4, bodyFat: 19.8, muscle: 48.1, age: 33),
          reference: Self.measurement(
            "2026-09-24", at: "22:05", weight: 63.8, bodyFat: 20.3, muscle: 48.0, age: 34))
      } else {
        // 体脂肪率から先が取れなかった回。初めて測った日なので差も無い
        BodyMeasurementDetailContent(
          measurement: BodyMeasurementDTO(
            id: "partial", sourceDate: "2026-09-26", measuredAt: "2026-09-26T11:40:00.000Z",
            weightKg: 63.1, bodyFatPercent: nil, muscleMassKg: nil, muscleScore: nil,
            visceralFatLevel: nil, basalMetabolismKcal: nil, metabolicAge: nil, boneMassKg: nil,
            bodyWaterPercent: nil),
          reference: nil)
      }
    }
    .padding()
  }

  /// 値は架空。前の日と同じ値の項目も混ぜる
  private static func measurement(
    _ day: String, at time: String, weight: Double, bodyFat: Double, muscle: Double, age: Int
  ) -> BodyMeasurementDTO {
    BodyMeasurementDTO(
      id: "\(day)T\(time)", sourceDate: day, measuredAt: "\(day)T\(time):00.000Z",
      weightKg: weight, bodyFatPercent: bodyFat, muscleMassKg: muscle, muscleScore: 1,
      visceralFatLevel: 7.5, basalMetabolismKcal: 1480, metabolicAge: age, boneMassKg: 2.7,
      bodyWaterPercent: 56.2)
  }
}

/// 画面の部品。週の帯・記録の詳細の要約・設定の行。
/// ほかの絵に足すと AX5 で PNG に書き出せない高さになるので分ける。
private struct ScreenPartsGalleryView: View {
  private let sample = NutritionValues(
    calories: 523, netCarbs: 62.4, dietaryFiber: 4.2, fat: 18.6, protein: 31.5)

  private static var galleryToday: Date { Calendar.current.startOfDay(for: Date()) }

  /// 今週の各日に、目標の手前・超過・未記録が混ざるように値を置く。
  private static var weekCalories: [String: Double] {
    let values: [Double] = [1850, 2300, 0, 1420, 960, 2000, 1200]
    let days = WeekStripView.days(containing: galleryToday)
    return Dictionary(
      uniqueKeysWithValues: zip(days.map(LogItemDTO.formatLogDate), values))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      group("Week Strip") {
        // 週の帯は ScrollView なので ImageRenderer で描けない。中の1週間ぶんを描く
        WeekRowView(
          days: WeekStripView.days(containing: Self.galleryToday),
          selectedDate: Self.galleryToday,
          caloriesByDate: Self.weekCalories,
          targetCalories: 2000,
          onSelect: { _ in })
      }

      group("Item Overview") {
        NutritionOverview(values: sample)
      }

      group("Meal Type Selector") {
        MealTypeSelector(selection: .constant(.lunch))
      }

      group("Log Row") {
        FoodRow(
          title: "Bulletproof Mct Oil", subtitle: "1 tbsp",
          values: NutritionValues(
            calories: 128, netCarbs: 0, dietaryFiber: 0, fat: 14, protein: 0),
          trailingText: "8:12")
        FoodRow(
          title: "ごはん", subtitle: "150 g",
          values: NutritionValues(
            calories: 234, netCarbs: 53.4, dietaryFiber: 2.3, fat: 0.5, protein: 3.8),
          showsAddIndicator: true)
      }

      group("Settings Rows") {
        VStack(alignment: .leading, spacing: 12) {
          SettingsRowLabel(
            "Daily Nutrition Goals", systemImage: "target", color: .red, detail: "1,210 kcal")
          SettingsRowLabel(
            "Body Composition Scale", systemImage: "scalemass.fill", color: .purple,
            detail: "Registered")
        }
      }

    }
    .padding()
  }

  private func group<Content: View>(
    _ title: String, @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      content()
    }
  }
}

/// 統計の「その他の栄養素」。基準値があるときと、プロフィールが無いとき。詳しい栄養素は畳んである
private struct AddedNutrientGoalsGalleryView: View {
  let withGoals: Bool

  var body: some View {
    AddedNutrientGoalsView(
      totals: DailyTotalsSample.addedTotals, dayCount: 1, goals: withGoals ? DailyTotalsSample.goals : [:]
    )
    .padding()
  }
}

/// 統計の栄養素のうち、1つの見出しの分だけを並べる。AX5 で全部を1枚に描けないときに使う
private struct AddedNutrientSectionGalleryView: View {
  let section: NutrientRingGrid.Section
  let withGoals: Bool

  var body: some View {
    NutrientRingGrid(
      nutrients: NutrientID.addedNutrients.filter { NutrientRingGrid.Section($0) == section },
      totals: DailyTotalsSample.addedTotals, aggregation: .dailyAverage(days: 1),
      goals: withGoals ? DailyTotalsSample.goals : [:], energy: 1800)
    .padding()
  }
}

/// 1日の合計の「その他の栄養素」だけを、合計のカードと同じ地の上に並べる。
/// 合計のカードごと描くと AX5 で書き出せない高さになる
private struct DayRingGalleryView: View {
  var body: some View {
    NutrientRingGrid(
      nutrients: NutrientID.labelNutrients, totals: DailyTotalsSample.addedTotals, aggregation: .dayTotal,
      goals: DailyTotalsSample.goals, energy: 1800,
      cardBackground: Color(UIColor.tertiarySystemGroupedBackground))
    .padding(16)
    .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    .padding()
  }
}

/// 記録の編集と食品の詳細の行
private struct NutrientRowsGalleryView: View {
  var body: some View {
    VStack(spacing: 8) {
      EditNutrientRow(nutrient: .calories, total: 360)
      EditNutrientRow(nutrient: .fiber, total: 3.2)
      EditNutrientRow(addedNutrient: .saltEquivalent, total: 1.8)
      EditNutrientRow(addedNutrient: .saturatedFat, total: 3.6)
      EditNutrientRow(addedNutrient: .calcium, total: nil)
      EditNutrientRow(addedNutrient: .vitaminB12, total: 0.6)
      NutrientCardRow(nutrient: NutrientID.potassium) {
        Text("420mg")
      }
    }
    .padding()
  }
}

/// 統計の「食事の質スコア」。点が出るときと、出せないとき
private struct DietQualityScoreGalleryView: View {
  private static let score = DietQualityScore(components: [
    .init(nutrient: .protein, role: .encouraged, percentOfReference: 118),
    .init(nutrient: .dietaryFiber, role: .encouraged, percentOfReference: 64),
    .init(nutrient: .vitaminA, role: .encouraged, percentOfReference: 55),
    .init(nutrient: .vitaminC, role: .encouraged, percentOfReference: 81),
    .init(nutrient: .vitaminD, role: .encouraged, percentOfReference: 92),
    .init(nutrient: .calcium, role: .encouraged, percentOfReference: 60),
    .init(nutrient: .iron, role: .encouraged, percentOfReference: 103),
    .init(nutrient: .potassium, role: .encouraged, percentOfReference: 77),
    .init(nutrient: .magnesium, role: .encouraged, percentOfReference: 85),
    .init(nutrient: .saturatedFat, role: .limited, percentOfReference: 131),
    .init(nutrient: .saltEquivalent, role: .limited, percentOfReference: 124),
  ])

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      DietQualityScoreView(result: .score(Self.score))
      Divider()
      DietQualityScoreView(result: .unavailable([.tooFewLoggedDays, .manyUnknownItems([.vitaminD, .potassium])]))
    }
    .padding()
  }
}
