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
      let renderer = ImageRenderer(
        content:
          GalleryView()
          .frame(width: 390)
          .background(Color(UIColor.systemGroupedBackground))
          .environment(\.colorScheme, scheme)
          .environment(\.dynamicTypeSize, typeSize)
      )
      renderer.scale = 2
      guard let image = renderer.uiImage, let data = image.pngData() else {
        Issue.record("failed to render \(name)")
        continue
      }
      try data.write(to: base.appendingPathComponent("\(name).png"))
    }
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
