import Foundation
import Testing

@testable import BiteLog

/// 体重計から受け取った測定を、サーバーの17列に合わせる変換。
struct BodyMeasurementCreateDTOTests {

  private static let jst = TimeZone(identifier: "Asia/Tokyo")!

  private static func measurement(
    at date: Date?, weightKg: Double? = 60.0, bodyFatPercent: Double? = 20.0
  ) -> TanitaBodyMeasurement {
    var measurement = TanitaBodyMeasurement()
    measurement.measuredAt = date
    measurement.weightKg = weightKg
    measurement.bodyFatPercent = bodyFatPercent
    return measurement
  }

  /// 2026-01-01 07:30:41 JST
  private static let withSeconds = Date(timeIntervalSince1970: 1_767_220_241)

  @Test func 計測時刻が無ければ作らない() {
    // 時刻が無いと同じ測定かどうかを判定できないので送らない
    #expect(BodyMeasurementCreateDTO(Self.measurement(at: nil), timeZone: Self.jst) == nil)
  }

  @Test func 計測時刻は秒を切り捨てて送る() throws {
    let dto = try #require(
      BodyMeasurementCreateDTO(Self.measurement(at: Self.withSeconds), timeZone: Self.jst))

    // HealthPlanet のページから取り込む経路は分までしか持たない。
    // 秒を残すと同じ測定が別の行として二重に入る
    #expect(dto.measuredAt == "2025-12-31T22:30:00.000Z")
  }

  @Test func 日付は計測した地域の暦日で送る() throws {
    let dto = try #require(
      BodyMeasurementCreateDTO(Self.measurement(at: Self.withSeconds), timeZone: Self.jst))

    // UTC では前日になる時刻でも、測定したのは日本の1月1日
    #expect(dto.sourceDate == "2026-01-01")
  }

  @Test func 入力経路が分かるようにする() throws {
    let dto = try #require(
      BodyMeasurementCreateDTO(Self.measurement(at: Self.withSeconds), timeZone: Self.jst))

    #expect(dto.inputMethod == "体組成計から直接")
  }

  @Test func 受け取った項目の数を数える() throws {
    var full = Self.measurement(at: Self.withSeconds)
    full.muscleMassKg = 45.0
    full.muscleScore = -1
    full.visceralFatLevel = 5.0
    full.basalMetabolismKcal = 1400
    full.metabolicAge = 30
    full.boneMassKg = 2.5
    full.bodyWaterPercent = 55.0

    let dto = try #require(BodyMeasurementCreateDTO(full, timeZone: Self.jst))

    #expect(dto.itemCount == 9)
    #expect(dto.muscleScore == -1)
    #expect(dto.basalMetabolismKcal == 1400)
    #expect(dto.metabolicAge == 30)
  }

  @Test func 取れなかった項目は数えない() throws {
    let dto = try #require(
      BodyMeasurementCreateDTO(
        Self.measurement(at: Self.withSeconds, bodyFatPercent: nil), timeZone: Self.jst))

    #expect(dto.itemCount == 1)
    #expect(dto.weightKg == 60.0)
    #expect(dto.bodyFatPercent == nil)
  }
}
