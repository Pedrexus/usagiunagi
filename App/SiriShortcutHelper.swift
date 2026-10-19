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

import Foundation
import StudyCore
import StudyUI
import UIKit

@MainActor final class SiriShortcutHelper: NSObject {
  typealias ShortcutType = StudyActivity

  public static let shared = SiriShortcutHelper()

  func attachShortcutActivity(_ vc: UIViewController, type: ShortcutType) {
    vc.userActivity = newShortcutActivity(type: type)
    vc.userActivity?.becomeCurrent()
  }

  func newShortcutActivity(type: ShortcutType) -> NSUserActivity {
    let activity = NSUserActivity(activityType: type.rawValue)
    type.configure(activity)

    return activity
  }

}
