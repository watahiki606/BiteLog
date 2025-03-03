import SwiftData
import SwiftUI

struct ContentView: View {
  @Environment(\.modelContext) private var modelContext
  @EnvironmentObject private var languageManager: LanguageManager

  @State private var selectedDate = Date()
  @State private var showingAddItemFor: (date: Date, mealType: MealType)?
  @State private var showingImportCSV = false
  @State private var showingSettings = false
  @State private var showingDatePicker = false

  var body: some View {
    NavigationStack {
      DayContentView(
        date: selectedDate,
        selectedDate: selectedDate,
        onAddTapped: { date, mealType in
          showingAddItemFor = (date, mealType)
        },
        modelContext: modelContext
      )
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .principal) {
          HStack {
            Button(action: {
              selectedDate = selectedDate.addingTimeInterval(-86400)
            }) {
              Image(systemName: "chevron.left")
            }

            Button(action: {
              showingDatePicker = true
            }) {
              Text(dateFormatter.string(from: selectedDate))
                .font(.headline)
            }

            Button(action: {
              selectedDate = selectedDate.addingTimeInterval(86400)
            }) {
              Image(systemName: "chevron.right")
            }
          }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
          Menu {
            Button(action: { showingImportCSV = true }) {
              Label(
                NSLocalizedString("Import CSV", comment: "Menu item"),
                systemImage: "square.and.arrow.down")
            }
            Button(action: { showingSettings = true }) {
              Label(NSLocalizedString("Settings", comment: "Menu item"), systemImage: "gearshape")
            }
            // 将来的な機能拡張のためのメニュー項目をここに追加可能
          } label: {
            Image(systemName: "ellipsis.circle")
          }
        }
      }
      .sheet(
        isPresented: Binding(
          get: { showingAddItemFor != nil },
          set: { if !$0 { showingAddItemFor = nil } }
        )
      ) {
        if let itemInfo = showingAddItemFor {
          AddItemView(
            preselectedMealType: itemInfo.mealType,
            selectedDate: itemInfo.date
          )
          .presentationDetents([.medium, .large])
        }
      }
      .sheet(isPresented: $showingDatePicker) {
        DatePickerSheet(selectedDate: $selectedDate, isPresented: $showingDatePicker)
      }
      .sheet(isPresented: $showingImportCSV) {
        ImportCSVView()
      }
      .sheet(isPresented: $showingSettings) {
        SettingsView()
      }
    }
  }

  private var dateFormatter: DateFormatter {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
  }
}

// 新しいアイテム行ビュー
struct ItemRowView: View {
  let item: LogItem
  @State private var showingEditSheet = false

  var body: some View {
    HStack {
      VStack(alignment: .leading) {
        Text(item.productName)
          .font(.headline)
        Text(item.brandName)
          .font(.subheadline)
          .foregroundColor(.secondary)
        Text(String(format: "%.1f %@", item.portion, item.portionUnit))
          .font(.footnote)
          .foregroundColor(.secondary)
      }
      Spacer()
      HStack {
        MacroView(label: "Cal", value: item.calories, color: .red)
        MacroView(label: "P", value: item.protein, color: .blue)
        MacroView(label: "F", value: item.fat, color: .yellow)
        MacroView(label: "C", value: item.carbohydrates, color: .green)
      }
    }
    .contentShape(Rectangle())
    .onTapGesture {
      showingEditSheet = true
    }
    .sheet(isPresented: $showingEditSheet) {
      EditItemView(item: item)
    }
  }
}

#Preview {
  ContentView()
    .modelContainer(for: [FoodMaster.self, LogItem.self], inMemory: true)
}

// 栄養素行のコンポーネント
struct NutrientRow: View {
  let label: String
  let value: Double
  let unit: String
  let format: String
  let icon: String
  let color: Color

  var body: some View {
    HStack {
      Image(systemName: icon)
        .foregroundColor(color.opacity(0.8))
        .font(.system(size: 14, weight: .medium))
        .frame(width: 22)

      Text(label)
        .font(.system(size: 15))
        .foregroundColor(.primary.opacity(0.9))

      Spacer()

      Text("\(value, specifier: format)")
        .font(.system(size: 15, weight: .medium))
        + Text(" \(unit)")
        .font(.system(size: 14))
        .foregroundColor(.secondary)
    }
    .padding(.horizontal)
  }
}

// 栄養素バッジコンポーネント
struct NutrientBadge: View {
  let value: Double
  let unit: String
  let name: String
  let color: Color
  let icon: String

  var body: some View {
    VStack(spacing: 2) {
      HStack(spacing: 3) {
        Text(name)
          .font(.system(size: 12, weight: .medium))
      }
      .foregroundColor(color.opacity(0.8))

      Text("\(value, specifier: value >= 100 ? "%.0f" : "%.1f")\(unit)")
        .font(.system(size: 13, weight: .medium))
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 5)
    .background(color.opacity(0.06))
    .cornerRadius(4)
  }
}

// 空の食事セクション
struct EmptyMealView: View {
  let mealType: MealType
  let onAddTap: () -> Void

  var body: some View {
    Button(action: onAddTap) {
      HStack {
        Image(systemName: "plus")
          .font(.body)
          .foregroundColor(.accentColor)

        Text(
          String(
            format: NSLocalizedString("Add %@", comment: "Add meal type"), mealType.localizedName)
        )
        .font(.subheadline)
        .foregroundColor(.primary.opacity(0.8))
      }
      .frame(maxWidth: .infinity)
      .padding()
      .background(Color(UIColor.systemBackground))
      .cornerRadius(6)
    }
    .buttonStyle(PlainButtonStyle())
    .padding(.horizontal)
  }
}
struct MacroView: View {
  let label: String
  let value: Double
  let color: Color

  var body: some View {
    HStack(spacing: 3) {
      Text(label)
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(color.opacity(0.7))

      Text("\(value, specifier: "%.1f")g")
        .font(.system(size: 13))
        .foregroundColor(.primary.opacity(0.8))
    }
    .padding(.vertical, 3)
    .padding(.horizontal, 6)
    .background(color.opacity(0.04))
    .cornerRadius(3)
  }
}

// 日付選択シート
struct DatePickerSheet: View {
  @Binding var selectedDate: Date
  @Binding var isPresented: Bool

  var body: some View {
    NavigationStack {
      VStack {
        DatePicker(
          NSLocalizedString("Select Date", comment: "Date picker title"),
          selection: $selectedDate,
          displayedComponents: .date
        )
        .datePickerStyle(.graphical)
        .padding()
      }
      .navigationTitle(NSLocalizedString("Select Date", comment: "Date picker title"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(NSLocalizedString("Done", comment: "Button title")) {
            isPresented = false
          }
        }
      }
    }
    .presentationDetents([.medium])
  }
}
