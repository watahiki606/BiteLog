// 生成したファイル。shared/nutrients.json を直して bun run generate:nutrients で作り直す

/// 栄養素の識別子。rawValue は API の JSON とスナップショットのキー
enum NutrientID: String, CaseIterable, Codable, Sendable {
  case calories
  case protein
  case fat
  case netCarbs
  case dietaryFiber
  case saltEquivalent
  case saturatedFat
}

extension NutrientID {
  var definition: NutrientDefinition {
    switch self {
    case .calories:
      return NutrientDefinition(
        id: .calories, column: "calories", unit: "kcal", fractionDigits: 0,
        group: .energy, core: true, label: .mandatory)
    case .protein:
      return NutrientDefinition(
        id: .protein, column: "protein", unit: "g", fractionDigits: 1,
        group: .macro, core: true, label: .mandatory)
    case .fat:
      return NutrientDefinition(
        id: .fat, column: "fat", unit: "g", fractionDigits: 1,
        group: .macro, core: true, label: .mandatory)
    case .netCarbs:
      return NutrientDefinition(
        id: .netCarbs, column: "net_carbs", unit: "g", fractionDigits: 1,
        group: .macro, core: true, label: .optional)
    case .dietaryFiber:
      return NutrientDefinition(
        id: .dietaryFiber, column: "dietary_fiber", unit: "g", fractionDigits: 1,
        group: .carbohydrate, core: true, label: .recommended)
    case .saltEquivalent:
      return NutrientDefinition(
        id: .saltEquivalent, column: "salt_equivalent", unit: "g", fractionDigits: 1,
        group: .mineral, core: false, label: .mandatory)
    case .saturatedFat:
      return NutrientDefinition(
        id: .saturatedFat, column: "saturated_fat", unit: "g", fractionDigits: 1,
        group: .lipid, core: false, label: .recommended)
    }
  }
}
