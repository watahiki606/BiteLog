import Foundation

/// 体組成計で測っている間の段階。いま何をすればよいかを、段階ごとに1か所で決める。
///
/// シートの中央の大きな表示も、カードの下段の1行も、ここから引く。
/// 段階の見せ方を直すときに、2つの画面で文言がずれないようにするため。
enum MeasurementStage: Equatable, CaseIterable {
  case searching
  /// 体重計に乗って待っている。体重計は測り終えるまで応答しないので、
  /// アプリは乗ったことを知れない。この段階は「乗ってください」から「乗ったまま待つ」まで続く。
  case waitingForStep
  /// 測り終えた。体重計は測り終えてから応答するので、降りてよい
  case reading
  case failed

  /// 失敗は `Activity` に無い。失敗の画面には `.failed` を別に渡す
  init?(activity: BodyCompositionModel.Activity) {
    switch activity {
    case .idle: return nil
    case .searching: self = .searching
    case .waitingForStep: self = .waitingForStep
    case .reading: self = .reading
    }
  }

  /// 段階の見せ方の表。
  struct Content {
    /// 大きな丸い印の中の絵
    let symbol: String
    let title: String
    /// 見出しの下の補足。失敗は文面が測るたびに変わるので持たない
    let detail: String?
    /// カードの下段に出す1行。失敗はカードが文面そのものを出すので持たない
    let cardLine: String?
    /// 進み具合の何段目か。失敗は進み具合を出さない
    let stepIndex: Int?
  }

  var content: Content {
    switch self {
    case .searching:
      return Content(
        symbol: "antenna.radiowaves.left.and.right",
        title: NSLocalizedString("Looking for the scale", comment: "Scale stage title"),
        detail: NSLocalizedString(
          "If it is not found, press the scale's communication button while it is off",
          comment: "Scale stage detail"),
        cardLine: NSLocalizedString("Looking for the scale", comment: "Scale import status"),
        stepIndex: 0)
    case .waitingForStep:
      return Content(
        symbol: "shoeprints.fill",
        title: NSLocalizedString("Step on the scale", comment: "Scale stage title"),
        detail: NSLocalizedString(
          "Stay on the scale until it finishes", comment: "Scale stage detail"),
        cardLine: NSLocalizedString("Step on the scale", comment: "Scale import status"),
        stepIndex: 1)
    case .reading:
      return Content(
        symbol: "checkmark",
        title: NSLocalizedString("Measurement complete", comment: "Scale stage title"),
        detail: NSLocalizedString(
          "Receiving the result. You can step off now", comment: "Scale stage detail"),
        cardLine: NSLocalizedString("Receiving measurements", comment: "Scale import status"),
        stepIndex: 2)
    case .failed:
      return Content(
        symbol: "exclamationmark.triangle",
        title: NSLocalizedString("Could not measure", comment: "Scale stage title"),
        detail: nil, cardLine: nil, stepIndex: nil)
    }
  }

  /// カードの下段の1行。結果を開いたまま次を待っているときは、乗り直せば切り替わることを伝える。
  /// 結果を見ている人に「乗ってください」と出すと、測れていなかったように読める。
  func cardLine(waitingForNext: Bool) -> String? {
    if self == .waitingForStep, waitingForNext {
      return NSLocalizedString(
        "Step on again to see the next result", comment: "Scale import status")
    }
    return content.cardLine
  }

  /// 進み具合の3段。済んだか、いまか、まだかを `stepIndex` と比べて決める
  static var stepTitles: [String] {
    [
      NSLocalizedString("Scale step: find", comment: "Scale stage progress"),
      NSLocalizedString("Scale step: step on", comment: "Scale stage progress"),
      NSLocalizedString("Scale step: receive", comment: "Scale stage progress"),
    ]
  }
}
