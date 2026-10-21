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

/// Apple still calls this class to move an installed ClockKit face to WidgetKit.
final class ComplicationController: NSObject, CLKComplicationDataSource,
  CLKComplicationWidgetMigrator
{
  var widgetMigrator: any CLKComplicationWidgetMigrator { self }

  func getCurrentTimelineEntry(
    for _: CLKComplication,
    withHandler handler: @escaping (CLKComplicationTimelineEntry?) -> Void
  ) {
    handler(nil)
  }

  nonisolated func widgetConfiguration(from _: CLKComplicationDescriptor) async
    -> CLKComplicationWidgetMigrationConfiguration?
  {
    guard
      let identifier = Bundle.main.object(
        forInfoDictionaryKey: "UsagiUnagiWatchWidgetBundleIdentifier") as? String,
      !identifier.isEmpty
    else { return nil }
    guard await MainActor.run(body: { WatchHelper.reloadComplications() }) else { return nil }
    return CLKComplicationStaticWidgetMigrationConfiguration(
      kind: WatchCompanionCache.widgetKind, extensionBundleIdentifier: identifier)
  }
}
