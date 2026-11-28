import SwiftUI

/// 体組成計で測っている間、シートの中央に出す今の段階。
///
/// 大きな丸い印と見出しで、乗るのか、乗ったまま待つのか、降りてよいのかがひと目で分かる。
/// 乗ったあとも測り終わるまで体重計は応答しないので、乗ったあとは「乗ったまま待つ」と伝える。
struct ScaleStageView: View {
  let stage: MeasurementStage
  /// 失敗の文面。失敗以外では使わない
  var failureMessage: String?
  let onStop: () -> Void
  let onRetry: () -> Void
  let onClose: () -> Void

  var body: some View {
    // 大きな文字で中身がシートより高くなっても、スクロールで届くようにする。
    // 収まるときは動かさず、シートの高さいっぱいに中央そろえで広げる
    GeometryReader { proxy in
      ScrollView {
        ScaleStageContent(
          stage: stage, failureMessage: failureMessage,
          onStop: onStop, onRetry: onRetry, onClose: onClose
        )
        .frame(minHeight: proxy.size.height)
      }
      .scrollBounceBehavior(.basedOnSize)
    }
    // 段階が変わったら見出しを読ませる。画面を見ていない人にも乗るタイミングが伝わる
    .onChange(of: stage, initial: true) { _, stage in
      AccessibilityNotification.Announcement(stage.content.title).post()
    }
  }
}

/// 段階の中身。縦に中央そろえで、印、見出し、補足、進み具合、ボタンの順に並べる。
///
/// スクロールと読み上げは `ScaleStageView` が持つ。`ImageRenderer` は `ScrollView` を
/// 描けないので、描画ギャラリーはこちらを直接描く。
struct ScaleStageContent: View {
  let stage: MeasurementStage
  var failureMessage: String?
  let onStop: () -> Void
  let onRetry: () -> Void
  let onClose: () -> Void

  var body: some View {
    VStack(spacing: 28) {
      Spacer(minLength: 0)

      ScaleStageBadge(stage: stage)

      VStack(spacing: 10) {
        Text(stage.content.title)
          .font(.title2.bold())
          .accessibilityAddTraits(.isHeader)
        if let detail = stage == .failed ? failureMessage : stage.content.detail {
          Text(detail)
            .font(.body)
            .foregroundStyle(.secondary)
        }
      }
      .multilineTextAlignment(.center)
      // 大きな文字で行が切られないよう、必要な高さを主張する
      .fixedSize(horizontal: false, vertical: true)

      if let step = stage.content.stepIndex {
        ScaleStageProgress(current: step)
      }

      Spacer(minLength: 0)

      actions
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 24)
    .frame(maxWidth: .infinity)
  }

  @ViewBuilder
  private var actions: some View {
    if stage == .failed {
      VStack(spacing: 8) {
        Button(action: onRetry) {
          Text(NSLocalizedString("Measure again", comment: "Body composition card button"))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)

        Button(NSLocalizedString("Close", comment: "Close button"), action: onClose)
          .controlSize(.large)
      }
    } else {
      Button(NSLocalizedString("Stop", comment: "Scale import button"), action: onStop)
        .controlSize(.large)
    }
  }
}

// MARK: - 丸い印

/// 段階を表す大きな丸い印。`NutrientRing` と同じく、色の薄い円の地、外周の輪、中央の絵でできている。
///
/// 動きは段階ごとに違う。探している間は輪の一部が回り、乗るのを待つ間は輪が脈を打つ。
/// 視差効果を減らす設定では、どちらも動かさない。
struct ScaleStageBadge: View {
  let stage: MeasurementStage

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorSchemeContrast) private var contrast

  /// 文字サイズには追随させるが、画面を埋めない範囲で頭打ちにする
  @ScaledMetric(relativeTo: .largeTitle) private var scaledSize: CGFloat = 120
  private var size: CGFloat { min(scaledSize, 160) }
  private var lineWidth: CGFloat { max(size * 0.06, 6) }

  /// 失敗の色は既存の失敗表示が使う赤に合わせる。それ以外はアクセントカラー
  private var color: Color { stage == .failed ? .red : .accentColor }

  @State private var rotation = 0.0
  @State private var isPulsing = false

  var body: some View {
    ZStack {
      Circle()
        .fill(color.opacity(contrast == .increased ? 0.3 : 0.15))

      Circle()
        .inset(by: lineWidth / 2)
        .stroke(color.opacity(contrast == .increased ? 0.35 : 0.2), lineWidth: lineWidth)

      ring

      Image(systemName: stage.content.symbol)
        .font(.system(size: size * 0.4, weight: .semibold))
        .foregroundStyle(color)
        .symbolEffect(
          .variableColor.iterative, options: .repeating,
          isActive: stage == .searching && !reduceMotion
        )
        .symbolEffect(
          .pulse, options: .repeating, isActive: stage == .waitingForStep && !reduceMotion)
    }
    .frame(width: size, height: size)
    // 段階が変わるたびに作り直し、動きを最初から始める
    .id(stage)
    .onAppear { startMotion() }
    .accessibilityHidden(true)
  }

  /// 外周の輪。探している間は一部だけの弧、それ以外は全周
  @ViewBuilder
  private var ring: some View {
    switch stage {
    case .searching:
      Circle()
        .inset(by: lineWidth / 2)
        .trim(from: 0, to: 0.28)
        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        .rotationEffect(.degrees(rotation - 90))
        .animation(
          reduceMotion ? nil : .linear(duration: 1.2).repeatForever(autoreverses: false),
          value: rotation)
    case .waitingForStep:
      Circle()
        .inset(by: lineWidth / 2)
        .stroke(color, lineWidth: lineWidth)
        .opacity(isPulsing ? 0.35 : 1)
        .animation(
          reduceMotion ? nil : .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
          value: isPulsing)
    case .reading, .failed:
      Circle()
        .inset(by: lineWidth / 2)
        .stroke(color, lineWidth: lineWidth)
    }
  }

  private func startMotion() {
    guard !reduceMotion else { return }
    switch stage {
    case .searching: rotation = 360
    case .waitingForStep: isPulsing = true
    case .reading, .failed: break
    }
  }
}

// MARK: - 進み具合

/// 「探す」「乗る」「受け取る」の3段。済んだ段には印を付け、いまの段を強く、まだの段は薄く出す。
struct ScaleStageProgress: View {
  /// いまの段。0から数える
  let current: Int

  private var titles: [String] { MeasurementStage.stepTitles }

  var body: some View {
    // 大きな文字では3つを横に並べると文字が折り返して読めなくなる
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .top, spacing: 20) { steps }
      VStack(alignment: .leading, spacing: 12) { steps }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      String(
        format: NSLocalizedString("Step %1$d of %2$d", comment: "Scale stage progress"),
        current + 1, titles.count)
    )
    .accessibilityValue(titles[current])
  }

  private var steps: some View {
    ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
      step(title: title, index: index)
    }
  }

  private func step(title: String, index: Int) -> some View {
    let isDone = index < current
    let isCurrent = index == current
    return HStack(spacing: 6) {
      Image(systemName: isDone ? "checkmark.circle.fill" : isCurrent ? "circle.inset.filled" : "circle")
        .foregroundStyle(isDone || isCurrent ? Color.accentColor : Color.secondary.opacity(0.5))
      Text(title)
        .font(.subheadline.weight(isCurrent ? .bold : .regular))
        .foregroundStyle(isCurrent ? Color.primary : Color.secondary.opacity(isDone ? 1 : 0.7))
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

// MARK: - 自動ロック

extension View {
  /// 測っている間、画面の自動ロックを止める。待っている間に暗くなると、
  /// いま何をすればよいかが見えなくなる。
  ///
  /// 画面が消えたら、測っていても必ず戻す。
  func keepsScreenAwake(_ active: Bool) -> some View {
    onChange(of: active, initial: true) { _, active in
      UIApplication.shared.isIdleTimerDisabled = active
    }
    .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
  }
}
