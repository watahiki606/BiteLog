import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ExportCSVView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss

  @State private var isExporting = false
  @State private var showingAlert = false
  @State private var alertTitle = ""
  @State private var alertMessage = ""
  @State private var exportedFileURL: URL? = nil
  @State private var showingShareSheet = false

  var body: some View {
    NavigationStack {
      Form {
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
    let fileName = "log_items"
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

    // バックグラウンドスレッドでエクスポート実行
    Task {
      do {
        let count = try CSVExporter.exportLogItems(to: fileURL, context: modelContext) { _, _, _ in
          return false // キャンセルしない
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
    alertMessage = "\(count) \(NSLocalizedString("Log", comment: "Log")) \(NSLocalizedString("exported successfully", comment: "Exported successfully"))\n\(NSLocalizedString("Tap OK to share the file", comment: "Tap OK to share the file"))"
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
