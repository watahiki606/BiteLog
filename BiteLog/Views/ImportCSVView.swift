import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ImportCSVView: View {
  @Environment(\.dismiss) var dismiss
  @Environment(\.modelContext) private var modelContext
  @State private var showingFilePicker = false
  @State private var importError: Error?
  @State private var showingError = false

  var body: some View {
    NavigationStack {
      VStack(spacing: 20) {
        Text(NSLocalizedString("CSV File Format:", comment: "CSV import instruction"))
          .font(.headline)

        Text(
          "Date,Meal Type,Brand,Product,Portion,Calories,Carbs,Fat,Protein\n2024-03-20,Breakfast,Brand A,Product B,1 piece,200,30,10,8"
        )
        .font(.system(.footnote, design: .monospaced))
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)

        Text(
          NSLocalizedString(
            "*Japanese meal types (朝食, 昼食, 夕食, 間食) are also supported", comment: "CSV import note")
        )
        .font(.caption)
        .foregroundColor(.secondary)

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

        Spacer()
      }
      .padding()
      .navigationTitle(NSLocalizedString("Import CSV", comment: "Navigation title"))
      .toolbar {
        Button(NSLocalizedString("Close", comment: "Button title")) { dismiss() }
      }
      .fileImporter(
        isPresented: $showingFilePicker,
        allowedContentTypes: [UTType.commaSeparatedText]
      ) { result in
        switch result {
        case .success(let url):
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

            try CSVImporter.importCSV(from: url, context: modelContext)
            dismiss()  // インポート成功時に画面を閉じる
          } catch let error as CSVImportError {
            importError = error
            showingError = true
          } catch {
            importError = error
            showingError = true
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
}
