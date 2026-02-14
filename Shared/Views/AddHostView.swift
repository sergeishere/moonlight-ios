import SwiftUI

struct AddHostView: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (String) -> Void

    @State private var hostAddress = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("IP Address or Hostname", text: $hostAddress)
                        #if !os(tvOS)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        #endif
                } footer: {
                    Text("Enter the IP address or hostname of your gaming PC.")
                }
            }
            .navigationTitle("Add Host")
            #if !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let address = hostAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !address.isEmpty {
                            onAdd(address)
                        }
                        dismiss()
                    }
                    .disabled(hostAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
