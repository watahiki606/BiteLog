import SwiftUI

/// 栄養素の印。形はそのまま、文字は丸みのある太字で描く。
///
/// 大きさと色は呼ぶ側の `.font` と `.foregroundStyle` に従う。
struct NutrientGlyphView: View {
  let glyph: NutrientGlyph

  var body: some View {
    switch glyph {
    case .symbol(let name):
      Image(systemName: name)
    case .text(let text):
      Text(verbatim: text)
        .fontDesign(.rounded)
        .fontWeight(.bold)
        .lineLimit(1)
        // 「NaCl」「B12」は丸に収まらないことがあるので縮める
        .minimumScaleFactor(0.5)
    }
  }
}

/// 栄養素の印を、その色の淡い丸に入れたもの。
struct NutrientBadge: View {
  let glyph: NutrientGlyph
  let color: Color
  var size: CGFloat = 36

  @Environment(\.colorSchemeContrast) private var contrast

  init(nutrient: some NutrientDisplaying, size: CGFloat = 36) {
    glyph = nutrient.glyph
    color = nutrient.color
    self.size = size
  }

  var body: some View {
    NutrientGlyphView(glyph: glyph)
      .font(.system(size: size * Self.glyphScale(glyph), weight: .semibold))
      .foregroundStyle(color)
      .padding(size * 0.12)
      .frame(width: size, height: size)
      .background(color.opacity(contrast == .increased ? 0.3 : 0.15), in: Circle())
      .accessibilityHidden(true)
  }

  /// 文字は形より横に広がるので、形より少し小さく描く
  static func glyphScale(_ glyph: NutrientGlyph) -> CGFloat {
    switch glyph {
    case .symbol: return 0.42
    case .text: return 0.38
    }
  }
}
