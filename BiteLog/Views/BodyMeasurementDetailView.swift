import SwiftUI

/// 測定1件の中身。体重計が送ってくる9項目すべてと、前日との差。
///
/// 差をここに置いてカードには置かないのは、並んだ数字の横に差があると、
/// 1日の上下を変化として読んでしまうから。1件を開いて見にきた人には出してよい。
///
/// 取り込みをやり直したいときや、他人が乗ったぶんが混ざったときのために、
/// ここから消せるようにしている。
///
/// 推移は統計の画面にある。栄養のグラフに体組成の折れ線を重ねる形なので、
/// 食べ方が体にどう出ているかはそこで見る。
struct BodyMeasurementDetailView: View {
  let measurement: BodyMeasurementDTO
  let previousDayLast: BodyMeasurementDTO?
  let onDelete: () async -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var showingDeleteConfirmation = false
  @State private var isDeleting = false

  private var rows: [BodyMeasurementDetail.Row] {
    BodyMeasurementDetail.rows(for: measurement, previousDay: previousDayLast)
  }

  var body: some View {
    List {
      Section {
        ForEach(rows) { row in
          detailRow(row)
        }
      } header: {
        if let measuredAt = measurement.measuredAtDate {
          Text(measuredAt.formatted(date: .abbreviated, time: .shortened))
        }
      } footer: {
        if previousDayLast != nil {
          Text(
            NSLocalizedString(
              "Change is against the last measurement of the day before.",
              comment: "Body measurement detail footer"))
        }
      }

      Section {
        Button(role: .destructive) {
          showingDeleteConfirmation = true
        } label: {
          Text(NSLocalizedString("Delete Measurement", comment: "Body measurement delete"))
        }
        .disabled(isDeleting)
      }
    }
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

  private func detailRow(_ row: BodyMeasurementDetail.Row) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(row.metric.localizedName)
      Spacer()
      if let value = row.value {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
          Text(row.metric.format(value))
            .fontWeight(.semibold)
            .monospacedDigit()
          if !row.metric.unit.isEmpty {
            Text(row.metric.unit)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        changeLabel(row)
      } else {
        // 体重計が送ってこなかった項目。0 と書くと測れたことになる
        Text("–")
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private func changeLabel(_ row: BodyMeasurementDetail.Row) -> some View {
    if let change = row.change {
      Text(signed(change, digits: row.metric.fractionDigits))
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(minWidth: 52, alignment: .trailing)
    } else {
      // 前日に測っていない。揃えるためだけに幅を残す
      Text(" ")
        .font(.caption)
        .frame(minWidth: 52, alignment: .trailing)
    }
  }

  /// 増減の向きが一目で分かる形にする。マイナス記号は全角の −
  private func signed(_ value: Double, digits: Int) -> String {
    let scale = pow(10, Double(digits))
    let rounded = (value * scale).rounded() / scale
    let sign = rounded > 0 ? "+" : rounded < 0 ? "−" : "±"
    return sign + String(format: "%.\(digits)f", abs(rounded))
  }
}
