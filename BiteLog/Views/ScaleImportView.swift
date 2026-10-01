import SwiftUI

/// 体組成計の登録と、うまくいかないときの確認。
///
/// ふだん測るのは記録の画面のカードからで、ここはその手前にある。
/// 最初の1回はここで登録し、以降は記録の画面の「測る」から測る。
///
/// 体組成計が覚えられるアプリは1つだけで、登録すると公式アプリの登録は外れる。
/// 戻し方を登録の手前に書いておく。
///
/// 体重計は測定のたびに本体へ溜めていくので、1回つなぐと未送信のぶんがまとめて流れてくる。
/// 受け取った順にサーバーへ送り、既に持っている計測時刻のものは重複として数える。
struct ScaleImportView: View {
  @StateObject private var connection = TanitaScaleConnection()
  @State private var isRegistered = TanitaScaleConnection.isPaired()

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

      if isRegistered {
        Section {
          runButton(NSLocalizedString("Connect to Scale", comment: "Scale import button")) {
            startImport()
          }
        } footer: {
          Text(
            NSLocalizedString(
              "Step on the scale after the connection starts. Measurements stored on the scale are imported together.",
              comment: "Scale import help"))
          Text(
            NSLocalizedString(
              "Registered. Use Measure on the Log screen from now on.",
              comment: "Scale setup help"))
        }

        Section {
          if !isRunning {
            Button(NSLocalizedString("Register Again", comment: "Scale register button")) {
              startRegistration()
            }
          }
        } footer: {
          Text(restoreHelp)
        }
      } else {
        Section {
          registrationStep(
            1, NSLocalizedString("Turn the scale off.", comment: "Scale register step"))
          registrationStep(
            2,
            NSLocalizedString(
              "Hold the communication button for 3 seconds or more.",
              comment: "Scale register step"))
          registrationStep(
            3,
            NSLocalizedString(
              "Tap Register, then step on the scale once it is registered.",
              comment: "Scale register step"))
          runButton(NSLocalizedString("Register", comment: "Scale register button")) {
            startRegistration()
          }
        } header: {
          Text(NSLocalizedString("Registration", comment: "Scale register section"))
        } footer: {
          Text(restoreHelp)
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
    }
    .navigationTitle(NSLocalizedString("Scale Setup", comment: "Scale setup title"))
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
    .onChange(of: connection.state) {
      // 登録が通ったときと、登録が外れていると分かったときに切り替わる
      isRegistered = TanitaScaleConnection.isPaired()
    }
  }

  private var restoreHelp: String {
    NSLocalizedString(
      "The scale remembers only one app. Registering here disconnects the Health Planet app. To switch back, register the scale again in the Health Planet app.",
      comment: "Scale register help")
  }

  /// 動いている間は同じ場所に「やめる」を出す
  @ViewBuilder
  private func runButton(_ title: String, action: @escaping () -> Void) -> some View {
    if isRunning {
      Button(NSLocalizedString("Stop", comment: "Scale import button"), role: .cancel) {
        connection.stop()
      }
    } else {
      Button(title, action: action)
    }
  }

  private func registrationStep(_ number: Int, _ text: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text("\(number)")
        .font(.subheadline.monospacedDigit().weight(.semibold))
        .foregroundColor(.secondary)
      Text(text)
        .font(.subheadline)
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
    clearResults()
    connection.start()
  }

  private func startRegistration() {
    clearResults()
    connection.register()
  }

  private func clearResults() {
    received = []
    savedCount = 0
    duplicateCount = 0
    uploadError = nil
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
