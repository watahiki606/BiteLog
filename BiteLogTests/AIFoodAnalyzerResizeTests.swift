import Testing
import UIKit

@testable import BiteLog

struct AIFoodAnalyzerResizeTests {

  /// 指定したピクセル数の画像を作る。scale 3 はスクリーンショットのように、ポイントとピクセルが違う画像。
  private func makeImage(pixelWidth: CGFloat, pixelHeight: CGFloat, scale: CGFloat) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = scale
    let size = CGSize(width: pixelWidth / scale, height: pixelHeight / scale)
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
      UIColor.orange.setFill()
      context.fill(CGRect(origin: .zero, size: size))
    }
  }

  private func pixelSize(_ image: UIImage) -> (width: Int, height: Int) {
    (image.cgImage!.width, image.cgImage!.height)
  }

  @Test func カメラの写真は長辺が上限のピクセル数になる() {
    let photo = makeImage(pixelWidth: 4032, pixelHeight: 3024, scale: 1)

    let resized = AIFoodAnalyzer.resizedForUpload(photo, maxPixelSize: 1536)

    #expect(pixelSize(resized) == (1536, 1152))
  }

  @Test func 縦長の写真は高さを上限に合わせる() {
    let photo = makeImage(pixelWidth: 3024, pixelHeight: 4032, scale: 1)

    let resized = AIFoodAnalyzer.resizedForUpload(photo, maxPixelSize: 1536)

    #expect(pixelSize(resized) == (1152, 1536))
  }

  @Test func 倍率付きの画像もピクセル数で上限に収める() {
    let screenshot = makeImage(pixelWidth: 3000, pixelHeight: 3000, scale: 3)

    let resized = AIFoodAnalyzer.resizedForUpload(screenshot, maxPixelSize: 1536)

    #expect(pixelSize(resized) == (1536, 1536))
  }

  @Test func 上限より小さい画像はそのまま送る() {
    let small = makeImage(pixelWidth: 800, pixelHeight: 600, scale: 1)

    let resized = AIFoodAnalyzer.resizedForUpload(small, maxPixelSize: 1536)

    #expect(pixelSize(resized) == (800, 600))
  }
}
