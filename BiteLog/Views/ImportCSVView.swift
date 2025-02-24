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
        Text("CSVファイルのフォーマット:")
          .font(.headline)

        Text("日付,食事タイプ,ブランド名,商品名,量,カロリー,炭水化物,脂質,タンパク質\n2024-03-20,朝食,ブランドA,商品B,1個,200,30,10,8")
          .font(.system(.footnote, design: .monospaced))
          .padding()
          .background(Color.gray.opacity(0.1))
          .cornerRadius(8)

        Button(action: {
          showingFilePicker = true
        }) {
          Label("CSVファイルを選択", systemImage: "doc.badge.plus")
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
      .navigationTitle("CSVインポート")
      .toolbar {
        Button("閉じる") { dismiss() }
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
              throw CSVImportError.invalidData("ファイルへのアクセス権限がありません")
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
      .alert("インポートエラー", isPresented: $showingError) {
        Button("OK") {}
      } message: {
        if let csvError = importError as? CSVImportError {
          Text(csvError.localizedDescription)
        } else {
          Text(importError?.localizedDescription ?? "不明なエラーが発生しました")
        }
      }
    }
  }
}
