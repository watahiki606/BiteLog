import SwiftData
import SwiftUI

struct FoodMasterManagementView: View {
  @Environment(\.dismiss) var dismiss
  @Environment(\.modelContext) private var modelContext
  @Query private var foodMasters: [FoodMaster]
  
  @State private var searchText = ""
  @State private var showingAddForm = false
  @State private var selectedFoodMaster: FoodMaster?
  @State private var showingEditForm = false
  @State private var showingDeleteConfirmation = false
  
  // ページネーション用
  @State private var currentPage = 0
  private let pageSize = 20
  
  var filteredFoodMasters: [FoodMaster] {
    if searchText.isEmpty {
      return Array(foodMasters.prefix(pageSize * (currentPage + 1)))
    } else {
      return foodMasters.filter { foodMaster in
        foodMaster.brandName.localizedCaseInsensitiveContains(searchText) ||
        foodMaster.productName.localizedCaseInsensitiveContains(searchText)
      }
    }
  }
  
  var body: some View {
    VStack {
      // 検索バー
      HStack {
        Image(systemName: "magnifyingglass")
          .foregroundColor(.secondary)
          .padding(.leading, 8)
        
        TextField(NSLocalizedString("Search food items", comment: "Search food items"), text: $searchText)
          .padding(10)
          .background(Color(UIColor.secondarySystemBackground))
          .cornerRadius(10)
        
        if !searchText.isEmpty {
          Button(action: {
            searchText = ""
          }) {
            Image(systemName: "xmark.circle.fill")
              .foregroundColor(.secondary)
              .padding(.trailing, 8)
          }
        }
      }
      .padding(.horizontal)
      .padding(.top, 8)
      
      if foodMasters.isEmpty {
        // フードが0件の場合に表示する登録促進ビュー
        EmptyFoodMasterView(showAddForm: $showingAddForm)
      } else {
        // フード一覧
        List {
          ForEach(filteredFoodMasters) { foodMaster in
            FoodMasterRow(foodMaster: foodMaster)
              .contentShape(Rectangle())
              .onTapGesture {
                selectedFoodMaster = foodMaster
                showingEditForm = true
              }
              .swipeActions {
                Button(role: .destructive) {
                  selectedFoodMaster = foodMaster
                  showingDeleteConfirmation = true
                } label: {
                  Label("Delete", systemImage: "trash")
                }
              }
          }
          
          // もっと読み込むボタン（検索していない場合のみ表示）
          if searchText.isEmpty && foodMasters.count > pageSize * (currentPage + 1) {
            Button(NSLocalizedString("Load More", comment: "Load more")) {
              currentPage += 1
            }
          }
        }
        .listStyle(.insetGrouped)
      }
    }
    .navigationTitle(NSLocalizedString("Manage food", comment: "Manage food"))
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          showingAddForm = true
        } label: {
          Image(systemName: "plus")
        }
      }
    }
    .sheet(isPresented: $showingAddForm) {
      FoodMasterFormView(mode: .add)
    }
    .sheet(item: $selectedFoodMaster, onDismiss: {
      selectedFoodMaster = nil
    }) { foodMaster in
      if showingEditForm {
        FoodMasterFormView(mode: .edit(foodMaster))
      }
    }
    .alert("Delete Food Item?", isPresented: $showingDeleteConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Delete", role: .destructive) {
        if let foodMaster = selectedFoodMaster {
          deleteFoodMaster(foodMaster)
        }
      }
    } message: {
      Text("This will permanently delete this food item from your master data. This action cannot be undone.")
    }
  }
  
  private func deleteFoodMaster(_ foodMaster: FoodMaster) {
    // 関連するLogItemを検索
    let foodMasterId = foodMaster.id
    let descriptor = FetchDescriptor<LogItem>(
      predicate: #Predicate<LogItem> { logItem in
        if let itemFoodMaster = logItem.foodMaster {
          return itemFoodMaster.id == foodMasterId
        } else {
          return false
        }
      }
    )
    
    if let relatedLogItems = try? modelContext.fetch(descriptor), !relatedLogItems.isEmpty {
      // 関連するLogItemがある場合は、FoodMasterへの参照をnilに設定
      for logItem in relatedLogItems {
        logItem.foodMaster = nil
      }
    }
    
    // FoodMasterを削除
    modelContext.delete(foodMaster)
    selectedFoodMaster = nil
  }
}

// フードが0件の場合に表示するビュー
struct EmptyFoodMasterView: View {
  @Binding var showAddForm: Bool
  
  var body: some View {
    VStack(spacing: 20) {
      Spacer()
      
      Image(systemName: "fork.knife")
        .font(.system(size: 70))
        .foregroundColor(.secondary)
      
      Text(NSLocalizedString("No Food Items", comment: "No food items"))
        .font(.title2)
        .fontWeight(.bold)
      
      Text(NSLocalizedString("Add your first food item to start tracking your nutrition.", comment: "Add food prompt"))
        .multilineTextAlignment(.center)
        .foregroundColor(.secondary)
        .padding(.horizontal, 40)
      
      Button {
        showAddForm = true
      } label: {
        Text(NSLocalizedString("Add Food Item", comment: "Add food item"))
          .fontWeight(.semibold)
          .padding(.horizontal, 20)
          .padding(.vertical, 10)
          .background(Color.blue)
          .foregroundColor(.white)
          .cornerRadius(10)
      }
      .padding(.top, 10)
      
      Spacer()
    }
    .padding()
  }
}

// フード行表示用コンポーネント
struct FoodMasterRow: View {
  let foodMaster: FoodMaster
  
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text("\(foodMaster.brandName) \(foodMaster.productName)")
          .font(.headline)
        
        Spacer()
        
        Text("\(foodMaster.calories, specifier: "%.0f") kcal")
          .font(.subheadline)
          .foregroundColor(.secondary)
      }
      
      HStack {
        Text("P: \(foodMaster.protein, specifier: "%.1f")g")
          .font(.caption)
          .foregroundColor(.blue)
        
        Text("F: \(foodMaster.fat, specifier: "%.1f")g")
          .font(.caption)
          .foregroundColor(.yellow)
        
        Text("C: \(foodMaster.carbohydrates, specifier: "%.1f")g")
          .font(.caption)
          .foregroundColor(.green)
        
        Spacer()
        
        Text("1 \(foodMaster.portionUnit)")
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
    .padding(.vertical, 4)
  }
}

// フード追加・編集フォーム
struct FoodMasterFormView: View {
  enum FormMode: Equatable {
    case add
    case edit(FoodMaster)
  }
  
  let mode: FormMode
  @Environment(\.dismiss) var dismiss
  @Environment(\.modelContext) private var modelContext
  
  @State private var brandName = ""
  @State private var productName = ""
  @State private var calories = ""
  @State private var carbohydrates = ""
  @State private var fat = ""
  @State private var protein = ""
  @State private var portionUnit = ""
  
  var title: String {
    switch mode {
    case .add:
      return NSLocalizedString("Add Food Item", comment: "Add food item")
    case .edit:
      return NSLocalizedString("Edit Food Item", comment: "Edit food item")
    }
  }
  
  var body: some View {
    NavigationStack {
      Form {
        Section(header: Text(NSLocalizedString("Basic Info", comment: "Basic info"))) {
          TextField(NSLocalizedString("Brand Name", comment: "Brand name"), text: $brandName)
          TextField(NSLocalizedString("Product Name", comment: "Product name"), text: $productName)
          TextField(NSLocalizedString("Portion Unit (e.g. piece, g)", comment: "Portion unit"), text: $portionUnit)
        }
        
        Section(header: Text(NSLocalizedString("Nutrition (per 1 \(portionUnit.isEmpty ? "unit" : portionUnit))", comment: "Nutrition"))) {
          HStack {
            Text(NSLocalizedString("Calories", comment: "Calories"))
            Spacer()
            TextField(NSLocalizedString("0", comment: "0"), text: $calories)
              .keyboardType(.decimalPad)
              .multilineTextAlignment(.trailing)
            Text(NSLocalizedString("kcal", comment: "kcal"))
          }
          
          HStack {
            Text(NSLocalizedString("Protein", comment: "Protein"))
            Spacer()
            TextField(NSLocalizedString("0", comment: "0"), text: $protein)
              .keyboardType(.decimalPad)
              .multilineTextAlignment(.trailing)
            Text(NSLocalizedString("g", comment: "g"))
          }
          
          HStack {
            Text(NSLocalizedString("Fat", comment: "Fat"))
            Spacer()
            TextField(NSLocalizedString("0", comment: "0"), text: $fat)
              .keyboardType(.decimalPad)
              .multilineTextAlignment(.trailing)
            Text(NSLocalizedString("g", comment: "g"))
          }
          
          HStack {
            Text(NSLocalizedString("Carbohydrates", comment: "Carbohydrates"))
            Spacer()
            TextField(NSLocalizedString("0", comment: "0"), text: $carbohydrates)
              .keyboardType(.decimalPad)
              .multilineTextAlignment(.trailing)
            Text(NSLocalizedString("g", comment: "g"))
          }
        }
      }
      .navigationTitle(title)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(NSLocalizedString("Cancel", comment: "Cancel")) {
            dismiss()
          }
        }
        
        ToolbarItem(placement: .confirmationAction) {
          Button(NSLocalizedString("Save", comment: "Save")) {
            saveFoodMaster()
            dismiss()
          }
          .disabled(brandName.isEmpty || productName.isEmpty || portionUnit.isEmpty)
        }
      }
      .onAppear {
        if case .edit(let foodMaster) = mode {
          // 編集モードの場合、既存の値をフォームにセット
          brandName = foodMaster.brandName
          productName = foodMaster.productName
          calories = String(format: "%.1f", foodMaster.calories)
          carbohydrates = String(format: "%.1f", foodMaster.carbohydrates)
          fat = String(format: "%.1f", foodMaster.fat)
          protein = String(format: "%.1f", foodMaster.protein)
          portionUnit = foodMaster.portionUnit
        }
      }
    }
  }
  
  private func saveFoodMaster() {
    // 入力値を数値に変換
    let caloriesValue = Double(calories) ?? 0
    let carbohydratesValue = Double(carbohydrates) ?? 0
    let fatValue = Double(fat) ?? 0
    let proteinValue = Double(protein) ?? 0
    
    switch mode {
    case .add:
      // 新規追加
      let newFoodMaster = FoodMaster(
        brandName: brandName,
        productName: productName,
        calories: caloriesValue,
        carbohydrates: carbohydratesValue,
        fat: fatValue,
        protein: proteinValue,
        portionUnit: portionUnit,
        portion: 1.0  // 1単位あたりに正規化
      )
      modelContext.insert(newFoodMaster)
      
    case .edit(let foodMaster):
      // 既存データの更新
      foodMaster.brandName = brandName
      foodMaster.productName = productName
      foodMaster.calories = caloriesValue
      foodMaster.carbohydrates = carbohydratesValue
      foodMaster.fat = fatValue
      foodMaster.protein = proteinValue
      foodMaster.portionUnit = portionUnit
      
      // uniqueKeyも更新
      let caloriesStr = String(format: "%.2f", caloriesValue)
      let carbsStr = String(format: "%.2f", carbohydratesValue)
      let fatStr = String(format: "%.2f", fatValue)
      let proteinStr = String(format: "%.2f", proteinValue)
      foodMaster.uniqueKey = "\(brandName)|\(productName)|\(caloriesStr)|\(carbsStr)|\(fatStr)|\(proteinStr)|\(portionUnit)"
    }
  }
}

// Identifiableプロトコル準拠のための拡張
extension FoodMasterFormView.FormMode: Identifiable {
  var id: String {
    switch self {
    case .add:
      return "add"
    case .edit(let foodMaster):
      return "edit_\(foodMaster.id.uuidString)"
    }
  }
}

// FoodMasterをIdentifiableとして扱うための拡張
extension FoodMaster: Identifiable {}

#Preview {
  FoodMasterManagementView()
    .modelContainer(for: [FoodMaster.self, LogItem.self], inMemory: true)
} 