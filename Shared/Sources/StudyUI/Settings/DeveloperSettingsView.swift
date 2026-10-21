import StudyCore
import StudyPersistence
import SwiftUI

public struct DeveloperSettingsView: View {
  @Binding var endpoint: String
  let defaultEndpoint: String
  let studyArchive: StudyDiagnosticArchive?
  let applyEndpoint: (@MainActor (String) throws -> Void)?
  @State private var endpointError: String?
  let clearAvatarCache: @MainActor () async throws -> Void
  @State private var editingEndpoint = false
  @State private var draft = ""
  @State private var invalidEndpoint = false
  @State private var cacheCleared = false
  @State private var clearingCache = false
  @State private var cacheError: String?

  public init(
    endpoint: Binding<String>, defaultEndpoint: String,
    studyArchive: StudyDiagnosticArchive? = nil,
    applyEndpoint: (@MainActor (String) throws -> Void)? = nil,
    clearAvatarCache: @escaping @MainActor () async throws -> Void
  ) {
    self._endpoint = endpoint
    self.defaultEndpoint = defaultEndpoint
    self.studyArchive = studyArchive
    self.applyEndpoint = applyEndpoint
    self.clearAvatarCache = clearAvatarCache
  }
  public var body: some View {
    Form {
      Section("WaniKani API") {
        Button {
          draft = endpoint
          invalidEndpoint = false
          editingEndpoint = true
        } label: {
          VStack(alignment: .leading, spacing: 4) {
            Text("API base URL").foregroundStyle(.primary)
            Text(endpoint).font(.caption).foregroundStyle(.secondary).lineLimit(2)
          }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("developer.endpoint")
        if invalidEndpoint {
          Text("Enter a valid http or https URL.").foregroundStyle(.red).accessibilityIdentifier(
            "developer.endpoint.error")
        }
      }
      Section {
        if let studyArchive {
          ShareLink(item: studyArchive, preview: SharePreview("Study diagnostics")) {
            Label("Export study diagnostics", systemImage: "square.and.arrow.up")
          }.accessibilityIdentifier("developer.export")
        }
        Button("Clear avatar image cache", systemImage: "person.crop.circle.badge.xmark") {
          clearingCache = true
          Task {
            defer { clearingCache = false }
            do {
              try await clearAvatarCache()
              cacheCleared = true
            } catch { cacheError = error.localizedDescription }
          }
        }.disabled(clearingCache).accessibilityIdentifier("developer.clearAvatarCache")
      } header: {
        Text("Diagnostics")
      } footer: {
        if studyArchive != nil {
          Text(
            "Share this account’s study diagnostics, including notes and pending work. This is not a restorable backup."
          )
        } else {
          Text("Connect to WaniKani to export saved study diagnostics.")
        }
      }
      if let studyArchive {
        Section {
          ShareLink(item: studyArchive.freeLevels, preview: SharePreview("Levels 1–3")) {
            Label("Export saved levels 1–3", systemImage: "square.and.arrow.up")
          }.accessibilityIdentifier("developer.exportFreeLevels")
        } header: {
          Text("Offline sample")
        } footer: {
          Text(
            "Shares saved subject content only. Your account, notes and study progress are excluded."
          )
        }
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Developer options")
    .alert("API base URL", isPresented: $editingEndpoint) {
      TextField("API base URL", text: $draft)
        #if os(iOS)
          .keyboardType(.URL).textInputAutocapitalization(.never)
        #endif
        .autocorrectionDisabled().accessibilityIdentifier("developer.endpoint.draft")
      Button("Save") {
        if let value = DeveloperEndpoint.normalized(draft, defaultURL: defaultEndpoint) {
          saveEndpoint(value)
        } else {
          invalidEndpoint = true
        }
      }
      Button("Reset to default", role: .destructive) { saveEndpoint(defaultEndpoint) }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("Default: \(defaultEndpoint)")
    }
    .alert(
      "Could not change API URL",
      isPresented: Binding(
        get: { endpointError != nil },
        set: { if !$0 { endpointError = nil } })
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(endpointError ?? "")
    }
    .alert("Image cache cleared", isPresented: $cacheCleared) { Button("OK", role: .cancel) {} }
    .alert(
      "Unable to clear image cache",
      isPresented: Binding(get: { cacheError != nil }, set: { if !$0 { cacheError = nil } })
    ) {
      Button("OK", role: .cancel) { cacheError = nil }
    } message: {
      Text(cacheError ?? "")
    }
  }
  private func saveEndpoint(_ value: String) {
    do {
      try applyEndpoint?(value)
      endpoint = value
    } catch { endpointError = error.localizedDescription }
  }

}
