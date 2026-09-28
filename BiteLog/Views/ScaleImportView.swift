import SwiftUI

/// 体組成計から Bluetooth で測定データを取り込む。
///
/// 体重計は測定のたびに本体へ溜めていくので、1回つなぐと未送信のぶんがまとめて流れてくる。
/// 受け取った順にサーバーへ送り、既に持っている計測時刻のものは重複として数える。
struct ScaleImportView: View {
  @StateObject private var connection = TanitaScaleConnection()
  @AppStorage("TanitaAppIdentifier") private var appIdentifier = ""

  @State private var received: [TanitaBodyMeasurement] = []
  @State private var savedCount = 0
  @State private var duplicateCount = 0
  @State private var uploadError: String?

  private var isRunning: Bool {
    switch connection.state {
    case .idle, .finished, .failed: return false
    default: return true
    }
  }

  var body: some View {
    List {
      Section {
        HStack(spacing: 12) {
          if isRunning {
            ProgressView()
          }
          Text(statusText)
            .font(.subheadline)
        }

        if case .failed(let message) = connection.state {
          Text(message)
            .font(.footnote)
            .foregroundColor(.secondary)
        }

        if let uploadError {
          Text(uploadError)
            .font(.footnote)
            .foregroundColor(.red)
        }
      }

      if !received.isEmpty {
        Section(
          header: Text(NSLocalizedString("Received Measurements", comment: "Scale import section"))
        ) {
          ForEach(Array(received.enumerated()), id: \.offset) { _, measurement in
            measurementRow(measurement)
          }
        }
      }

      if !connection.log.isEmpty {
        Section(
          header: Text(NSLocalizedString("Connection Log", comment: "Scale import section"))
        ) {
          ForEach(Array(connection.log.enumerated()), id: \.offset) { _, line in
            Text(line)
              .font(.system(.caption, design: .monospaced))
              .foregroundColor(.secondary)
              .textSelection(.enabled)
          }
        }
      }

      #if DEBUG
        Section(
          header: Text("識別子（開発用）"),
          footer: Text("体組成計は登録済みの識別子しか受け付けない。未登録だと Err UUID が出る")
        ) {
          TextField("UUID", text: $appIdentifier)
            .font(.system(.caption, design: .monospaced))
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
        }
      #endif

      Section {
        if isRunning {
          Button(NSLocalizedString("Stop", comment: "Scale import button"), role: .cancel) {
            connection.stop()
          }
        } else {
          Button(NSLocalizedString("Connect to Scale", comment: "Scale import button")) {
            startImport()
          }
        }
      } footer: {
        Text(
          NSLocalizedString(
            "Step on the scale after the connection starts. Measurements stored on the scale are imported together.",
            comment: "Scale import help"))
      }
    }
    .navigationTitle(NSLocalizedString("Import from Scale", comment: "Scale import title"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      connection.onMeasurement = { measurement in
        received.append(measurement)
        Task { await upload(measurement) }
      }
    }
    .onDisappear {
      connection.stop()
    }
  }

  private func measurementRow(_ measurement: TanitaBodyMeasurement) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      if let measuredAt = measurement.measuredAt {
        Text(measuredAt.formatted(date: .abbreviated, time: .shortened))
          .font(.subheadline)
      }
      HStack(spacing: 12) {
        if let weight = measurement.weightKg {
          Text(String(format: "%.1f kg", weight))
        }
        if let fat = measurement.bodyFatPercent {
          Text(String(format: "%.1f %%", fat))
        }
      }
      .font(.footnote)
      .foregroundColor(.secondary)
    }
  }

  private var statusText: String {
    switch connection.state {
    case .idle:
      return NSLocalizedString("Not connected", comment: "Scale import status")
    case .scanning:
      return NSLocalizedString("Looking for the scale", comment: "Scale import status")
    case .connecting:
      return NSLocalizedString("Connecting", comment: "Scale import status")
    case .preparing:
      return NSLocalizedString("Preparing", comment: "Scale import status")
    case .waitingForStep:
      return NSLocalizedString("Step on the scale", comment: "Scale import status")
    case .reading:
      return NSLocalizedString("Receiving measurements", comment: "Scale import status")
    case .finished:
      return String(
        format: NSLocalizedString(
          "Done. %d saved, %d already stored", comment: "Scale import result"),
        savedCount, duplicateCount)
    case .failed:
      return NSLocalizedString("Could not finish", comment: "Scale import status")
    }
  }

  private func startImport() {
    received = []
    savedCount = 0
    duplicateCount = 0
    uploadError = nil
    connection.start()
  }

  private func upload(_ measurement: TanitaBodyMeasurement) async {
    guard let dto = BodyMeasurementCreateDTO(measurement) else {
      uploadError = NSLocalizedString(
        "A measurement without a timestamp was skipped", comment: "Scale import error")
      return
    }
    do {
      try await APIClient.shared.createBodyMeasurement(dto)
      savedCount += 1
    } catch APIError.serverError(409) {
      // 同じ計測時刻の記録が既にある。体重計は引き取り済みのぶんも送ってくることがある
      duplicateCount += 1
    } catch {
      uploadError = error.localizedDescription
    }
  }
}
