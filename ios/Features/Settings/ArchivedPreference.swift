// Copyright David Sansome
// Licensed under the Apache License, Version 2.0. See LICENSE for terms.

import SwiftUI

/// Temporary SwiftUI observation of existing archives; the original setting remains the writer.
@propertyWrapper struct ArchivedPreference<S: SettingProtocol>: DynamicProperty {
  private let setting: S
  @AppStorage private var archive: Data?
  @State private var revision = 0

  init(_ setting: S) {
    self.setting = setting
    _ = setting.wrappedValue
    _archive = AppStorage(setting.key)
  }
  var wrappedValue: S.ValueType {
    get {
      _ = archive
      _ = revision
      return setting.wrappedValue
    }
    nonmutating set {
      var saved = setting
      saved.wrappedValue = newValue
      // Volatile screenshot-fixture overrides also need to invalidate the local view.
      revision &+= 1
    }
  }
  var projectedValue: Binding<S.ValueType> {
    Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
  }
}

struct SettingToggle: View {
  let title: String
  let explanation: String?
  private let key: String
  @ArchivedPreference<Setting<Bool>> private var enabled: Bool

  init(_ title: String, _ setting: Setting<Bool>, help: String? = nil) {
    self.title = title
    self.explanation = help
    self.key = setting.key
    _enabled = ArchivedPreference(setting)
  }
  var body: some View {
    Toggle(isOn: $enabled) {
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
        if let explanation { Text(explanation).font(.caption).foregroundStyle(.secondary) }
      }
    }.accessibilityIdentifier("settings.\(key)")
  }
}

struct EnumSettingPicker<Value: SettingEnum & Hashable>: View {
  let title: String
  @Binding var selection: Value
  var body: some View {
    Picker(title, selection: $selection) {
      ForEach(Array(Value.allCases), id: \.self) { Text($0.description).tag($0) }
    }
  }
}
