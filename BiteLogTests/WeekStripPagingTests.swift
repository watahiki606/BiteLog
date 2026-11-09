import Foundation
import Testing

@testable import BiteLog

struct WeekStripPagingTests {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    calendar.firstWeekday = 1
    return calendar
  }

  private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
  }

  @Test func 同じ週の日は同じページになる() {
    let sunday = WeekStripView.page(containing: day(2026, 11, 8), calendar: calendar)
    let saturday = WeekStripView.page(containing: day(2026, 11, 14, hour: 23), calendar: calendar)
    #expect(sunday == saturday)
  }

  @Test func 次の週は次のページになる() {
    let thisWeek = WeekStripView.page(containing: day(2026, 11, 14), calendar: calendar)
    let nextWeek = WeekStripView.page(containing: day(2026, 11, 15), calendar: calendar)
    #expect(nextWeek == thisWeek + 1)
  }

  @Test func 夏時間の切り替えをまたいでも1週ずつ進む() {
    // 2026-11-01 に米国東部の夏時間が終わり、その週だけ1時間長い
    let before = WeekStripView.page(containing: day(2026, 10, 31), calendar: calendar)
    let after = WeekStripView.page(containing: day(2026, 11, 1), calendar: calendar)
    #expect(after == before + 1)
  }

  @Test func ページの週の7日を返す() {
    let page = WeekStripView.page(containing: day(2026, 11, 11), calendar: calendar)
    let days = WeekStripView.days(onPage: page, calendar: calendar)
    #expect(days.first == day(2026, 11, 8))
    #expect(days.last == day(2026, 11, 14))
    #expect(days.count == 7)
  }

  @Test func 前の週へ移ると同じ曜日を選ぶ() {
    let selected = day(2026, 11, 11)
    let page = WeekStripView.page(containing: selected, calendar: calendar)
    let moved = WeekStripView.date(
      movingFrom: selected, toPage: page - 1, today: day(2026, 11, 12), calendar: calendar)
    #expect(moved == day(2026, 11, 4))
  }

  @Test func 今週へ戻ると同じ曜日が未来なら今日で止める() {
    let selected = day(2026, 11, 6)
    let page = WeekStripView.page(containing: selected, calendar: calendar)
    let moved = WeekStripView.date(
      movingFrom: selected, toPage: page + 1, today: day(2026, 11, 9), calendar: calendar)
    #expect(moved == day(2026, 11, 9))
  }

  @Test func 暦から遠い過去を選んでもその週のページが含まれる() {
    let today = day(2026, 11, 9)
    let distant = day(1990, 1, 10)
    let pages = WeekStripView.pages(selected: distant, today: today, calendar: calendar)
    #expect(pages.contains(WeekStripView.page(containing: distant, calendar: calendar)))
    #expect(pages.last == WeekStripView.page(containing: today, calendar: calendar))
  }

  @Test func 今週より先のページは作らない() {
    let today = day(2026, 11, 9)
    let pages = WeekStripView.pages(selected: today, today: today, calendar: calendar)
    #expect(!pages.contains(WeekStripView.page(containing: today, calendar: calendar) + 1))
  }
}
