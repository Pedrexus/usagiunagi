import SwiftUI

/// Hosts supply their existing account-bound writer; this control never initiates a sync.
public struct SubjectExclusionControl: View {
  @Binding private var excluded: Bool
  public init(excluded: Binding<Bool>) { _excluded = excluded }
  public var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: 8) {
        Toggle("Exclude this item", isOn: $excluded).accessibilityIdentifier("subject.excluded")
        Text("Excluded items do not appear in new lessons or scheduled reviews.")
          .font(.caption).foregroundStyle(.secondary)
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
