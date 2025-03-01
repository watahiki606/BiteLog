import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ImportCSVView: View {
  @Environment(\.dismiss) var dismiss
  @Environment(\.modelContext) private var modelContext
  @State private var showingFilePicker = false
  @State private var importError: Error?
  @State private var showingError = false
  @State private var isImporting = false
  @State private var importCompleted = false
  @State private var progress: Double = 0
  @State private var currentRow: Int = 0
  @State private var totalRows: Int = 0
  @State private var importedRowCount: Int = 0
  @State private var importTask: Task<Void, Error>?
  @State private var importDuration: Double = 0

  var body: some View {
    NavigationStack {
      VStack(spacing: 20) {
        if isImporting {
          // インポート進捗表示
          VStack(spacing: 16) {
            if importCompleted {
              // インポート完了表示
              VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                  .font(.system(size: 50))
                  .foregroundColor(.green)

                Text(NSLocalizedString("Import Complete", comment: "CSV import status"))
                  .font(.headline)

                Text(
                  String(
                    format: NSLocalizedString("%d rows imported", comment: "CSV import result"),
                    importedRowCount)
                )
                .font(.subheadline)
                .foregroundColor(.secondary)

                #if DEBUG
                  Text(
                    String(
                      format: NSLocalizedString(
                        "Processing time: %.2f seconds", comment: "CSV import debug info"),
                      importDuration)
                  )
                  .font(.caption)
                  .foregroundColor(.secondary)
                #endif

                Button(NSLocalizedString("Close", comment: "Button title")) {
                  dismiss()
                }
                .buttonStyle(.bordered)
                .padding(.top, 8)
              }
            } else {
              // インポート中表示
              Text(NSLocalizedString("Importing CSV file", comment: "CSV import status"))
                .font(.headline)

              ProgressView(value: progress)
                .progressViewStyle(.linear)
                .padding(.horizontal)

              Text(
                String(
                  format: NSLocalizedString(
                    "Processing %d / %d rows", comment: "CSV import progress"), currentRow,
                  totalRows)
              )
              .font(.subheadline)
              .foregroundColor(.secondary)

              Button(NSLocalizedString("Cancel", comment: "Button title")) {
                importTask?.cancel()
                isImporting = false
              }
              .buttonStyle(.bordered)
              .tint(.red)
              .padding(.top)
            }
          }
          .padding()
          .frame(maxWidth: .infinity)
          .background(Color(UIColor.secondarySystemBackground))
          .cornerRadius(12)
          .padding()
        } else {
          Text(NSLocalizedString("CSV File Format:", comment: "CSV import instruction"))
            .font(.headline)

          Text(
            "Date,Meal Type,Brand,Product,Portion,Calories,Carbs,Fat,Protein,Portion Amount,Portion Unit\n2024-03-20,Breakfast,Brand A,Product B,1 piece,200,30,10,8,1.0,piece"
          )
          .font(.system(.footnote, design: .monospaced))
          .padding()
          .background(Color.gray.opacity(0.1))
          .cornerRadius(8)

          Button(action: {
            showingFilePicker = true
          }) {
            Label(
              NSLocalizedString("Select CSV File", comment: "Button title"),
              systemImage: "doc.badge.plus"
            )
            .font(.headline)
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
          }
          .padding(.horizontal)
        }

        Spacer()
      }
      .padding()
      .navigationTitle(NSLocalizedString("Import CSV", comment: "Navigation title"))
      .toolbar {
        Button(NSLocalizedString("Close", comment: "Button title")) {
          if isImporting && !importCompleted {
            importTask?.cancel()
          }
          dismiss()
        }
      }
      .fileImporter(
        isPresented: $showingFilePicker,
        allowedContentTypes: [UTType.commaSeparatedText]
      ) { result in
        switch result {
        case .success(let url):
          // インポート開始
          isImporting = true
          importCompleted = false
          progress = 0
          currentRow = 0
          totalRows = 0
          importedRowCount = 0

          importTask = Task {
            do {
              // ファイルのセキュリティスコープドアクセスを開始
              guard url.startAccessingSecurityScopedResource() else {
                throw CSVImportError.invalidData(
                  NSLocalizedString("No permission to access file", comment: "Error message"))
              }
              defer {
                // 関数を抜ける前に必ずアクセスを停止
                url.stopAccessingSecurityScopedResource()
              }

              // 進捗ハンドラを設定してインポート
              try CSVImporter.importCSV(from: url, context: modelContext) {
                newProgress, row, total in
                // メインスレッドで進捗状況を更新
                DispatchQueue.main.async {
                  self.progress = newProgress
                  self.currentRow = row
                  self.totalRows = total
                }
                // タスクがキャンセルされたかどうかをチェック
                return Task.isCancelled
              }

              // インポート完了
              DispatchQueue.main.async {
                self.importedRowCount = self.currentRow
                self.progress = 1.0
                self.importCompleted = true
                // 自動的に閉じないようにする（ユーザーが閉じるボタンをタップする）
              }
            } catch let error as CSVImportError {
              await handleImportError(error)
            } catch {
              await handleImportError(error)
            }
          }
        case .failure(let error):
          importError = error
          showingError = true
        }
      }
      .alert(NSLocalizedString("Import Error", comment: "Alert title"), isPresented: $showingError)
      {
        Button("OK") {}
      } message: {
        if let csvError = importError as? CSVImportError {
          Text(csvError.localizedDescription)
        } else {
          Text(
            importError?.localizedDescription
              ?? NSLocalizedString("Unknown error occurred", comment: "Error message"))
        }
      }
    }
  }

  private func handleImportError(_ error: Error) async {
    await MainActor.run {
      isImporting = false
      importError = error
      showingError = true
    }
  }
}
