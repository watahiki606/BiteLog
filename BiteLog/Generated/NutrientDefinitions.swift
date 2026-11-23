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
  case potassium
  case calcium
  case magnesium
  case iron
  case vitaminA
  case vitaminD
  case vitaminC
  case phosphorus
  case zinc
  case copper
  case manganese
  case iodine
  case selenium
  case chromium
  case molybdenum
  case vitaminE
  case vitaminK
  case vitaminB1
  case vitaminB2
  case niacin
  case vitaminB6
  case vitaminB12
  case folate
  case pantothenicAcid
  case biotin
  case n3FattyAcids
  case n6FattyAcids
}

extension NutrientID {
  var definition: NutrientDefinition {
    switch self {
    case .calories:
      return NutrientDefinition(
        id: .calories, column: "calories", unit: "kcal", fractionDigits: 0,
        group: .energy, core: true, detail: false, label: .mandatory)
    case .protein:
      return NutrientDefinition(
        id: .protein, column: "protein", unit: "g", fractionDigits: 1,
        group: .macro, core: true, detail: false, label: .mandatory)
    case .fat:
      return NutrientDefinition(
        id: .fat, column: "fat", unit: "g", fractionDigits: 1,
        group: .macro, core: true, detail: false, label: .mandatory)
    case .netCarbs:
      return NutrientDefinition(
        id: .netCarbs, column: "net_carbs", unit: "g", fractionDigits: 1,
        group: .macro, core: true, detail: false, label: .optional)
    case .dietaryFiber:
      return NutrientDefinition(
        id: .dietaryFiber, column: "dietary_fiber", unit: "g", fractionDigits: 1,
        group: .carbohydrate, core: true, detail: false, label: .recommended)
    case .saltEquivalent:
      return NutrientDefinition(
        id: .saltEquivalent, column: "salt_equivalent", unit: "g", fractionDigits: 1,
        group: .mineral, core: false, detail: false, label: .mandatory)
    case .saturatedFat:
      return NutrientDefinition(
        id: .saturatedFat, column: "saturated_fat", unit: "g", fractionDigits: 1,
        group: .lipid, core: false, detail: false, label: .recommended)
    case .potassium:
      return NutrientDefinition(
        id: .potassium, column: "potassium", unit: "mg", fractionDigits: 0,
        group: .mineral, core: false, detail: false, label: .optional)
    case .calcium:
      return NutrientDefinition(
        id: .calcium, column: "calcium", unit: "mg", fractionDigits: 0,
        group: .mineral, core: false, detail: false, label: .optional)
    case .magnesium:
      return NutrientDefinition(
        id: .magnesium, column: "magnesium", unit: "mg", fractionDigits: 0,
        group: .mineral, core: false, detail: false, label: .optional)
    case .iron:
      return NutrientDefinition(
        id: .iron, column: "iron", unit: "mg", fractionDigits: 1,
        group: .mineral, core: false, detail: false, label: .optional)
    case .vitaminA:
      return NutrientDefinition(
        id: .vitaminA, column: "vitamin_a", unit: "µg", fractionDigits: 0,
        group: .vitamin, core: false, detail: false, label: .optional)
    case .vitaminD:
      return NutrientDefinition(
        id: .vitaminD, column: "vitamin_d", unit: "µg", fractionDigits: 1,
        group: .vitamin, core: false, detail: false, label: .optional)
    case .vitaminC:
      return NutrientDefinition(
        id: .vitaminC, column: "vitamin_c", unit: "mg", fractionDigits: 0,
        group: .vitamin, core: false, detail: false, label: .optional)
    case .phosphorus:
      return NutrientDefinition(
        id: .phosphorus, column: "phosphorus", unit: "mg", fractionDigits: 0,
        group: .mineral, core: false, detail: true, label: .optional)
    case .zinc:
      return NutrientDefinition(
        id: .zinc, column: "zinc", unit: "mg", fractionDigits: 1,
        group: .mineral, core: false, detail: true, label: .optional)
    case .copper:
      return NutrientDefinition(
        id: .copper, column: "copper", unit: "mg", fractionDigits: 2,
        group: .mineral, core: false, detail: true, label: .optional)
    case .manganese:
      return NutrientDefinition(
        id: .manganese, column: "manganese", unit: "mg", fractionDigits: 2,
        group: .mineral, core: false, detail: true, label: .optional)
    case .iodine:
      return NutrientDefinition(
        id: .iodine, column: "iodine", unit: "µg", fractionDigits: 0,
        group: .mineral, core: false, detail: true, label: .optional)
    case .selenium:
      return NutrientDefinition(
        id: .selenium, column: "selenium", unit: "µg", fractionDigits: 0,
        group: .mineral, core: false, detail: true, label: .optional)
    case .chromium:
      return NutrientDefinition(
        id: .chromium, column: "chromium", unit: "µg", fractionDigits: 0,
        group: .mineral, core: false, detail: true, label: .optional)
    case .molybdenum:
      return NutrientDefinition(
        id: .molybdenum, column: "molybdenum", unit: "µg", fractionDigits: 0,
        group: .mineral, core: false, detail: true, label: .optional)
    case .vitaminE:
      return NutrientDefinition(
        id: .vitaminE, column: "vitamin_e", unit: "mg", fractionDigits: 1,
        group: .vitamin, core: false, detail: true, label: .optional)
    case .vitaminK:
      return NutrientDefinition(
        id: .vitaminK, column: "vitamin_k", unit: "µg", fractionDigits: 0,
        group: .vitamin, core: false, detail: true, label: .optional)
    case .vitaminB1:
      return NutrientDefinition(
        id: .vitaminB1, column: "vitamin_b1", unit: "mg", fractionDigits: 2,
        group: .vitamin, core: false, detail: true, label: .optional)
    case .vitaminB2:
      return NutrientDefinition(
        id: .vitaminB2, column: "vitamin_b2", unit: "mg", fractionDigits: 2,
        group: .vitamin, core: false, detail: true, label: .optional)
    case .niacin:
      return NutrientDefinition(
        id: .niacin, column: "niacin", unit: "mg", fractionDigits: 1,
        group: .vitamin, core: false, detail: true, label: .optional)
    case .vitaminB6:
      return NutrientDefinition(
        id: .vitaminB6, column: "vitamin_b6", unit: "mg", fractionDigits: 2,
        group: .vitamin, core: false, detail: true, label: .optional)
    case .vitaminB12:
      return NutrientDefinition(
        id: .vitaminB12, column: "vitamin_b12", unit: "µg", fractionDigits: 1,
        group: .vitamin, core: false, detail: true, label: .optional)
    case .folate:
      return NutrientDefinition(
        id: .folate, column: "folate", unit: "µg", fractionDigits: 0,
        group: .vitamin, core: false, detail: true, label: .optional)
    case .pantothenicAcid:
      return NutrientDefinition(
        id: .pantothenicAcid, column: "pantothenic_acid", unit: "mg", fractionDigits: 2,
        group: .vitamin, core: false, detail: true, label: .optional)
    case .biotin:
      return NutrientDefinition(
        id: .biotin, column: "biotin", unit: "µg", fractionDigits: 1,
        group: .vitamin, core: false, detail: true, label: .optional)
    case .n3FattyAcids:
      return NutrientDefinition(
        id: .n3FattyAcids, column: "n3_fatty_acids", unit: "g", fractionDigits: 2,
        group: .lipid, core: false, detail: true, label: .optional)
    case .n6FattyAcids:
      return NutrientDefinition(
        id: .n6FattyAcids, column: "n6_fatty_acids", unit: "g", fractionDigits: 2,
        group: .lipid, core: false, detail: true, label: .optional)
    }
  }
}
