import SwiftUI

/// 食品の入力で、成分表から食品を選んで値を欄に入れる欄。
///
/// 食品名で成分表を探して候補を出す。違う語で探すこともできる。候補を押すと、重さの分の値が
/// 下の栄養素の欄に入る。入れた値は手で打った値と同じで直せる。選ばなくても保存できる。
///
/// 画面では「成分表」と言わない。使う人には何の表か伝わらないので、似た食品の値を入れる操作として見せる。
/// 出典はプロフィールのデータの出典に書く。
struct CompositionPickSection: View {
  let productName: String
  let defaultGrams: Double
  /// 最後に選んだ食品と重さ。選んだことを欄の下に出す
  let picked: (name: String, grams: Double)?
  let onPick: (CompositionFoodDTO, Double) -> Void

  @State private var searchText = ""
  @State private var gramsText = ""
  @State private var candidates: [CompositionFoodDTO] = []
  @FocusState private var focusedField: Field?

  private enum Field { case search, grams }

  private var query: String {
    let typed = searchText.trimmingCharacters(in: .whitespaces)
    return typed.isEmpty ? CompositionPick.query(for: productName) : typed
  }

  /// 選んだ食品の重さ。1回分に含まれる食べられる部分の重さ
  private var weightTitle: String {
    NSLocalizedString("Weight per portion", comment: "Weight of the picked food in one portion")
  }

  private var grams: Double {
    Double(gramsText.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil } ?? defaultGrams
  }

  var body: some View {
    Section {
      HStack(spacing: 6) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
        TextField(
          query.isEmpty ? NSLocalizedString("Search foods", comment: "Similar food search placeholder") : query,
          text: $searchText)
          .focused($focusedField, equals: .search)
      }
      .inputFieldStyle(isFocused: focusedField == .search)
      LabeledContent(weightTitle) {
        NumberInputField(
          title: weightTitle, text: $gramsText, placeholder: NutritionFormatter.formatNutrition(defaultGrams),
          unit: "g", focus: $focusedField, field: .grams)
      }
      if candidates.isEmpty {
        Text(query.isEmpty
          ? NSLocalizedString("Enter the product name to see candidates.", comment: "Similar food pick hint")
          : NSLocalizedString("No matching food.", comment: "Similar food pick empty"))
          .foregroundStyle(.secondary)
      }
      ForEach(candidates) { food in
        Button {
          onPick(food, grams)
        } label: {
          HStack {
            Text(food.name).foregroundStyle(.primary).multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            Image(systemName: "arrow.down.circle").foregroundStyle(.tint)
          }
        }
        .accessibilityHint(NSLocalizedString(
          "Fills the nutrient fields with its values", comment: "Composition candidate hint"))
      }
      if let picked {
        Text(String(
          format: NSLocalizedString("Filled with %@, %@ g. You can edit the values.", comment: "Composition pick result"),
          picked.name, NutritionFormatter.formatNutrition(picked.grams)))
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    } header: {
      Text(NSLocalizedString("Fill from a Similar Food", comment: "Similar food pick section"))
    }
    .task(id: query) {
      // 打つたびに探さないよう、少し待ってから探す。名前を変えれば候補も変わる
      try? await Task.sleep(for: .milliseconds(400))
      guard !Task.isCancelled else { return }
      candidates = query.isEmpty ? [] : ((try? await APIClient.shared.searchComposition(query: query, limit: 5)) ?? [])
    }
  }
}
