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

// Optional practice entry points remain development-only until their release acceptance.
enum FeatureFlags {
  #if DEBUG
    static let showOtherPracticeModes = true
    static let showSubjectDeveloperOptions = true
  #else
    static let showOtherPracticeModes = false
    static let showSubjectDeveloperOptions = false
  #endif
}
