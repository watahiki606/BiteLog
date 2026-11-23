import Foundation

/// 栄養素の量を、食事摂取基準の値と比べた結果。
///
/// 食塩相当量や飽和脂肪酸のような上限の目標は、超えたかを見る。
/// カリウムや鉄のように満たしたい栄養素は、届いたかを見る。満たしたい栄養素が基準を上回っても超過とは呼ばない。
struct ReferenceProgress: Equatable {
  let goal: DietaryReferenceIntakes.Goal
  let amount: Double
  /// 比べる量。栄養素の単位で持つ。飽和脂肪酸はエネルギーの割合から g に直してある
  let target: Double

  /// 比べられないときは nil。飽和脂肪酸で、比べるエネルギーが 0 のとき
  ///
  /// - Parameter energy: 飽和脂肪酸の目標量はエネルギーに占める割合なので、その割合を掛けるエネルギー。
  ///   1日の合計では目標のカロリーを渡す。その日に食べたエネルギーで割ると、朝の1品だけで超過になる。
  ///   期間の平均では、その期間に食べたエネルギーの1日平均を渡す
  init?(amount: Double, goal: DietaryReferenceIntakes.Goal, energy: Double) {
    let target: Double
    if goal.comparison == .atMostPercentOfEnergy {
      // 脂質は 1 g あたり 9 kcal
      target = energy * goal.value / 100 / 9
    } else {
      target = goal.value
    }
    guard target > 0 else { return nil }
    self.goal = goal
    self.amount = amount
    self.target = target
  }

  /// 上限の目標か。食塩相当量と飽和脂肪酸
  var isLimit: Bool {
    goal.comparison == .lessThan || goal.comparison == .atMostPercentOfEnergy
  }

  var ratio: Double { amount / target }

  /// 上限の目標を超えた
  var isOver: Bool { isLimit && amount > target }

  /// 満たしたい栄養素が基準に届いた
  var isReached: Bool { !isLimit && amount >= target }

  /// 基準までの残り。上限の目標なら、まだ摂ってよい量
  var remaining: Double { max(target - amount, 0) }

  /// 上限の目標を超えた量
  var excess: Double { max(amount - target, 0) }

  var percent: Int { Int((ratio * 100).rounded()) }

  /// 輪の長さ。基準の量で一周し、それ以上は伸ばさない
  var ringFraction: Double { min(max(ratio, 0), 1) }
}
