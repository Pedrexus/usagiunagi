import StudyCore
import StudyPersistence
import SwiftUI

struct DeveloperSettingsView: View {
  @Binding var endpoint: String
  let defaultEndpoint: String
  var studyArchive: StudyDiagnosticArchive? = nil
  var applyEndpoint: (@MainActor (String) throws -> Void)? = nil
  @State private var endpointError: String?
  let clearAvatarCache: @MainActor () async throws -> Void
  @State private var editingEndpoint = false
  @State private var draft = ""
  @State private var invalidEndpoint = false
  @State private var cacheCleared = false
  @State private var clearingCache = false
  @State private var cacheError: String?

  var body: some View {
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
          .sheet(isPresented: $editingEndpoint) {
            NavigationStack {
              Form {
                Section {
                  TextField("API base URL", text: $draft)
                    #if os(iOS)
                      .keyboardType(.URL).textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled().accessibilityIdentifier("developer.endpoint.draft")
                  Button("Reset to default", role: .destructive) {
                    editingEndpoint = false
                    saveEndpoint(defaultEndpoint)
                  }
                } footer: {
                  Text("Default: \(defaultEndpoint)")
                }
              }
              .navigationTitle("API base URL")
              .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                  Button("Cancel", role: .cancel) { editingEndpoint = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                  Button("Save") {
                    editingEndpoint = false
                    if let value = DeveloperEndpoint.normalized(draft, defaultURL: defaultEndpoint)
                    {
                      saveEndpoint(value)
                    } else {
                      invalidEndpoint = true
                    }
                  }
                }
              }
            }
            .presentationDetents([.medium, .large])
          }

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
    }
    .formStyle(.grouped)
    .navigationTitle("Developer options")
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
