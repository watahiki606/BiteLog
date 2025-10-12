import SwiftData
import SwiftUI

struct ContentView: View {
  @Environment(\.modelContext) private var modelContext
  @EnvironmentObject private var languageManager: LanguageManager

  @State private var selectedDate = Date()
  @State private var showingAddItemFor: (date: Date, mealType: MealType)?
  @State private var showingSettings = false
  @State private var showingDatePicker = false
  @State private var selectedTab = 0

  var body: some View {
    VStack(spacing: 0) {
      TabView(selection: $selectedTab) {
      // ログタブ
      NavigationStack {
        VStack(spacing: 0) {
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

                Button {
                  showingSettings = true
                } label: {
                  Label(
                    NSLocalizedString("Settings", comment: "Settings"), systemImage: "gearshape")
                }
              } label: {
                Image(systemName: "ellipsis.circle")
              }
            }
          }
        }
        .navigationTitle("BiteLog")
        .sheet(
          isPresented: Binding(
            get: { showingAddItemFor != nil },
            set: { if !$0 { showingAddItemFor = nil } }
          )
        ) {
          if let itemInfo = showingAddItemFor {
            AddItemView(
              preselectedMealType: itemInfo.mealType,
              selectedDate: itemInfo.date,
              selectedTab: $selectedTab
            )
            .presentationDetents([.medium, .large])
          }
        }
        .sheet(isPresented: $showingDatePicker) {
          DatePickerSheet(selectedDate: $selectedDate, isPresented: $showingDatePicker)
        }
        .sheet(isPresented: $showingSettings) {
          SettingsView()
        }
      }
      .tabItem {
        Label(NSLocalizedString("Log", comment: "Log"), systemImage: "book")
      }
      .tag(0)

      // フード管理タブ
      NavigationStack {
        FoodMasterManagementView()
      }
      .tabItem {
        Label(NSLocalizedString("Food", comment: "Food"), systemImage: "list.bullet.clipboard")
      }
      .tag(1)
    }
    
    // 固定バナー広告
    AdaptiveBannerView()
      .frame(height: 50)
      .background(Color(UIColor.systemBackground))
      .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: -2)
    }
    .edgesIgnoringSafeArea(.bottom)
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
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        if item.isMasterDeleted {
          // 削除されたFoodMasterの場合、削除済みであることを示す
          Text("\(item.brandName) \(item.productName)")
            .font(.headline)
            .foregroundColor(.secondary)
            .strikethrough()  // 取り消し線を追加

          Text(NSLocalizedString("(Deleted)", comment: "Deleted Food indicator"))
            .font(.caption)
            .foregroundColor(.red)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.red.opacity(0.1))
            .cornerRadius(4)
        } else {
          Text("\(item.brandName) \(item.productName)")
            .font(.headline)
        }

        Spacer()

        Text("\(item.calories, specifier: "%.0f") kcal")
          .font(.subheadline)
          .foregroundColor(.secondary)
      }

      HStack {
        Text("P: \(NutritionFormatter.formatNutrition(item.protein))g")
          .font(.caption)
          .foregroundColor(.blue)

        Text("F: \(NutritionFormatter.formatNutrition(item.fat))g")
          .font(.caption)
          .foregroundColor(.yellow)

        Text("S: \(NutritionFormatter.formatNutrition(item.sugar))g")
          .font(.caption)
          .foregroundColor(.green)

        Text("F: \(NutritionFormatter.formatNutrition(item.dietaryFiber))g")
          .font(.caption)
          .foregroundColor(.brown)

        Spacer()

        Text("\(NutritionFormatter.formatNutrition(item.numberOfServings)) \(item.portionUnit)")
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
    .padding(.vertical, 4)
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

      Text(formattedValue)
        .font(.system(size: 15, weight: .medium))
        + Text(" \(unit)")
        .font(.system(size: 14))
        .foregroundColor(.secondary)
    }
    .padding(.horizontal)
  }

  private var formattedValue: String {
    // カロリーの場合は整数表示、それ以外は適応的フォーマット
    if unit == "kcal" {
      return NutritionFormatter.formatCalories(value)
    } else {
      return NutritionFormatter.formatNutrition(value)
    }
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
    HStack(spacing: 2) {
      Text(name)
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(color.opacity(0.8))

      Text("\(value, specifier: value >= 100 ? "%.0f" : "%.1f")\(unit)")
        .font(.system(size: 13, weight: .medium))
    }
    .padding(.vertical, 2)
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

      Text("\(NutritionFormatter.formatNutrition(value))g")
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
