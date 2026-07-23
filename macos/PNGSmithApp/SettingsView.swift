import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: PNGSmithSettingsStore
    @State private var showResetConfirmation = false

    private enum Effort: Hashable {
        case fast, balanced, maximum
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 14) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 48, height: 48)
                            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Settings")
                                .font(.title2.weight(.semibold))
                            Text("Tune how PNGSmith compresses and saves your images.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    settingsSection("Compression", systemImage: "gauge.with.dots.needle.67percent", tint: .blue) {
                        Picker("Effort", selection: effortBinding) {
                            Text("Fast").tag(Effort.fast)
                            Text("Balanced").tag(Effort.balanced)
                            Text("Maximum").tag(Effort.maximum)
                        }
                        .pickerStyle(.segmented)
                        effortEstimate
                    }

                    settingsSection("Saving & verification", systemImage: "checkmark.shield", tint: .green) {
                        VStack(spacing: 0) {
                            settingToggle(
                                "Verify decoded pixels",
                                detail: "Re-open every lossless result and compare all pixels.",
                                isOn: $store.settings.verifyPixels
                            )
                            Divider().padding(.vertical, 10)
                            HStack(spacing: 14) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Copy filename suffix")
                                        .font(.subheadline.weight(.medium))
                                    Text("Copies use names like image\(store.settings.suffix).png.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 16)
                                TextField("_min", text: $store.settings.suffix)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 120)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }

                    settingsSection("Finder", systemImage: "folder", tint: .orange) {
                        VStack(spacing: 12) {
                            integrationRow("Compress", detail: "Lossless Quick Action and Service")
                            integrationRow("Reduce to 256 Colors", detail: "Smaller, visually optimized output")
                            Divider()
                            HStack {
                                Button("Keyboard Shortcuts…") { openSystemSettings(keyboardSettingsURL) }
                                    .help("Open Keyboard Shortcuts, then choose Services")
                                Button("Login Items & Extensions…") { openSystemSettings(extensionsSettingsURL) }
                                    .help("Open Extensions, then expand Finder")
                                Spacer()
                            }
                        }
                    }
                }
                .padding(24)
            }

            Divider()
            HStack {
                Button("Restore Defaults…") {
                    showResetConfirmation = true
                }
                Spacer()
                Text("Changes are saved automatically")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.bar)
        }
        .frame(width: 620, height: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .confirmationDialog("Restore default settings?", isPresented: $showResetConfirmation) {
            Button("Restore Defaults", role: .destructive) { store.reset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Compression, verification, and filename settings will all be reset.")
        }
    }

    private var effortEstimate: some View {
        let estimate = effortEstimateContent
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: estimate.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(estimate.tint)
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(estimate.title)
                    .font(.caption.weight(.semibold))
                Text(estimate.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(estimate.tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var effortEstimateContent: (icon: String, title: String, detail: String, tint: Color) {
        switch effortBinding.wrappedValue {
        case .fast:
            return (
                "hare.fill",
                "Fastest turnaround",
                "Uses fewer compression trials and may produce a slightly larger file.",
                .blue
            )
        case .balanced:
            return (
                "checkmark.circle.fill",
                "Recommended for everyday use",
                "Usually captures most of the available savings without a long wait.",
                .green
            )
        case .maximum:
            return (
                "hourglass",
                "Often 20–100× slower",
                "Typically saves another 0–10% versus Balanced; some images gain nothing.",
                .orange
            )
        }
    }

    private let keyboardSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts"
    )
    private let extensionsSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
    )

    private func openSystemSettings(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }

    private func settingsSection<Content: View>(
        _ title: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(title).font(.headline)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 20)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func settingToggle(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 20)
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn.wrappedValue ? "On" : "Off")
    }

    private var effortBinding: Binding<Effort> {
        Binding {
            if store.settings.zopfli { return .maximum }
            if store.settings.oxipngLevel <= 2 { return .fast }
            return .balanced
        } set: { effort in
            switch effort {
            case .fast:
                store.settings.oxipngLevel = 2
                store.settings.zopfli = false
            case .balanced:
                store.settings.oxipngLevel = 4
                store.settings.zopfli = false
            case .maximum:
                store.settings.oxipngLevel = 6
                store.settings.zopfli = true
            }
        }
    }

    private func integrationRow(_ title: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
