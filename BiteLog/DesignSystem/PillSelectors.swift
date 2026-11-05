import SwiftUI

/// 統計の期間を選ぶ丸い切り替え。
///
/// 以前は右上のメニューに入っていて、今どの期間を見ているかが小さな文字でしか分からなかった。
/// 画面の先頭に並べ、選んだものを塗りつぶして目立たせる。
struct PeriodSelector: View {
  @Binding var selection: StatPeriod

  var body: some View {
    HStack(spacing: 8) {
      ForEach(StatPeriod.allCases) { period in
        let isSelected = period == selection
        Button {
          withAnimation(.snappy(duration: 0.2)) { selection = period }
        } label: {
          Text(period.localizedName)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(isSelected ? Color(UIColor.systemBackground) : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(
              isSelected ? Color.primary : Color(UIColor.tertiarySystemFill),
              in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(NSLocalizedString("Period", comment: "Statistics period"))
  }
}

/// グラフに出す指標を選ぶ切り替え。栄養素ごとの色と形を出し、選んだものはその色で塗る。
struct MetricSelector: View {
  @Binding var selection: TrendMetric

  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    Group {
      // 4つを同じ幅で1段に並べる。大きな文字では入らないので2つずつに折り返す
      if !dynamicTypeSize.isAccessibilitySize {
        HStack(spacing: 6) {
          ForEach(TrendMetric.allCases) { chip($0) }
        }
      } else {
        VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
          ForEach(TrendMetric.allCases.prefix(2)) { chip($0) }
        }
        HStack(spacing: 6) {
          ForEach(TrendMetric.allCases.suffix(2)) { chip($0) }
        }
      }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(NSLocalizedString("Metric", comment: "Statistics metric picker"))
  }

  private func chip(_ metric: TrendMetric) -> some View {
    let isSelected = metric == selection
    return Button {
      withAnimation(.snappy(duration: 0.2)) { selection = metric }
    } label: {
      HStack(spacing: 3) {
        Image(systemName: metric.nutrient.symbolName)
          .font(.caption2)
          .accessibilityHidden(true)
        Text(metric.localizedName)
          .font(.footnote.weight(.semibold))
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      }
      .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(metric.color))
      .padding(.horizontal, 6)
      .frame(maxWidth: .infinity, minHeight: 36)
      .background(
        isSelected
          ? AnyShapeStyle(metric.color)
          : AnyShapeStyle(metric.color.opacity(contrast == .increased ? 0.25 : 0.12)),
        in: Capsule()
      )
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(metric.localizedName)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
