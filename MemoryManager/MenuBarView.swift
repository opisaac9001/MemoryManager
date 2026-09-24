import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var monitor: ProcessMonitor
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Memory Manager").font(.headline)
                    Text("\(formatBytes(monitor.memory.usedBytes)) of \(formatBytes(monitor.memory.totalBytes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(monitor.memory.pressure.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(pressureColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(pressureColor.opacity(0.12), in: Capsule())
            }

            ProgressView(value: monitor.memory.usedPercent, total: 100)
                .tint(pressureColor)

            HStack(spacing: 8) {
                Text("CPU").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                ProgressView(value: monitor.cpu.overallPercent, total: 100)
                    .tint(cpuColor)
                Text("\(Int(monitor.cpu.overallPercent.rounded()))%")
                    .font(.caption.monospacedDigit())
            }

            HStack {
                miniMetric("RAM", "\(Int(monitor.memory.usedPercent.rounded()))%")
                Spacer()
                miniMetric("Compressed", formatBytes(monitor.memory.compressedBytes))
                Spacer()
                miniMetric("Swap", formatBytes(monitor.memory.swapUsedBytes))
            }

            HStack {
                Label("\(monitor.cpu.equivalentCores, specifier: "%.1f") CPU cores", systemImage: "cpu")
                Spacer()
                if let watts = monitor.power.watts {
                    Label("\(watts, specifier: "%.1f") W", systemImage: "bolt.fill")
                        .foregroundStyle(.yellow)
                    Spacer()
                }
                Label(monitor.thermalLevel.label, systemImage: "thermometer.medium")
                    .foregroundStyle(thermalColor)
            }
            .font(.caption)

            Divider()

            Text("Largest apps")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if monitor.menuBarApps.isEmpty {
                Text("No apps available").foregroundStyle(.secondary)
            } else {
                ForEach(monitor.menuBarApps) { app in
                    HStack(spacing: 8) {
                        Image(nsImage: app.icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                        Text(app.name).lineLimit(1)
                        Spacer()
                        if app.isPaused {
                            Button("Resume") { monitor.togglePause(app) }
                                .controlSize(.small)
                        }
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(formatBytes(app.memoryBytes))
                            Text("CPU \(Int(app.cpuPercent.rounded()))%")
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            HStack {
                Button("Open Memory Manager") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut("o")
                Spacer()
                Button {
                    monitor.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .help("Quit Memory Manager")
            }
        }
        .padding(14)
        .frame(width: 360)
    }

    private func miniMetric(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit())
            Text(name).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var pressureColor: Color {
        switch monitor.memory.pressure {
        case .normal: return .green
        case .elevated: return .orange
        case .critical: return .red
        }
    }

    private var cpuColor: Color {
        if monitor.cpu.overallPercent >= 85 { return .red }
        if monitor.cpu.overallPercent >= 60 { return .orange }
        return .green
    }

    private var thermalColor: Color {
        switch monitor.thermalLevel {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        }
    }
}
