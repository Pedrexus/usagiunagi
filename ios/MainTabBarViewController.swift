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
import UIKit

class MainTabBarViewController: UITabBarController {
  var services: TKMServices!
  weak var waniKaniTabDelegate: MainWaniKaniTabViewController.Delegate?
  weak var waniKaniViewController: MainWaniKaniTabViewController?

  func setup(services: TKMServices, waniKaniTabDelegate: MainWaniKaniTabViewController.Delegate?) {
    self.services = services
    self.waniKaniTabDelegate = waniKaniTabDelegate
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    tabBar.isHidden = false

    view.backgroundColor = .clear
    for vc in viewControllers! {
      switch vc {
      case let vc as MainWaniKaniTabViewController:
        vc.setup(services: services, delegate: waniKaniTabDelegate)
        waniKaniViewController = vc
        vc.tabBarItem = UITabBarItem(title: "Home", image: UIImage(systemName: "house"), tag: 0)

      case let vc as MainPracticeTabViewController:
        vc.setup(services: services)
        vc.tabBarItem = UITabBarItem(title: "Practice",
                                     image: UIImage(systemName: "square.and.pencil"), tag: 1)

      default:
        break
      }
    }
    var tabs = viewControllers ?? []
    if !FeatureFlags.showOtherPracticeModes {
      tabs.removeAll { $0 is MainPracticeTabViewController }
    }
    tabs.append(StatisticsViewController(services: services))
    setViewControllers(tabs, animated: false)
    #if DEBUG
      if ProcessInfo.processInfo.arguments
        .contains("ShowStatistics") { selectedIndex = tabs.count - 1 }
    #endif
  }

  func update() {
    waniKaniViewController?.update()
  }
}
