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
      try render(BodyGalleryView(), to: base, name: "body-\(name)", scheme: scheme, typeSize: typeSize)
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
      group("Chips") {
        NutrientChipRow(values: sample)
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
          NutrientChipRow(values: overSample)
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
  @State private var showsAllNutrients = true

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      DailyTotalsView(
        totals: NutritionValues(
          calories: 1642, netCarbs: 186.3, dietaryFiber: 14.2, fat: 52.8, protein: 94.5),
        goals: NutritionGoalsTargets(
          calories: 2000, protein: 120, fat: 60, netCarbs: 250, fiber: 20),
        showsAllNutrients: $showsAllNutrients)
    }
  }
}

/// 体組成まわりの部品。栄養と重ねた二軸グラフと、記録の画面に置くカード。
private struct BodyGalleryView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      group("Body Correlation") {
        BodyCorrelationChart(
          points: Self.correlationPoints, nutrient: .calories, metric: .weightKg,
          bucket: .day, xAxisStride: 2)
      }

      group("Body Card") {
        VStack(alignment: .leading, spacing: 20) {
          ForEach(Array(Self.cardSummaries.enumerated()), id: \.offset) { _, summary in
            BodyCompositionValuesView(summary: summary)
          }

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

  /// 二軸グラフの見え方。値は架空で、同じ日に何度も乗った日と、
  /// 測らなかった日と、記録の無い日を混ぜてある。
  static var correlationPoints: [BodyCorrelation.Point] {
    let start = Calendar.current.startOfDay(for: Date())
    let rows: [(nutrient: Double, body: Double?, low: Double?, high: Double?, count: Int)] = [
      (2180, 61.2, 60.9, 61.9, 3),
      (1740, 61.0, 61.0, 61.0, 1),
      (0, nil, nil, nil, 0),
      (2460, 61.4, 61.1, 62.3, 2),
      (1980, 61.1, 61.1, 61.1, 1),
      (2050, nil, nil, nil, 0),
      (1620, 60.8, 60.4, 61.5, 4),
      (2310, 60.9, 60.9, 60.9, 1),
    ]
    return rows.enumerated().map { index, row in
      BodyCorrelation.Point(
        date: Calendar.current.date(byAdding: .day, value: index, to: start)!,
        nutrient: row.nutrient, body: row.body, low: row.low, high: row.high,
        measurementCount: row.count)
    }
  }

  /// カードが取りうる状態。値は架空。
  ///
  /// 探している間の表示はここに並べられない。`ProgressView` は `ImageRenderer` で
  /// 描けず、AX5 では書き出し自体が失敗する。実機で見るしかない。
  static var cardSummaries: [BodyCardSummary.Summary] {
    [
      // 1回だけ乗った日
      summary(
        measurements: [measurement("2026-09-24", at: "22:02", weight: 61.2, bodyFat: 18.4)],
        weight: .init(latest: 61.2, dayChange: -0.3),
        bodyFat: .init(latest: 18.4, dayChange: 0.2),
        trend: .init(change: -0.6, windowDays: 7), lastMeasured: nil),
      // 同じ日に3回乗った日
      summary(
        measurements: [
          measurement("2026-09-24", at: "22:02", weight: 60.9, bodyFat: 18.1),
          measurement("2026-09-25", at: "03:30", weight: 61.4, bodyFat: 18.3),
          measurement("2026-09-25", at: "12:45", weight: 61.9, bodyFat: 18.6),
        ],
        weight: .init(latest: 61.9, dayChange: 0.4),
        bodyFat: .init(latest: 18.6, dayChange: 0.1),
        trend: .init(change: 0.2, windowDays: 7), lastMeasured: nil),
      // その日は乗らなかった
      summary(
        measurements: [], weight: nil, bodyFat: nil, trend: nil,
        lastMeasured: .init(weightKg: 61.0, bodyFatPercent: 18.2, daysAgo: 3)),
    ]
  }

  private static func summary(
    measurements: [BodyMeasurementDTO], weight: BodyCardSummary.Value?,
    bodyFat: BodyCardSummary.Value?, trend: BodyCardSummary.Trend?,
    lastMeasured: BodyCardSummary.LastMeasured?
  ) -> BodyCardSummary.Summary {
    BodyCardSummary.Summary(
      measurements: measurements, weight: weight, bodyFat: bodyFat, weightTrend: trend,
      lastMeasured: lastMeasured, hasAnyData: true)
  }

  /// `day` は UTC 側の日付。`measuredAt` は UTC なので、朝いちばんの計測は
  /// 暦日より前の日付になる。暦日は `sourceDate` に固定で入れる
  private static func measurement(
    _ day: String, at time: String, weight: Double, bodyFat: Double
  ) -> BodyMeasurementDTO {
    BodyMeasurementDTO(
      id: "\(day)T\(time)", sourceDate: "2026-09-25", measuredAt: "\(day)T\(time):00.000Z",
      weightKg: weight, bodyFatPercent: bodyFat, muscleMassKg: 47.6, muscleScore: 2,
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
