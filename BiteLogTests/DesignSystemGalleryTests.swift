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
