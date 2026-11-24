import Foundation

/// 統計で栄養素を押したときに出す説明と、その出典。
///
/// 文言は NutrientInfo.strings の表に「栄養素.欄」の鍵で置く。出典に書かれていない欄は表に置かず、画面にも出さない。
/// 推測で埋めると、出典を添えていても裏の取れない説明になるため。
struct NutrientInfo: Identifiable {
  /// 文言の表の鍵。定義の栄養素は NutrientID の rawValue、定義に無い炭水化物は carbohydrate
  let id: String
  let nutrient: any NutrientDisplaying

  init(_ id: NutrientID) {
    self.id = id.rawValue
    nutrient = id
  }

  init(_ nutrient: Nutrient) {
    id = nutrient.nutrientID?.rawValue ?? "carbohydrate"
    self.nutrient = nutrient
  }

  /// 何のための栄養素か
  var role: String? { text("role") }
  /// 足りないとき
  var shortage: String? { text("shortage") }
  /// とりすぎたとき
  var excess: String? { text("excess") }
  /// 多く含む食品の例
  var foods: String? { text("foods") }

  var sources: [Source] { Self.sources[id] ?? [] }

  private func text(_ field: String) -> String? {
    let key = "\(id).\(field)"
    // 表に無い鍵は value をそのまま返す。鍵の文字を説明として出さないよう、無いことを見分ける
    let missing = "\u{0}"
    let text = Bundle.main.localizedString(forKey: key, value: missing, table: "NutrientInfo")
    return text == missing ? nil : text
  }

  struct Source: Hashable {
    let title: String
    let url: URL
  }

  /// 厚生労働省 e-ヘルスネットの用語辞典。今は健康日本21アクション支援システムの中にある
  private static func eHealthNet(_ page: String, _ file: String) -> Source {
    Source(
      title: String(
        format: NSLocalizedString("NutrientInfo.Source.EHealthNet", comment: "Source title of an e-Health Net page"),
        page),
      url: URL(string: "https://kennet.mhlw.go.jp/information/information/dictionary/food/\(file)")!)
  }

  /// 国立健康・栄養研究所「健康食品」の安全性・有効性情報のビタミンとミネラルの解説
  private static func healthFoods(_ page: String, _ path: String) -> Source {
    Source(
      title: String(
        format: NSLocalizedString("NutrientInfo.Source.HFNet", comment: "Source title of a NIHN health food page"),
        page),
      url: URL(string: "https://hfnet.nibn.go.jp/\(path)/")!)
  }

  private static let fatPage = eHealthNet("脂肪 / 脂質", "ye-014")
  private static let carbohydratePage = eHealthNet("炭水化物 / 糖質", "ye-018")
  private static let unsaturatedPage = eHealthNet("不飽和脂肪酸", "ye-031")

  /// 説明の文言を確かめたページ。ページの題名は原文のまま書く
  static let sources: [String: [Source]] = [
    "calories": [eHealthNet("エネルギー産生栄養素", "ye-013")],
    "protein": [eHealthNet("たんぱく質", "ye-044")],
    "fat": [fatPage],
    "netCarbs": [carbohydratePage],
    "carbohydrate": [carbohydratePage],
    "dietaryFiber": [eHealthNet("食物繊維", "ye-016")],
    "saltEquivalent": [eHealthNet("ナトリウム", "ye-024")],
    "saturatedFat": [fatPage],
    "n3FattyAcids": [unsaturatedPage, fatPage],
    "n6FattyAcids": [unsaturatedPage, fatPage],
    "potassium": [eHealthNet("カリウム", "ye-005")],
    "calcium": [healthFoods("カルシウム", "mineral/detail660")],
    "magnesium": [healthFoods("マグネシウム", "mineral/detail656")],
    "phosphorus": [healthFoods("リン", "mineral/detail661")],
    "iron": [healthFoods("鉄", "mineral/detail675")],
    "zinc": [healthFoods("亜鉛", "mineral/detail672")],
    "copper": [healthFoods("銅", "mineral/detail674")],
    "manganese": [healthFoods("マンガン", "mineral/detail681")],
    "iodine": [healthFoods("ヨウ素", "mineral/detail680")],
    "selenium": [healthFoods("セレン", "mineral/detail682")],
    "chromium": [healthFoods("クロム", "mineral/detail758")],
    "molybdenum": [healthFoods("モリブデン", "mineral/detail759")],
    "vitaminA": [healthFoods("ビタミンA", "vitamin/detail171")],
    "vitaminD": [healthFoods("ビタミンD", "vitamin/detail221")],
    "vitaminE": [healthFoods("ビタミンE", "vitamin/detail176")],
    "vitaminK": [healthFoods("ビタミンK", "vitamin/detail17")],
    "vitaminB1": [healthFoods("ビタミンB1", "vitamin/detail173")],
    "vitaminB2": [healthFoods("ビタミンB2", "vitamin/detail175")],
    "niacin": [healthFoods("ナイアシン", "vitamin/detail181")],
    "vitaminB6": [healthFoods("ビタミンB6", "vitamin/detail149")],
    "vitaminB12": [healthFoods("ビタミンB12", "vitamin/detail177")],
    "folate": [healthFoods("葉酸", "vitamin/detail652")],
    "pantothenicAcid": [healthFoods("パントテン酸", "vitamin/detail274")],
    "biotin": [healthFoods("ビオチン", "vitamin/detail180")],
    "vitaminC": [healthFoods("ビタミンC", "vitamin/detail179")],
  ]
}
