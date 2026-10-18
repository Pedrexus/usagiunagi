// Copyright David Sansome
// Licensed under the Apache License, Version 2.0. See LICENSE for terms.

import SwiftUI
import WaniKaniAPI

struct LessonSettings: View {
  @ArchivedPreference(Settings.$lessonBatchSize) private var batchSize: Int
  @ArchivedPreference(Settings.$apprenticeLessonsLimit) private var apprenticeLimit: Int
  @State private var order = Settings.lessonOrder

  var body: some View {
    Form {
      Section {
        NavigationLink {
          List {
            ForEach(order, id: \.rawValue) { Text($0.description) }
              .onMove { source, destination in
                order.move(fromOffsets: source, toOffset: destination)
                Settings.lessonOrder = order
              }
          }
          .environment(\.editMode, .constant(.active))
          .navigationTitle("Lesson order")
          .accessibilityIdentifier("settings.lessonOrder")
        } label: {
          LabeledContent("Order", value: order.map(\.description).joined(separator: ", "))
        }.accessibilityIdentifier("settings.lessonOrderLink")
        Picker("Batch size", selection: $batchSize) {
          ForEach(1...10, id: \.self) { Text($0 == 1 ? "1 lesson" : "\($0) lessons").tag($0) }
        }.accessibilityIdentifier("settings.lessonBatchSize")
        SettingToggle(
          "Prioritize current level", Settings.$prioritizeCurrentLevel,
          help: "Teach items from the current level first")
        Picker("Apprentice limit", selection: $apprenticeLimit) {
          Text("No limit").tag(Int.max)
          ForEach(Array(stride(from: 25, through: 200, by: 25)), id: \.self) {
            Text($0.formatted()).tag($0)
          }
        }.accessibilityIdentifier("settings.apprenticeLessonsLimit")
      } header: {
        Text("Lessons")
      } footer: {
        Text(
          "The batch size controls how many new items are introduced before a quiz. The apprentice limit stops new lessons when you have more than that many Apprentice items."
        )
      }
      Section("Vocabulary") {
        SettingToggle(
          "Show kana-only vocabulary", Settings.$showKanaOnlyVocab,
          help: "Include lessons for vocabulary written only in kana")
        SettingToggle(
          "Allow excluding vocabulary items", Settings.$allowExcludeItems,
          help: "Show the option to exclude vocabulary from lessons and reviews")
      }
    }.navigationTitle("Lessons")
      .onAppear { order = Settings.lessonOrder }
  }
}
