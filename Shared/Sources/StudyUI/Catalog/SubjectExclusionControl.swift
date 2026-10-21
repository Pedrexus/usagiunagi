import SwiftUI

/// Hosts supply their existing account-bound writer; this control never initiates a sync.
struct SubjectExclusionControl: View {
  @Binding var excluded: Bool
  var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 8) {
        Toggle("Exclude this item", isOn: $excluded).accessibilityIdentifier("subject.excluded")
        Text("Excluded items do not appear in new lessons or scheduled reviews.")
          .font(.caption).foregroundStyle(.secondary)
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
