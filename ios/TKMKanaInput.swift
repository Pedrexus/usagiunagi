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

import StudyCore
import UIKit

/// Native selection/composition bridge; all conversion rules live in shared Swift.
final class TKMKanaInput: NSObject, UITextFieldDelegate {
  private weak var delegate: UITextFieldDelegate?
  var enabled = false
  var alphabet: KanaAlphabet = .hiragana

  init(delegate: UITextFieldDelegate) {
    self.delegate = delegate
    super.init()
  }

  func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange,
                 replacementString string: String) -> Bool {
    if delegate?.textField?(textField, shouldChangeCharactersIn: range,
                            replacementString: string) == false { return false }
    guard enabled, textField.markedTextRange == nil,
          let edit = KanaConverter.edit(text: textField.text ?? "", range: range,
                                        replacement: string, alphabet: alphabet)
    else { return true }
    let selection = textField.selectedTextRange
    textField.text = edit.text
    textField.textAlignment = .center
    if let cursor = edit.cursor,
       let position = textField.position(from: textField.beginningOfDocument, offset: cursor) {
      textField.selectedTextRange = textField.textRange(from: position, to: position)
    } else {
      textField.selectedTextRange = selection
    }
    return edit.allowsSystemChange
  }

  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    delegate?.textFieldShouldReturn?(textField) ?? false
  }
}
