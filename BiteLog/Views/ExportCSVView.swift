import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum ExportType {
  case foodMaster
  case logItems
}

struct ExportCSVView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss

  @State private var exportType: ExportType = .logItems
  @State private var isExporting = false
  @State private var exportProgress: Double = 0
  @State private var currentCount: Int = 0
  @State private var totalCount: Int = 0
  @State private var showingAlert = false
  @State private var alertTitle = ""
  @State private var alertMessage = ""
  @State private var exportedFileURL: URL? = nil
  @State private var showingShareSheet = false

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker("Export Type", selection: $exportType) {
            Text("Log").tag(ExportType.logItems)
            Text("Food").tag(ExportType.foodMaster)
          }
          .pickerStyle(.segmented)
          .padding(.vertical, 8)
        } header: {
          Text("Select Data to Export")
        } footer: {
          Text("Choose the type of data you want to export as CSV.")
        }

        if isExporting {
          Section {
            VStack(alignment: .leading, spacing: 8) {
              ProgressView(value: exportProgress, total: 1.0)
              Text("\(currentCount) / \(totalCount)")
                .font(.caption)
                .foregroundColor(.secondary)
            }
          } header: {
            Text("Export Progress")
          }
        }

        Section {
          Button(action: startExport) {
            HStack {
              Spacer()
              if isExporting {
                ProgressView()
                  .padding(.trailing, 10)
              }
              Text("Export as CSV")
                .bold()
              Spacer()
            }
          }
          .disabled(isExporting)
        }
      }
      .navigationTitle("Export CSV")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            dismiss()
          }
          .disabled(isExporting)
        }
      }
      .alert(isPresented: $showingAlert) {
        Alert(
          title: Text(alertTitle),
          message: Text(alertMessage),
          dismissButton: .default(Text("OK")) {
            if exportedFileURL != nil {
              showingShareSheet = true
            }
          }
        )
      }
      .sheet(isPresented: $showingShareSheet) {
        if let fileURL = exportedFileURL {
          ShareSheet(items: [fileURL])
        }
      }
    }
  }

  private func startExport() {
    let fileName = exportType == .foodMaster ? "food_master" : "log_items"
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
    let dateString = dateFormatter.string(from: Date())
    let fullFileName = "\(fileName)_\(dateString).csv"

    // ユーザーのドキュメントディレクトリにファイル保存
    guard
      let documentsDirectory = FileManager.default.urls(
        for: .documentDirectory, in: .userDomainMask
      ).first
    else {
      showError(title: "Export Failed", message: "Could not access documents directory")
      return
    }

    let fileURL = documentsDirectory.appendingPathComponent(fullFileName)

    isExporting = true
    exportProgress = 0
    currentCount = 0
    totalCount = 0

    // バックグラウンドスレッドでエクスポート実行
    Task {
      do {
        let count: Int

        if exportType == .foodMaster {
          count = try CSVExporter.exportFoodMaster(to: fileURL, context: modelContext) {
            progress, current, total in
            // UI更新はメインスレッドで行う
            DispatchQueue.main.async {
              exportProgress = progress
              currentCount = current
              totalCount = total
            }
            return false  // キャンセルしない
          }
        } else {
          count = try CSVExporter.exportLogItems(to: fileURL, context: modelContext) {
            progress, current, total in
            DispatchQueue.main.async {
              exportProgress = progress
              currentCount = current
              totalCount = total
            }
            return false
          }
        }

        // エクスポート完了
        await MainActor.run {
          isExporting = false
          exportedFileURL = fileURL
          showSuccess(count: count, filePath: fileURL.path)
        }
      } catch {
        await MainActor.run {
          isExporting = false
          showError(title: "Export Failed", message: error.localizedDescription)
        }
      }
    }
  }

  private func showSuccess(count: Int, filePath: String) {
    alertTitle = NSLocalizedString("Export Successful", comment: "Export successful")
    let type = exportType == .foodMaster ? "Food" : "Log"
    alertMessage = "\(count) \(NSLocalizedString(type, comment: type)) \(NSLocalizedString("exported successfully", comment: "Exported successfully"))\n\(NSLocalizedString("Tap OK to share the file", comment: "Tap OK to share the file"))"
    showingAlert = true
  }

  private func showError(title: String, message: String) {
    alertTitle = title
    alertMessage = message
    showingAlert = true
  }
}

// シェアシート用のUIViewControllerRepresentable
struct ShareSheet: UIViewControllerRepresentable {
  var items: [Any]

  func makeUIViewController(context: Context) -> UIActivityViewController {
    let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
    return controller
  }

  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
  ExportCSVView()
}
