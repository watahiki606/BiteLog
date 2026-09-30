import SwiftUI

/// 記録の画面に置く体組成のカード。
///
/// 測るのは記録をつけるのと同じ毎日の入力なので、設定の奥ではなくここから始める。
/// 表示するだけの部品にして、探すかどうかの判断は `BodyCompositionModel` に持たせる。
struct BodyCompositionCardView: View {
  let measurement: BodyMeasurementDTO?
  let activity: BodyCompositionModel.Activity
  /// いまから測れる日か。過去の日には測る導線を出さない
  let canMeasure: Bool
  let failure: String?
  let onMeasure: () -> Void
  let onStop: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let measurement {
        values(measurement)
      }

      if activity != .idle {
        progress
      } else if canMeasure {
        measureButton
      }

      if let failure {
        Text(failure)
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// 測っていない日は、測れることだけを出す。
  /// 値が出たあとは同じボタンを控えめにして、読むものを値の側に残す。
  @ViewBuilder
  private var measureButton: some View {
    if measurement == nil {
      Text(NSLocalizedString("Not measured today", comment: "Body composition card placeholder"))
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Button(action: onMeasure) {
        Label(
          NSLocalizedString("Measure", comment: "Body composition card button"),
          systemImage: "scalemass")
      }
      .buttonStyle(.bordered)
    } else {
      Button(NSLocalizedString("Measure again", comment: "Body composition card button"),
        action: onMeasure)
        .buttonStyle(.borderless)
        .font(.subheadline)
    }
  }

  private func values(_ measurement: BodyMeasurementDTO) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 24) {
      if let weight = measurement.weightKg {
        value(
          NSLocalizedString("Weight", comment: "Body composition metric"),
          String(format: "%.1f", weight), unit: "kg")
      }
      if let fat = measurement.bodyFatPercent {
        value(
          NSLocalizedString("Body Fat", comment: "Body composition metric"),
          String(format: "%.1f", fat), unit: "%")
      }
    }
  }

  private func value(_ label: String, _ number: String, unit: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
      HStack(alignment: .firstTextBaseline, spacing: 2) {
        Text(number)
          .font(.title2)
          .fontWeight(.semibold)
          .monospacedDigit()
        Text(unit)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
  }

  /// 探している間の表示。どの段階かが分かれば、乗るべきときが分かる。
  private var progress: some View {
    HStack(spacing: 10) {
      ProgressView()
      Text(activityText)
        .font(.subheadline)
        .foregroundStyle(activity == .waitingForStep ? .primary : .secondary)
      Spacer()
      Button(NSLocalizedString("Stop", comment: "Scale import button"), action: onStop)
        .buttonStyle(.borderless)
        .font(.subheadline)
    }
  }

  private var activityText: String {
    switch activity {
    case .idle:
      return ""
    case .searching:
      return NSLocalizedString("Looking for the scale", comment: "Scale import status")
    case .waitingForStep:
      return NSLocalizedString("Step on the scale", comment: "Scale import status")
    case .reading:
      return NSLocalizedString("Receiving measurements", comment: "Scale import status")
    }
  }
}
