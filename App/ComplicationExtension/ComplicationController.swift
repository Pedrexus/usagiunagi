// Copyright David Sansome
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import ClockKit

final class ComplicationController: NSObject, CLKComplicationDataSource {
  let tsurukameHighlightColor = UIColor.red
  // Ignore next review dates father in the future. We show the durations in
  // hours and these large values look incorrect.
  let farFutureReviewDate = TimeInterval(60 * 60 * 24)

  // MARK: - Timeline Configuration

  func getSupportedTimeTravelDirections(
    for _: CLKComplication,
    withHandler handler:
      @escaping (CLKComplicationTimeTravelDirections)
      -> Void
  ) {
    handler([.forward])
  }

  func getTimelineStartDate(
    for _: CLKComplication,
    withHandler handler: @escaping (Date?) -> Void
  ) {
    handler(nil)
  }

  func getTimelineEndDate(for _: CLKComplication, withHandler handler: @escaping (Date?) -> Void) {
    let data = WatchCompanionCache.sharedInstance.latestData
    if let expiry = WatchCompanionCache.status(for: data).staleAfter {
      handler(expiry)
    } else if let sent = data?[WatchHelper.keySentAt] as? EpochTimeInt,
      let hours = data?[WatchHelper.keyReviewUpcomingHourlyCounts] as? [Int]
    {
      handler(Date(timeIntervalSince1970: TimeInterval(sent) + Double(min(24, hours.count)) * 3600))
    } else {
      handler(nil)
    }
  }

  func getPrivacyBehavior(
    for _: CLKComplication,
    withHandler handler: @escaping (CLKComplicationPrivacyBehavior) -> Void
  ) {
    handler(.showOnLockScreen)
  }

  // MARK: - Timeline Population

  func getCurrentTimelineEntry(
    for complication: CLKComplication,
    withHandler handler:
      @escaping (CLKComplicationTimelineEntry?)
      -> Void
  ) {
    guard let data = WatchCompanionCache.sharedInstance.latestData else {
      handler(staleTimelineEntry(complication: complication, at: Date()))
      return
    }
    let status = WatchCompanionCache.status(for: data)
    if status.isStale(at: Date()), let expiry = status.staleAfter {
      handler(staleTimelineEntry(complication: complication, at: expiry))
      return
    }

    if let template = templateFor(
      complication,
      userData: data,
      dataSource: WatchCompanionCache.sharedInstance.dataSource)
    {
      let date = Date()
      let entry = CLKComplicationTimelineEntry(date: date, complicationTemplate: template)
      handler(entry)
    } else {
      handler(nil)
    }
  }

  func getTimelineEntries(
    for _: CLKComplication, before _: Date, limit _: Int,
    withHandler handler:
      @escaping ([CLKComplicationTimelineEntry]?)
      -> Void
  ) {
    // Don't provide any timeline entries in the past
    handler(nil)
  }

  func getTimelineEntries(
    for complication: CLKComplication, after: Date, limit: Int,
    withHandler handler: @escaping ([CLKComplicationTimelineEntry]?) -> Void
  ) {
    guard limit > 0 else {
      handler([])
      return
    }
    let data = WatchCompanionCache.sharedInstance.latestData
    let expiry = WatchCompanionCache.status(for: data).staleAfter
    var entries: [CLKComplicationTimelineEntry] = []
    if WatchCompanionCache.sharedInstance.dataSource == .reviews,
      let data, let sent = data[WatchHelper.keySentAt] as? EpochTimeInt,
      let hours = data[WatchHelper.keyReviewUpcomingHourlyCounts] as? [Int], !hours.isEmpty
    {
      for offset in 0...min(24, hours.count) {
        let date = Date(timeIntervalSince1970: TimeInterval(sent) + Double(offset) * 3600)
        guard date > after else { continue }
        if let expiry, date >= expiry { break }
        if let template = templateForReviewCount(complication, userData: data, offset: offset) {
          entries.append(CLKComplicationTimelineEntry(date: date, complicationTemplate: template))
        }
        if entries.count == limit { break }
      }
    }
    if entries.count < limit, let expiry, expiry > after,
      let stale = staleTimelineEntry(complication: complication, at: expiry)
    {
      entries.append(stale)
    }
    handler(entries)
  }

  func staleTimelineEntry(complication: CLKComplication, at expiry: Date)
    -> CLKComplicationTimelineEntry?
  {
    templateForStaleData(complication).map {
      CLKComplicationTimelineEntry(date: expiry, complicationTemplate: $0)
    }
  }

  // MARK: - Placeholder Templates

  func getLocalizableSampleTemplate(
    for complication: CLKComplication,
    withHandler handler:
      @escaping (CLKComplicationTemplate?)
      -> Void
  ) {
    // This method will be called once per supported complication, and the results will be cached
    let template = templateFor(
      complication,
      userData: WatchCompanionCache.sharedInstance.latestData ?? [
        WatchHelper.keyReviewCount: 8,
        WatchHelper.keyReviewNextHourCount: 3,
        WatchHelper.keyReviewUpcomingHourlyCounts: [
          3, 0, 0, 0, 4, 0, 0, 4,
          1, 0, 1, 1, 1, 0, 4, 4,
          0, 0, 0, 0, 0, 0, 0,
          0,
        ],
        WatchHelper.keyLevelCurrent: 6,
        WatchHelper.keyLevelTotal: 80,
        WatchHelper.keyLevelLearned: 12,
        WatchHelper.keyLevelHalf: false,
        WatchHelper.keyNextReviewAt: Date()
          .addingTimeInterval(TimeInterval(300)).timeIntervalSince1970,
      ],
      dataSource: WatchCompanionCache.sharedInstance.dataSource)
    handler(template)
  }

  // MARK: - Internal helpers

  func templateFor(
    _ complication: CLKComplication, userData: UserData?,
    dataSource: ComplicationDataSource
  ) -> CLKComplicationTemplate? {
    switch dataSource {
    case .reviews:
      return templateForReviewCount(complication, userData: userData)
    case .level:
      return templateForLevel(complication, userData: userData)
    case .legacyCharacter:
      return templateForStaleData(complication)
    }
  }

  func templateForReviewCount(
    _ complication: CLKComplication, userData: UserData?,
    offset: Int? = nil
  ) -> CLKComplicationTemplate? {
    let referenceDate: Date
    if let offset, let sent = userData?[WatchHelper.keySentAt] as? EpochTimeInt {
      referenceDate = Date(timeIntervalSince1970: TimeInterval(sent) + Double(offset) * 3600)
    } else {
      referenceDate = Date()
    }
    var reviewsPending = 0
    var nextHour = 0
    var nextReview: Date?
    if let data = userData {
      if let reviewCount = data[WatchHelper.keyReviewCount] as? Int {
        reviewsPending = reviewCount
      }
      if let nextHourCount = data[WatchHelper.keyReviewNextHourCount] as? Int {
        nextHour = nextHourCount
      }
      if let nextReviewAt = data[WatchHelper.keyNextReviewAt] as? EpochTimeInt, nextReviewAt > 0 {
        nextReview = Date(timeIntervalSince1970: TimeInterval(nextReviewAt))
        if let nr = nextReview,
          nr <= referenceDate || nr > referenceDate.addingTimeInterval(farFutureReviewDate)
        {
          nextReview = nil
        }
      }

      if let hours = data[WatchHelper.keyReviewUpcomingHourlyCounts] as? [Int] {
        let elapsed =
          (data[WatchHelper.keySentAt] as? EpochTimeInt).map {
            max(0, referenceDate.timeIntervalSince1970 - TimeInterval($0)) / 3600
          } ?? 0
        let horizon = min(24, hours.count)
        let hour = min(max(0, offset ?? Int(min(elapsed, Double(horizon)))), horizon)
        // Buckets are independent: retain current due work and accumulate completed hours.
        reviewsPending += hours.prefix(hour).reduce(0, +)
        nextHour = hour < horizon ? hours[hour] : 0
      }
    }

    switch complication.family {
    case .circularSmall:
      let template = CLKComplicationTemplateCircularSmallSimpleText()
      template.textProvider = CLKTextProvider(format: "%d", reviewsPending)
      return template
    case .extraLarge:
      let template = CLKComplicationTemplateExtraLargeStackText()
      template.line1TextProvider = CLKTextProvider(format: "REVIEWS")
      template.line2TextProvider = CLKTextProvider(format: "%d", reviewsPending)
      return template
    case .modularSmall:
      if reviewsPending > 0 {
        let template = CLKComplicationTemplateModularSmallStackText()
        template.line1TextProvider = CLKSimpleTextProvider(text: "now")
        template.line2TextProvider = CLKTextProvider(format: "%d", reviewsPending)
        if reviewsPending > 10 {
          template.highlightLine2 = true
        }
        return template
      } else if nextHour > 0 || nextReview == nil {
        let template = CLKComplicationTemplateModularSmallStackText()
        template.line1TextProvider = CLKSimpleTextProvider(text: "next")
        template.line2TextProvider = CLKTextProvider(format: "%d", nextHour)
        return template
      } else {
        let template = CLKComplicationTemplateModularSmallStackText()
        template.line1TextProvider = CLKSimpleTextProvider(text: "next")
        template.line2TextProvider = relativeDateProvider(date: nextReview!)
        return template
      }
    case .modularLarge:
      let template = CLKComplicationTemplateModularLargeTable()
      if let img = UIImage(named: "miniCrab") {
        template.headerImageProvider = CLKImageProvider(onePieceImage: img)
      }
      template.headerTextProvider = CLKSimpleTextProvider(text: "Reviews")
      template.row1Column1TextProvider = CLKTextProvider(format: "%d", reviewsPending)
      template.row1Column2TextProvider = CLKSimpleTextProvider(text: "now")
      if nextHour > 0 || nextReview == nil {
        template.row2Column1TextProvider = CLKTextProvider(format: "%d", nextHour)
        template.row2Column2TextProvider = CLKSimpleTextProvider(text: "next hour")
      } else {
        template.row2Column1TextProvider = relativeDateProvider(date: nextReview!)
        template.row2Column2TextProvider = CLKSimpleTextProvider(text: "until next")
      }
      return template
    case .utilitarianSmall, .utilitarianSmallFlat:
      let template = CLKComplicationTemplateUtilitarianSmallFlat()
      template.textProvider = CLKTextProvider(format: "NOW %d", reviewsPending)
      return template
    case .utilitarianLarge:
      let template = CLKComplicationTemplateUtilitarianLargeFlat()
      if reviewsPending == 1 {
        template.textProvider = CLKTextProvider(format: "%d REVIEW", reviewsPending)
      } else {
        template.textProvider = CLKTextProvider(format: "%d REVIEWS", reviewsPending)
      }
      return template
    case .graphicCorner:
      let template = CLKComplicationTemplateGraphicCornerStackText()
      template.outerTextProvider = CLKTextProvider(format: "%d NOW", reviewsPending)
      if nextHour > 0 || nextReview == nil {
        template.innerTextProvider = CLKTextProvider(format: "%d next hour", nextHour)
      } else {
        template
          .innerTextProvider = CLKTextProvider(
            format: "%@ until next",
            relativeDateProvider(date: nextReview!))
      }
      return template
    case .graphicCircular:
      if reviewsPending > 0 {
        let template = CLKComplicationTemplateGraphicCircularStackImage()
        template.line2TextProvider = CLKTextProvider(format: "%d", reviewsPending)
        if let img = UIImage(named: "miniCrab") {
          template.line1ImageProvider = CLKFullColorImageProvider(fullColorImage: img)
        }
        return template
      } else if nextHour > 0 || nextReview == nil {
        let template = CLKComplicationTemplateGraphicCircularStackText()
        template.line1TextProvider = CLKSimpleTextProvider(text: "next")
        template.line2TextProvider = CLKTextProvider(format: "%d", nextHour)
        return template
      } else {
        let template = CLKComplicationTemplateGraphicCircularStackText()
        template.line1TextProvider = CLKSimpleTextProvider(text: "next")
        template.line2TextProvider = relativeDateProvider(date: nextReview!)
        return template
      }
    case .graphicBezel:
      let template = CLKComplicationTemplateGraphicBezelCircularText()
      if let img = UIImage(named: "miniCrab") {
        let circularTemplate = CLKComplicationTemplateGraphicCircularImage()
        circularTemplate.imageProvider = CLKFullColorImageProvider(fullColorImage: img)
        template.circularTemplate = circularTemplate
      } else {
        let circularTemplate = CLKComplicationTemplateGraphicCircularStackText()
        circularTemplate.line1TextProvider = CLKSimpleTextProvider(text: "")
        circularTemplate.line2TextProvider = CLKSimpleTextProvider(text: "")
        template.circularTemplate = circularTemplate
      }
      if nextHour > 0 || nextReview == nil {
        template
          .textProvider = CLKTextProvider(format: "%d NOW • %d next hour", reviewsPending, nextHour)
      } else {
        template.textProvider = relativeDateProvider(date: nextReview!)
      }
      return template
    case .graphicRectangular:
      let template = CLKComplicationTemplateGraphicRectangularStandardBody()
      template.headerTextProvider = CLKTextProvider(format: "Reviews")
      template.body1TextProvider = CLKTextProvider(format: "%d now", reviewsPending)
      if nextHour > 0 || nextReview == nil {
        template.body2TextProvider = CLKTextProvider(format: "%d next hour", nextHour)
      } else {
        template
          .body2TextProvider = CLKTextProvider(
            format: "%@ until next",
            relativeDateProvider(date: nextReview!))
      }

      if let img = UIImage(named: "miniCrab") {
        template.headerImageProvider = CLKFullColorImageProvider(fullColorImage: img)
      }
      return template
    case .graphicExtraLarge:
      return nil
    @unknown default:
      return nil
    }
  }

  func templateForLevel(
    _ complication: CLKComplication,
    userData: UserData?
  ) -> CLKComplicationTemplate? {
    let currentLevel = userData?[WatchHelper.keyLevelCurrent] as? Int ?? 0
    let learned = userData?[WatchHelper.keyLevelLearned] as? Int ?? 0
    let total = userData?[WatchHelper.keyLevelTotal] as? Int ?? 0
    let halfLevel = userData?[WatchHelper.keyLevelHalf] as? Bool ?? false
    let fillFraction: Float = total > 0 ? min(1, max(0, Float(learned) / Float(total))) : 0

    let levelTextProvider: CLKTextProvider
    let levelShortTextProvider: CLKTextProvider
    if halfLevel {
      levelTextProvider = CLKTextProvider(format: "Level %.1f", Float(currentLevel) + 0.5)
      levelShortTextProvider = CLKTextProvider(format: "%.1f", Float(currentLevel) + 0.5)
    } else {
      levelTextProvider = CLKTextProvider(format: "Level %d", currentLevel)
      levelShortTextProvider = CLKTextProvider(format: "%d", currentLevel)
    }

    switch complication.family {
    case .circularSmall:
      let template = CLKComplicationTemplateCircularSmallRingText()
      template.textProvider = levelShortTextProvider
      template.ringStyle = .closed
      template.fillFraction = fillFraction
      return template
    case .extraLarge:
      let template = CLKComplicationTemplateExtraLargeRingText()
      template.textProvider = levelShortTextProvider
      template.fillFraction = fillFraction
      template.ringStyle = .closed
      return template
    case .modularSmall:
      let template = CLKComplicationTemplateModularSmallStackImage()
      template.line2TextProvider = levelShortTextProvider
      if let img = UIImage(named: "miniCrab") {
        template.line1ImageProvider = CLKImageProvider(onePieceImage: img)
      }
      return template
    case .modularLarge:
      let template = CLKComplicationTemplateModularLargeTable()
      if let img = UIImage(named: "miniCrab") {
        template.headerImageProvider = CLKImageProvider(onePieceImage: img)
      }
      template.headerTextProvider = levelTextProvider
      template.row1Column1TextProvider = CLKTextProvider(format: "%d", learned)
      template.row1Column2TextProvider = CLKSimpleTextProvider(text: "learned")
      template.row2Column1TextProvider = CLKTextProvider(format: "%d", total - learned)
      template.row2Column2TextProvider = CLKSimpleTextProvider(text: "remaining")
      return template
    case .utilitarianSmall, .utilitarianSmallFlat:
      let template = CLKComplicationTemplateUtilitarianSmallFlat()
      template.textProvider = levelShortTextProvider
      if let img = UIImage(named: "miniCrab") {
        template.imageProvider = CLKImageProvider(onePieceImage: img)
        template.imageProvider?.tintColor = tsurukameHighlightColor
      }
      return template
    case .utilitarianLarge:
      let template = CLKComplicationTemplateUtilitarianLargeFlat()
      if fillFraction > 0.8 {
        template
          .textProvider = CLKTextProvider(
            format: "%@ • %d left", levelTextProvider,
            total - learned)
      } else {
        template
          .textProvider = CLKTextProvider(format: "%@ • %d/%d", levelTextProvider, learned, total)
      }
      return template
    case .graphicCorner:
      let template = CLKComplicationTemplateGraphicCornerGaugeText()
      template.outerTextProvider = levelShortTextProvider
      template
        .gaugeProvider = CLKSimpleGaugeProvider(
          style: .fill, gaugeColor: tsurukameHighlightColor,
          fillFraction: fillFraction)
      template.trailingTextProvider = CLKTextProvider(format: "→%d", total - learned)
      return template
    case .graphicCircular:
      let template = CLKComplicationTemplateGraphicCircularOpenGaugeRangeText()
      template.centerTextProvider = CLKTextProvider(format: "%d", learned)
      template
        .gaugeProvider = CLKSimpleGaugeProvider(
          style: .ring, gaugeColor: tsurukameHighlightColor,
          fillFraction: fillFraction)
      template.leadingTextProvider = CLKSimpleTextProvider(text: "0")
      template.trailingTextProvider = CLKTextProvider(format: "%d", total)
      return template
    case .graphicBezel:
      let circleTemplate = CLKComplicationTemplateGraphicCircularOpenGaugeRangeText()
      circleTemplate.centerTextProvider = CLKTextProvider(format: "%d", learned)
      circleTemplate
        .gaugeProvider = CLKSimpleGaugeProvider(
          style: .ring, gaugeColor: tsurukameHighlightColor,
          fillFraction: fillFraction)
      circleTemplate.leadingTextProvider = CLKSimpleTextProvider(text: "0")
      circleTemplate.trailingTextProvider = CLKTextProvider(format: "%d", total)
      let template = CLKComplicationTemplateGraphicBezelCircularText()
      template
        .textProvider = CLKTextProvider(
          format: "%@ • %.0f%% complete", levelTextProvider,
          (Float(learned) / Float(total)) * 100.0)
      template.circularTemplate = circleTemplate
      return template
    case .graphicRectangular:
      let template = CLKComplicationTemplateGraphicRectangularTextGauge()
      template.headerTextProvider = levelTextProvider
      template.body1TextProvider = CLKTextProvider(format: "%d of %d learned", learned, total)
      if let img = UIImage(named: "miniCrab") {
        template.headerImageProvider = CLKFullColorImageProvider(fullColorImage: img)
      }
      template
        .gaugeProvider = CLKSimpleGaugeProvider(
          style: .fill, gaugeColor: tsurukameHighlightColor,
          fillFraction: fillFraction)
      return template
    default:
      return nil
    }
  }

  func templateForStaleData(_ complication: CLKComplication) -> CLKComplicationTemplate? {
    let dashTextProvider = CLKSimpleTextProvider(text: "-")

    switch complication.family {
    case .circularSmall:
      let template = CLKComplicationTemplateCircularSmallSimpleText()
      template.textProvider = dashTextProvider
      return template
    case .extraLarge:
      let template = CLKComplicationTemplateExtraLargeStackText()
      template.line1TextProvider = CLKTextProvider(format: "REVIEWS")
      template.line2TextProvider = CLKSimpleTextProvider(text: "unknown")
      return template
    case .modularSmall:
      let template = CLKComplicationTemplateModularSmallStackText()
      template.line1TextProvider = CLKSimpleTextProvider(text: "now")
      template.line2TextProvider = dashTextProvider
      return template
    case .modularLarge:
      let template = CLKComplicationTemplateModularLargeTable()
      if let img = UIImage(named: "miniCrab") {
        template.headerImageProvider = CLKImageProvider(onePieceImage: img)
      }
      template.headerTextProvider = CLKSimpleTextProvider(text: "Reviews")
      template.row1Column1TextProvider = dashTextProvider
      template.row1Column2TextProvider = CLKSimpleTextProvider(text: "now")
      template.row2Column1TextProvider = dashTextProvider
      template.row2Column2TextProvider = CLKSimpleTextProvider(text: "next hour")
      return template
    case .utilitarianSmall, .utilitarianSmallFlat:
      let template = CLKComplicationTemplateUtilitarianSmallFlat()
      if let img = UIImage(named: "miniCrab") {
        template.imageProvider = CLKImageProvider(onePieceImage: img)
      }
      template.textProvider = dashTextProvider
      return template
    case .utilitarianLarge:
      let template = CLKComplicationTemplateUtilitarianLargeFlat()
      template.textProvider = CLKSimpleTextProvider(text: "data stale")
      return template
    case .graphicCorner:
      let template = CLKComplicationTemplateGraphicCornerStackText()
      template.outerTextProvider = CLKSimpleTextProvider(text: "stale")
      template.innerTextProvider = CLKSimpleTextProvider(text: "open phone app")
      return template
    case .graphicCircular:
      let template = CLKComplicationTemplateGraphicCircularStackText()
      template.line1TextProvider = CLKSimpleTextProvider(text: "next")
      template.line2TextProvider = dashTextProvider
      return template
    case .graphicBezel:
      let template = CLKComplicationTemplateGraphicBezelCircularText()
      if let img = UIImage(named: "miniCrab") {
        let circularTemplate = CLKComplicationTemplateGraphicCircularImage()
        circularTemplate.imageProvider = CLKFullColorImageProvider(fullColorImage: img)
        template.circularTemplate = circularTemplate
      } else {
        let circularTemplate = CLKComplicationTemplateGraphicCircularStackText()
        circularTemplate.line1TextProvider = CLKSimpleTextProvider(text: "")
        circularTemplate.line2TextProvider = CLKSimpleTextProvider(text: "")
        template.circularTemplate = circularTemplate
      }
      template.textProvider = dashTextProvider
      return template
    case .graphicRectangular:
      let template = CLKComplicationTemplateGraphicRectangularStandardBody()
      template.headerTextProvider = CLKTextProvider(format: "Reviews")
      template.body1TextProvider = dashTextProvider
      template.body2TextProvider = dashTextProvider

      if let img = UIImage(named: "miniCrab") {
        template.headerImageProvider = CLKFullColorImageProvider(fullColorImage: img)
      }
      return template
    case .graphicExtraLarge:
      return nil
    @unknown default:
      return nil
    }
  }

  func relativeDateProvider(date: Date) -> CLKRelativeDateTextProvider {
    // Always use hour because the complication cache does not call often enough
    // to vary this unit.
    CLKRelativeDateTextProvider(date: date, style: .offsetShort, units: .hour)
  }

}
