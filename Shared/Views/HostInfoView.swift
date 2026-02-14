import SwiftUI

struct HostInfoView: View {
    let host: Host
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("General") {
                    row("Name", host.name)
                    row("UUID", host.uuid)
                    row("MAC", host.mac ?? "Unknown")
                    row("Paired", host.isPaired ? "Yes" : "No")
                    row("Status", statusString)
                }

                Section("Addresses") {
                    row("Local", host.localAddress ?? "None")
                    row("External", host.externalAddress ?? "None")
                    row("IPv6", host.ipv6Address ?? "None")
                    row("Manual", host.address ?? "None")
                    row("Active", host.activeAddress ?? "None")
                }

                Section("Server") {
                    row("HTTPS Port", host.httpsPort > 0 ? "\(host.httpsPort)" : "N/A")
                    row("Codecs", codecString)
                }

                if host.serverCert != nil {
                    Section("Certificate") {
                        row("Server Cert", "\(host.serverCert?.count ?? 0) bytes")
                    }
                }
            }
            .navigationTitle("Host Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var statusString: String {
        if host.isOnline { return "Online" }
        if host.isStatusUnknown { return "Unknown" }
        return "Offline"
    }

    private var codecString: String {
        let mask = host.serverCodecModeSupport
        guard mask != 0 else { return "N/A" }

        var codecs: [String] = []
        if mask & 0x00001 != 0 { codecs.append("H.264") }
        if mask & 0x00100 != 0 { codecs.append("HEVC") }
        if mask & 0x00200 != 0 { codecs.append("HEVC HDR") }
        if mask & 0x10000 != 0 { codecs.append("AV1") }
        if mask & 0x20000 != 0 { codecs.append("AV1 HDR") }
        return codecs.isEmpty ? "Unknown" : codecs.joined(separator: ", ")
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
    }
}
