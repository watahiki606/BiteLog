import SwiftUI

struct ContentView: View {
  @EnvironmentObject private var languageManager: LanguageManager

  @State private var selectedDate = Date()
  @State private var showingAddItemFor: (date: Date, mealType: MealType)?
  @State private var showingSettings = false
  @State private var showingDatePicker = false
  @State private var selectedTab = 0
  @State private var logRefreshTrigger = 0
  @State private var dragOffset: CGFloat = 0

  var body: some View {
    VStack(spacing: 0) {
      // メインコンテンツ
      ZStack {
        // ログタブ
        NavigationStack {
        VStack(spacing: 0) {
          DayContentView(
            date: selectedDate,
            selectedDate: selectedDate,
            onAddTapped: { date, mealType in
              showingAddItemFor = (date, mealType)
            },
            refreshTrigger: logRefreshTrigger
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
          ),
          onDismiss: { logRefreshTrigger += 1 }
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
      .offset(x: dragOffset)
      .gesture(DateSwipeGesture(
        dragOffset: $dragOffset,
        onDateChange: { goForward in
          selectedDate = selectedDate.addingTimeInterval(goForward ? 86400 : -86400)
        }
      ))
      .opacity(selectedTab == 0 ? 1 : 0)
      .zIndex(selectedTab == 0 ? 1 : 0)

      // フード管理タブ
      NavigationStack {
        FoodMasterManagementView()
      }
      .opacity(selectedTab == 1 ? 1 : 0)
      .zIndex(selectedTab == 1 ? 1 : 0)

      // 統計タブ
      NavigationStack {
        StatisticsView()
      }
      .opacity(selectedTab == 2 ? 1 : 0)
      .zIndex(selectedTab == 2 ? 1 : 0)
      }
      .clipped()

      // カスタムタブバー
      HStack {
        // Logタブ
        Button(action: {
          selectedDate = Calendar.current.startOfDay(for: Date())
          selectedTab = 0
          logRefreshTrigger += 1
        }) {
          VStack(spacing: 4) {
            Image(systemName: "book")
              .font(.system(size: 24))
            Text(NSLocalizedString("Log", comment: "Log"))
              .font(.caption)
          }
          .frame(maxWidth: .infinity)
          .foregroundColor(selectedTab == 0 ? .blue : .gray)
        }

        // Foodタブ
        Button(action: {
          selectedTab = 1
        }) {
          VStack(spacing: 4) {
            Image(systemName: "list.bullet.clipboard")
              .font(.system(size: 24))
            Text(NSLocalizedString("Food", comment: "Food"))
              .font(.caption)
          }
          .frame(maxWidth: .infinity)
          .foregroundColor(selectedTab == 1 ? .blue : .gray)
        }

        // 統計タブ
        Button(action: {
          selectedTab = 2
        }) {
          VStack(spacing: 4) {
            Image(systemName: "chart.xyaxis.line")
              .font(.system(size: 24))
            Text(NSLocalizedString("Statistics", comment: "Tab name"))
              .font(.caption)
          }
          .frame(maxWidth: .infinity)
          .foregroundColor(selectedTab == 2 ? .blue : .gray)
        }
      }
      .padding(.vertical, 8)
      .background(
        Color(UIColor.systemBackground)
          .ignoresSafeArea(edges: .bottom)
      )
      .overlay(
        Rectangle()
          .frame(height: 0.5)
          .foregroundColor(Color.gray.opacity(0.3)),
        alignment: .top
      )
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
  let item: LogItemDTO
  var onUpdate: ((LogItemDTO) -> Void)?
  @State private var showingEditSheet = false

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline) {
        if item.isMasterDeleted {
          Text("\(item.brandName) \(item.productName)")
            .font(.subheadline.weight(.medium))
            .foregroundColor(.secondary)
            .strikethrough()
            .lineLimit(1)
          Text(NSLocalizedString("(Deleted)", comment: "Deleted Food indicator"))
            .font(.caption2)
            .foregroundColor(.red)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.red.opacity(0.1))
            .cornerRadius(4)
        } else {
          Text("\(item.brandName) \(item.productName)")
            .font(.subheadline.weight(.medium))
            .foregroundColor(.primary)
            .lineLimit(1)
        }
        Spacer()
        Text("\(item.calories, specifier: "%.0f")")
          .font(.system(size: 15, weight: .semibold, design: .rounded))
        + Text(" kcal")
          .font(.system(size: 12))
          .foregroundColor(.secondary)
      }
      HStack(spacing: 6) {
        MacroChip(label: "P", value: item.protein, color: .blue)
        MacroChip(label: "F", value: item.fat, color: .yellow)
        MacroChip(label: "S", value: item.netCarbs, color: .green)
        MacroChip(label: "Fb", value: item.dietaryFiber, color: .brown)
        Spacer()
        Text("\(NutritionFormatter.formatNutrition(item.numberOfServings)) \(item.portionUnit)")
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
    .onTapGesture { showingEditSheet = true }
    .sheet(isPresented: $showingEditSheet) {
      EditItemView(item: item, onSaved: onUpdate)
    }
  }
}

#Preview {
  ContentView()
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
    // すべての栄養素に適応的フォーマットを使用
    return NutritionFormatter.formatNutrition(value)
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
    HStack(spacing: 3) {
      Circle()
        .fill(color)
        .frame(width: 6, height: 6)

      Text(name)
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(color.opacity(0.9))

      Text("\(value, specifier: value >= 100 ? "%.0f" : "%.1f")\(unit)")
        .font(.system(size: 13, weight: .semibold, design: .rounded))
    }
    .padding(.vertical, 3)
    .padding(.horizontal, 6)
    .background(color.opacity(0.06))
    .cornerRadius(6)
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

// MARK: - Date Swipe Gesture

class HorizontalPanGestureRecognizer: UIPanGestureRecognizer {
  private var isDirectionDetermined = false

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesBegan(touches, with: event)
    guard let touch = touches.first, let rootView = self.view else { return }
    let location = touch.location(in: rootView)
    if isLocationInTableView(location, in: rootView) {
      state = .failed
    }
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesMoved(touches, with: event)
    guard !isDirectionDetermined else { return }
    let t = translation(in: view)
    if abs(t.x) > 8 || abs(t.y) > 8 {
      isDirectionDetermined = true
      if abs(t.y) >= abs(t.x) { state = .failed }
    }
  }

  override func reset() {
    super.reset()
    isDirectionDetermined = false
  }

  private func isLocationInTableView(_ location: CGPoint, in rootView: UIView) -> Bool {
    var hitView: UIView? = rootView.hitTest(location, with: nil)
    while let v = hitView {
      if v is UICollectionView { return true }
      hitView = v.superview
    }
    return false
  }
}

struct DateSwipeGesture: UIGestureRecognizerRepresentable {
  @Binding var dragOffset: CGFloat
  var onDateChange: (Bool) -> Void

  func makeUIGestureRecognizer(context: Context) -> HorizontalPanGestureRecognizer {
    let recognizer = HorizontalPanGestureRecognizer()
    recognizer.delegate = context.coordinator
    return recognizer
  }

  func handleUIGestureRecognizerAction(_ recognizer: HorizontalPanGestureRecognizer, context: Context) {
    let translation = recognizer.translation(in: recognizer.view)
    let velocity = recognizer.velocity(in: recognizer.view)

    switch recognizer.state {
    case .changed:
      dragOffset = translation.x
    case .ended:
      let h = translation.x
      let screenWidth = UIScreen.main.bounds.width
      if abs(h) > 50 || abs(velocity.x) > 500 {
        let goForward = h < 0
        let exitOffset: CGFloat = goForward ? -screenWidth : screenWidth
        withAnimation(.easeInOut(duration: 0.2)) { dragOffset = exitOffset }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
          onDateChange(goForward)
          dragOffset = -exitOffset
          withAnimation(.easeInOut(duration: 0.2)) { dragOffset = 0 }
        }
      } else {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragOffset = 0 }
      }
    case .cancelled, .failed:
      withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragOffset = 0 }
    default:
      break
    }
  }

  func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

  class Coordinator: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
      !isFromTableView(other)
    }

    private func isFromTableView(_ recognizer: UIGestureRecognizer) -> Bool {
      var view: UIView? = recognizer.view
      while let v = view {
        if v is UICollectionView { return true }
        view = v.superview
      }
      return false
    }
  }
}
