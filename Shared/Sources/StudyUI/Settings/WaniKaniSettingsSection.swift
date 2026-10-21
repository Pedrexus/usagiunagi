import StudyCore
import SwiftUI

extension EnvironmentValues {
  @Entry var waniKaniPreferences: WaniKaniPreferences? = nil
}

struct WaniKaniSettingsSection: View {
  @Bindable var model: StudyAppModel

  var body: some View {
    Section {
      if let value = model.effectiveWaniKaniPreferences {
        let values = Binding(
          get: { model.effectiveWaniKaniPreferences ?? value }, set: model.editWaniKaniPreferences)
        Group {
          Picker("Lessons per batch", selection: values.lessonsBatchSize) {
            ForEach(Array(Set(Array(1...10) + [value.lessonsBatchSize])).sorted(), id: \.self) {
              Text($0.formatted()).tag($0)
            }
          }
          Toggle("Autoplay lesson audio", isOn: values.lessonsAutoplayAudio)
          Picker("Review order", selection: values.reviewsPresentationOrder) {
            Text("Random").tag(WaniKaniPreferences.ReviewOrder.shuffled.rawValue)
            Text("Lowest level first").tag(
              WaniKaniPreferences.ReviewOrder.lowerLevelsFirst.rawValue)
            if value.reviewOrder == nil {
              Text("Other WaniKani order").tag(value.reviewsPresentationOrder)
            }
          }
          Toggle("Autoplay review audio", isOn: values.reviewsAutoplayAudio)
          Toggle("Show completed review SRS change", isOn: values.reviewsDisplaySrsIndicator)
          Toggle("Autoplay Extra Study audio", isOn: values.extraStudyAutoplayAudio)
        }.disabled(model.isLoadingWaniKaniPreferences)
      } else {
        Text(
          model.snapshot?.isSample == false
            ? "WaniKani settings aren't available yet. App settings remain available offline."
            : "Connect your WaniKani account to read or change its settings."
        )
        .foregroundStyle(.secondary)
      }
      if model.snapshot?.isSample == false {
        if model.isLoadingWaniKaniPreferences {
          HStack {
            ProgressView().controlSize(.small)
            Text("Syncing with WaniKani")
          }
        } else if !model.pendingWaniKaniPreferences.isEmpty {
          Label("Changes pending sync", systemImage: "clock")
        } else if model.waniKaniPreferencesNotice == nil, model.waniKaniPreferencesSavedAt != nil {
          Label("Synced with WaniKani", systemImage: "checkmark.circle")
        }
        if let notice = model.waniKaniPreferencesNotice {
          Text(notice).font(.caption).foregroundStyle(.secondary)
        }
        if model.waniKaniPreferencesNeedConfirmation || model.waniKaniPreferencesNotice != nil {
          if !model.pendingWaniKaniPreferences.isEmpty {
            Button("Retry sync", action: model.retryWaniKaniPreferencesSave)
              .disabled(model.isLoadingWaniKaniPreferences)
          }
          Button("Refresh from WaniKani") {
            Task { await model.refreshWaniKaniPreferences(force: true) }
          }.disabled(model.isLoadingWaniKaniPreferences)
        }
      }
    } header: {
      Text("WaniKani")
    } footer: {
      Text(
        "Changes sync automatically after a brief pause. These account settings also apply on WaniKani. App settings below can override audio, order and batch size."
      )
    }
  }
}
