import SwiftUI

/// 測定1件の中身。測り終えたときに開くのもこの画面。
///
/// 乗り終えた人がまず知りたいのは体重と、前より増えたか減ったか。体重を大きく出し、
/// 体脂肪率と筋肉量をその下に添える。残りの6項目は小さなカードに並べる。
/// 9項目を同じ大きさの表にすると、どこを見ればいいかが分からない。
///
/// 差はカードには置かずここに置く。並んだ数字の横に差があると、
/// 1日の上下を変化として読んでしまう。1件を開いて見にきた人には出してよい。
/// 何と比べたかは必ず書く。間が空いていても読み違えない。
///
/// 取り込みをやり直したいときや、他人が乗ったぶんが混ざったときのために、
/// ここから消せるようにしている。
///
/// 推移は統計の画面にある。栄養のグラフに体組成の折れ線を重ねる形なので、
/// 食べ方が体にどう出ているかはそこで見る。
struct BodyMeasurementDetailView: View {
  let measurement: BodyMeasurementDTO
  /// 比べる相手。前の日の同じ頃に測った回
  let reference: BodyMeasurementDTO?
  let onDelete: () async -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var showingDeleteConfirmation = false
  @State private var isDeleting = false

  var body: some View {
    ScrollView {
      BodyMeasurementDetailContent(measurement: measurement, reference: reference)
        .padding(.horizontal, 16)
        .padding(.top, 8)

      Button(role: .destructive) {
        showingDeleteConfirmation = true
      } label: {
        Text(NSLocalizedString("Delete Measurement", comment: "Body measurement delete"))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 14)
          .background(
            Color(UIColor.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous))
      }
      .disabled(isDeleting)
      .padding(.horizontal, 16)
      // 結果から目を離した先にある操作なので、上の内容と離して置く
      .padding(.top, 32)
      .padding(.bottom, 24)
    }
    .background(Color(UIColor.systemGroupedBackground))
    .navigationTitle(NSLocalizedString("Body Composition", comment: "Body composition section"))
    .navigationBarTitleDisplayMode(.inline)
    .alert(
      NSLocalizedString("Delete this measurement?", comment: "Body measurement delete title"),
      isPresented: $showingDeleteConfirmation
    ) {
      Button(NSLocalizedString("Delete", comment: "Delete button"), role: .destructive) {
        isDeleting = true
        Task {
          await onDelete()
          dismiss()
        }
      }
      Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) {}
    } message: {
      Text(
        NSLocalizedString(
          "The scale keeps its own copy, so it may come back the next time you connect.",
          comment: "Body measurement delete message"))
    }
  }
}

/// 1件の画面の中身。消す操作とナビゲーションを持たないので、そのまま描画して確かめられる。
struct BodyMeasurementDetailContent: View {
  let measurement: BodyMeasurementDTO
  let reference: BodyMeasurementDTO?

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// 体重の下に添える2項目。カードに出しているのと同じ並び
  private static let secondaryMetrics: [BodyMetric] = [.bodyFatPercent, .muscleMassKg]

  private var rows: [BodyMeasurementDetail.Row] {
    BodyMeasurementDetail.rows(for: measurement, reference: reference)
  }

  private func row(_ metric: BodyMetric) -> BodyMeasurementDetail.Row? {
    rows.first { $0.metric == metric }
  }

  private var otherRows: [BodyMeasurementDetail.Row] {
    rows.filter { $0.metric != .weightKg && !Self.secondaryMetrics.contains($0.metric) }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 28) {
      summaryCard

      VStack(alignment: .leading, spacing: 12) {
        Text(NSLocalizedString("Other measurements", comment: "Body measurement detail section"))
          .font(.headline)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.leading, 4)
          .accessibilityAddTraits(.isHeader)

        LazyVGrid(columns: gridColumns, spacing: 12) {
          ForEach(otherRows) { row in
            BodyMetricTile(row: row)
          }
        }
      }
    }
  }

  /// 大きな文字では2列にすると数値が折り返す。1列にする
  private var gridColumns: [GridItem] {
    let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
    return Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: count)
  }

  // MARK: - 主役のカード

  private var summaryCard: some View {
    VStack(alignment: .leading, spacing: 20) {
      if let measuredAt = measurement.measuredAtDate {
        Text(measuredAt.formatted(.dateTime.month().day().weekday().hour().minute()))
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      if let weight = row(.weightKg) {
        BodyHeadlineWeight(row: weight)
      }

      Divider()

      // 大きな文字では2つを横に並べると数値が切れる
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 16) { secondaryValues }
      } else {
        HStack(alignment: .top, spacing: 16) { secondaryValues }
      }

      comparisonNote
    }
    .padding(dynamicTypeSize.isAccessibilitySize ? 16 : 20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      Color(UIColor.secondarySystemGroupedBackground),
      in: RoundedRectangle(cornerRadius: 24, style: .continuous))
  }

  @ViewBuilder
  private var secondaryValues: some View {
    ForEach(Self.secondaryMetrics) { metric in
      if let row = row(metric) {
        BodyMetricSummaryValue(row: row)
      }
    }
  }

  /// 何と比べた差かを書く。前の日に測っていなければ差が無い理由を書く
  private var comparisonNote: some View {
    Group {
      if let referenceDate = reference?.measuredAtDate {
        Text(
          String(
            format: NSLocalizedString(
              "Compared with %@", comment: "Body measurement detail comparison"),
            referenceDate.formatted(.dateTime.month().day().hour().minute())))
      } else {
        Text(
          NSLocalizedString(
            "Changes appear once you have a measurement from an earlier day.",
            comment: "Body measurement detail comparison"))
      }
    }
    .font(.footnote)
    .foregroundStyle(.secondary)
    .fixedSize(horizontal: false, vertical: true)
  }
}

/// 体重。乗り終えた人がいちばん先に見る数字なので、画面でいちばん大きくする。
private struct BodyHeadlineWeight: View {
  let row: BodyMeasurementDetail.Row

  /// 大きな文字に合わせて伸ばすが、画面の幅を超えないように頭を打つ
  @ScaledMetric(relativeTo: .largeTitle) private var scaledSize: CGFloat = 60
  private var size: CGFloat { min(scaledSize, 88) }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      BodyMetricLabel(metric: row.metric)
        .font(.subheadline.weight(.semibold))

      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(row.value.map(row.metric.format) ?? "–")
          .font(.system(size: size, weight: .bold, design: .rounded))
          .monospacedDigit()
          .minimumScaleFactor(0.6)
          .lineLimit(1)
        if row.value != nil, !row.metric.unit.isEmpty {
          Text(row.metric.unit)
            .font(.title2.weight(.semibold))
            .foregroundStyle(.secondary)
        }
      }

      if let change = row.change {
        BodyChangeBadge(metric: row.metric, change: change, isProminent: true)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

/// 体重の下に添える項目。体重より一段小さく、残りの6項目より一段大きい。
private struct BodyMetricSummaryValue: View {
  let row: BodyMeasurementDetail.Row

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      BodyMetricLabel(metric: row.metric)
        .font(.subheadline)
      BodyMetricNumber(row: row, font: .system(.title, design: .rounded, weight: .bold))
      if let change = row.change {
        BodyChangeBadge(metric: row.metric, change: change)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}

/// 残りの6項目を1つずつ載せる小さなカード。
private struct BodyMetricTile: View {
  let row: BodyMeasurementDetail.Row

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      BodyMetricLabel(metric: row.metric)
        .font(.subheadline)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
      BodyMetricNumber(row: row, font: .system(.title2, design: .rounded, weight: .semibold))
      if let change = row.change {
        BodyChangeText(metric: row.metric, change: change)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      Color(UIColor.secondarySystemGroupedBackground),
      in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    .accessibilityElement(children: .combine)
  }
}

/// アイコンと項目名。栄養素の名前と同じ形で、アイコンだけに色を付ける。
///
/// 色は体組成の1色にそろえる。項目ごとに色を変えると9色が並び、増減の緑と橙が埋もれる。
private struct BodyMetricLabel: View {
  let metric: BodyMetric

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 5) {
      Image(systemName: metric.symbolName)
        .foregroundStyle(Color("BodyMetric"))
        .accessibilityHidden(true)
      Text(metric.localizedName)
        .foregroundStyle(.secondary)
    }
  }
}

/// 数値と単位。取れなかった項目は「–」にする。0 と書くと測れたことになる。
private struct BodyMetricNumber: View {
  let row: BodyMeasurementDetail.Row
  let font: Font

  var body: some View {
    if let value = row.value {
      HStack(alignment: .firstTextBaseline, spacing: 3) {
        Text(row.metric.format(value))
          .font(font)
          .monospacedDigit()
        if !row.metric.unit.isEmpty {
          Text(row.metric.unit)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
    } else {
      Text("–")
        .font(font)
        .foregroundStyle(.secondary)
    }
  }
}

/// 差を地の付いた札にする。主役の3項目に使い、数字の並びから一目で拾えるようにする。
///
/// 良し悪しが決まる項目だけ色を付ける。体重は目標次第で増減の良し悪しが変わるので灰色。
private struct BodyChangeBadge: View {
  let metric: BodyMetric
  let change: Double
  var isProminent = false

  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    let color = metric.changeColor(change)
    Text(label)
      .font((isProminent ? Font.body : .subheadline).weight(.semibold))
      .monospacedDigit()
      .foregroundStyle(color ?? .secondary)
      .padding(.horizontal, isProminent ? 12 : 10)
      .padding(.vertical, isProminent ? 6 : 4)
      .background(
        color.map { $0.opacity(contrast == .increased ? 0.25 : 0.14) }
          ?? Color(UIColor.tertiarySystemFill),
        in: Capsule())
  }

  private var label: String {
    let value = metric.formatChange(change)
    return metric.unit.isEmpty ? value : "\(value) \(metric.unit)"
  }
}

/// 差を文字だけで添える。小さなカードに札を置くと、6枚とも色の塊が並んで騒がしい。
private struct BodyChangeText: View {
  let metric: BodyMetric
  let change: Double

  var body: some View {
    Text(metric.formatChange(change))
      .font(.subheadline.weight(.medium))
      .monospacedDigit()
      .foregroundStyle(metric.changeColor(change) ?? .secondary)
  }
}
