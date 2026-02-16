import SwiftUI

struct HostCardView: View {
    let host: Host

    private var isActive: Bool { host.isOnline }

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: iconName)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 56))
                .foregroundStyle(iconColor)
            Text(host.name)
                .font(.title3.weight(.semibold))
                .foregroundStyle(isActive ? .primary : .tertiary)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.center)
            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(isActive ? .secondary : .tertiary)
                .frame(minHeight: 24)
            Spacer()
        }
        .padding(20)
        .frame(width: 195, height: 260)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 20))
        .hoverEffect()
        .overlay(alignment: .topTrailing) {
            if host.isPaired {
                Image(systemName: "personalhotspot")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isActive ? .secondary : .tertiary)
                    .padding(8)
            }
        }
    }

    private var iconName: String {
        if host.isPaired {
            host.isOnline ? "desktopcomputer" : "desktopcomputer.trianglebadge.exclamationmark"
        } else {
            "lock.desktopcomputer"
        }
    }

    private var iconColor: Color {
        if !host.isPaired { return isActive ? .orange : .secondary }
        return isActive ? .green : .secondary
    }

    private var statusText: String {
        if host.updatePending { return "Updating..." }
        if !host.isPaired { return "Not Paired" }
        return host.isOnline ? "Online" : "Offline"
    }
}
