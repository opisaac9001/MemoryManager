import Charts
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var monitor: ProcessMonitor
    @EnvironmentObject private var storage: StorageMonitor
    @State private var pendingForceQuit: AppMemory?
    @State private var pendingPause: AppMemory?

    var body: some View {
        VStack(spacing: 0) {
            dashboardPicker
            if monitor.dashboardMode == .storage {
                StorageView()
            } else if monitor.dashboardMode == .insights {
                InsightsView()
            } else {
                Group {
                    switch monitor.dashboardMode {
                    case .memory: systemOverview
                    case .cpu: cpuOverview
                    case .activity: activityOverview
                    case .storage: EmptyView()
                    case .insights: EmptyView()
                    }
                }
                Divider()
                controls
                Divider()
                appList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { monitor.searchText = "" }
        .alert("Couldn’t complete that action", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(monitor.errorMessage ?? "An unknown error occurred.")
        }
        .confirmationDialog(
            "Force quit \(pendingForceQuit?.name ?? "this app")?",
            isPresented: forceQuitIsPresented,
            titleVisibility: .visible
        ) {
            Button("Force Quit", role: .destructive) {
                if let app = pendingForceQuit { monitor.forceQuit(app) }
                pendingForceQuit = nil
            }
            Button("Cancel", role: .cancel) { pendingForceQuit = nil }
        } message: {
            Text("Unsaved changes in this app will be lost.")
        }
        .confirmationDialog(
            "Pause \(pendingPause?.name ?? "this app")?",
            isPresented: pauseIsPresented,
            titleVisibility: .visible
        ) {
            Button("Pause App") {
                if let app = pendingPause { monitor.togglePause(app) }
                pendingPause = nil
            }
            Button("Cancel", role: .cancel) { pendingPause = nil }
        } message: {
            Text("The app and its helper processes will stop responding until resumed.")
        }
    }

    private var dashboardPicker: some View {
        Picker("Dashboard", selection: $monitor.dashboardMode) {
            ForEach(DashboardMode.allCases) { mode in
                Label(mode.label, systemImage: mode.symbol).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var systemOverview: some View {
        VStack(spacing: 14) {
            HStack(spacing: 18) {
                ZStack {
                    Circle().stroke(Color.secondary.opacity(0.16), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: monitor.memory.usedPercent / 100)
                        .stroke(pressureColor, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(monitor.memory.usedPercent.rounded()))%")
                        .font(.system(.headline, design: .rounded).weight(.semibold))
                }
                .frame(width: 74, height: 74)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Memory")
                        .font(.title2.weight(.semibold))
                    Text("\(formatBytes(monitor.memory.usedBytes)) of \(formatBytes(monitor.memory.totalBytes)) used")
                        .font(.headline)
                    Text("\(formatBytes(monitor.memory.availableBytes)) readily available")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                metric(value: formatBytes(monitor.memory.swapUsedBytes), label: "Swap used")
                Divider().frame(height: 44)
                VStack(alignment: .trailing, spacing: 5) {
                    Label(monitor.memory.pressure.label, systemImage: "circle.fill")
                        .font(.headline)
                        .foregroundStyle(pressureColor)
                    Text("System pressure")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            MemoryBreakdownBar(snapshot: monitor.memory)

            if monitor.showHistory {
                historyChart
            }
        }
        .padding(20)
        .padding(.top, -4)
    }

    private var cpuOverview: some View {
        VStack(spacing: 14) {
            HStack(spacing: 18) {
                gauge(percent: monitor.cpu.overallPercent, color: cpuColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text("CPU").font(.title2.weight(.semibold))
                    Text("\(monitor.cpu.equivalentCores, specifier: "%.1f") equivalent cores in use")
                        .font(.headline)
                    Text("Rows below use the same whole-machine percentage scale")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                metric(value: "\(Int(monitor.cpu.userPercent.rounded()))%", label: "User")
                metric(value: "\(Int(monitor.cpu.systemPercent.rounded()))%", label: "System")
                Divider().frame(height: 44)
                VStack(alignment: .trailing, spacing: 5) {
                    Label(monitor.thermalLevel.label, systemImage: "thermometer.medium")
                        .font(.headline)
                        .foregroundStyle(thermalColor)
                    Text(monitor.lowPowerModeEnabled ? "Low Power Mode" : "Thermal state")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            cpuHistoryChart
            perCoreGrid
        }
        .padding(20)
        .padding(.top, -4)
    }

    private var activityOverview: some View {
        VStack(spacing: 14) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                activityCard(
                    title: powerTitle, value: powerValue,
                    subtitle: powerSubtitle, symbol: "bolt.fill", color: .yellow
                )
                activityCard(
                    title: "Disk read", value: formatRate(monitor.diskReadBytesPerSecond),
                    subtitle: "All readable processes", symbol: "arrow.down.to.line", color: .blue
                )
                activityCard(
                    title: "Disk write", value: formatRate(monitor.diskWriteBytesPerSecond),
                    subtitle: "All readable processes", symbol: "arrow.up.to.line", color: .orange
                )
                activityCard(
                    title: monitor.hardware.gpuName,
                    value: monitor.hardware.gpuCoreCount.map { "\($0) GPU cores" } ?? "GPU",
                    subtitle: "Live load unavailable publicly", symbol: "display", color: .purple
                )
                activityCard(
                    title: "CPU hardware",
                    value: "\(monitor.hardware.logicalCPUCount) logical cores",
                    subtitle: "\(monitor.hardware.physicalCPUCount) physical cores", symbol: "cpu", color: .green
                )
            }
            HStack {
                Text("History range").font(.caption).foregroundStyle(.secondary)
                Spacer()
                historyRangePicker
            }
            if monitor.chartHistory.contains(where: { $0.powerWatts != nil }) {
                HStack(alignment: .top, spacing: 18) {
                    diskHistoryChart.frame(maxWidth: .infinity)
                    powerHistoryChart.frame(maxWidth: .infinity)
                }
            } else {
                diskHistoryChart
            }
            Text(powerExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .padding(.top, -4)
    }

    private func gauge(percent: Double, color: Color) -> some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.16), lineWidth: 9)
            Circle()
                .trim(from: 0, to: min(1, percent / 100))
                .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(percent.rounded()))%")
                .font(.system(.headline, design: .rounded).weight(.semibold))
        }
        .frame(width: 74, height: 74)
    }

    private func activityCard(
        title: String, value: String, subtitle: String, symbol: String, color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
            Text(value).font(.headline.monospacedDigit()).lineLimit(1)
            Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func metric(value: String, label: String) -> some View {
        VStack(alignment: .trailing, spacing: 5) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var historyChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Recent memory history", systemImage: "chart.xyaxis.line")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                historyRangePicker
                if monitor.chartHistory.count > 1 {
                    Text("\(monitor.chartHistory.count) samples")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Chart(monitor.chartHistory) { point in
                AreaMark(
                    x: .value("Time", point.date),
                    y: .value("RAM used", point.usedPercent)
                )
                .foregroundStyle(pressureColor.opacity(0.12))
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("RAM used", point.usedPercent)
                )
                .foregroundStyle(pressureColor)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: [0, 50, 100])
            }
            .frame(height: 72)
        }
    }

    private var cpuHistoryChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("CPU history", systemImage: "chart.xyaxis.line")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                historyRangePicker
            }
            Chart(monitor.chartHistory) { point in
                AreaMark(x: .value("Time", point.date), y: .value("CPU", point.cpuPercent))
                    .foregroundStyle(cpuColor.opacity(0.12))
                LineMark(x: .value("Time", point.date), y: .value("CPU", point.cpuPercent))
                    .foregroundStyle(cpuColor)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: [0, 50, 100])
            }
            .frame(height: 66)
        }
    }

    private var perCoreGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Logical cores").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("One bar per schedulable CPU core")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 6) {
                ForEach(Array(monitor.cpu.perCorePercent.enumerated()), id: \.offset) { index, percent in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("C\(index + 1)").font(.caption2.weight(.semibold))
                            Spacer()
                            Text("\(Int(percent.rounded()))%").font(.caption2.monospacedDigit())
                        }
                        ProgressView(value: percent, total: 100).tint(cpuColor(for: percent))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    private var diskHistoryChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Recent tracked disk activity", systemImage: "chart.xyaxis.line")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Chart {
                ForEach(monitor.chartHistory) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Bytes per second", point.diskReadBytesPerSecond),
                        series: .value("Direction", "Read")
                    ).foregroundStyle(by: .value("Direction", "Read"))
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Bytes per second", point.diskWriteBytesPerSecond),
                        series: .value("Direction", "Write")
                    ).foregroundStyle(by: .value("Direction", "Write"))
                }
            }
            .chartForegroundStyleScale(["Read": Color.blue, "Write": Color.orange])
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 72)
        }
    }

    private var powerHistoryChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Recent battery power", systemImage: "bolt.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Chart {
                ForEach(monitor.chartHistory.filter { $0.powerWatts != nil }) { point in
                    AreaMark(
                        x: .value("Time", point.date),
                        y: .value("Watts", point.powerWatts ?? 0)
                    )
                    .foregroundStyle(Color.yellow.opacity(0.12))
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Watts", point.powerWatts ?? 0)
                    )
                    .foregroundStyle(Color.yellow)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 72)
        }
    }

    private var powerTitle: String {
        if monitor.power.isCharging { return "Battery charging" }
        if monitor.power.source == .battery { return "Battery draw" }
        return "Battery power"
    }

    private var powerValue: String {
        monitor.power.watts.map { String(format: "%.1f W", $0) } ?? "Unavailable"
    }

    private var powerSubtitle: String {
        if monitor.power.source == .unavailable { return "No internal battery detected" }
        var parts: [String] = []
        if let percent = monitor.power.batteryPercent {
            parts.append("\(Int(percent.rounded()))%")
        }
        if let minutes = monitor.power.minutesRemaining, minutes > 0 {
            parts.append(formatDuration(minutes))
        }
        if monitor.power.source == .acPower, !monitor.power.isCharging {
            parts.append("On power adapter")
        }
        return parts.isEmpty ? "Live battery flow estimate" : parts.joined(separator: " • ")
    }

    private var powerExplanation: String {
        let gpu = "GPU core count is hardware information; macOS does not publicly expose reliable live GPU utilization."
        switch monitor.power.source {
        case .battery:
            return "Battery power is estimated from macOS-reported voltage × current. \(gpu)"
        case .acPower:
            let adapter = monitor.power.adapterRatedWatts.map { " The \($0) W adapter figure is its rated capacity, not current wall draw." } ?? ""
            return "While plugged in, watts show battery charge flow—not the Mac’s total wall power.\(adapter) \(gpu)"
        case .unavailable:
            return "This Mac does not report an internal battery, so public macOS data cannot provide actual whole-system watts without privileged or private measurement. \(gpu)"
        }
    }

    private func formatDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours > 0 ? "\(hours)h \(remainder)m" : "\(remainder)m"
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search apps or PID", text: $monitor.searchText)
                .textFieldStyle(.plain)
            if !monitor.searchText.isEmpty {
                Button {
                    monitor.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
            Spacer()
            Menu {
                Picker("Sort", selection: $monitor.sortMode) {
                    ForEach(AppSortMode.allCases) { mode in Text(mode.label).tag(mode) }
                }
                Divider()
                Toggle("Combine helper processes", isOn: $monitor.combineProcesses)
                Toggle("Show history", isOn: $monitor.showHistory)
                Toggle("Live updates", isOn: $monitor.autoRefresh)
            } label: {
                Label("View", systemImage: "line.3.horizontal.decrease.circle")
            }
            Button {
                monitor.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }

    private var appList: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    monitor.sortMode = monitor.sortMode == .nameAscending ? .nameDescending : .nameAscending
                } label: {
                    Label(monitor.dashboardMode == .cpu ? "PROCESS" : "APP", systemImage: nameSortSymbol)
                }
                .buttonStyle(.plain)
                Spacer()
                Button {
                    togglePrimarySort()
                } label: {
                    Label(metricHeaderTitle, systemImage: metricSortSymbol)
                }
                .buttonStyle(.plain)
                .frame(width: 190, alignment: .trailing)
                Text("ACTIONS").frame(width: 205, alignment: .trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)

            Divider()

            if monitor.filteredApps.isEmpty {
                ContentUnavailableView(
                    "No Apps Found",
                    systemImage: "app.dashed",
                    description: Text("Try a different search.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(monitor.filteredApps) { app in
                            appRow(app)
                            Divider().padding(.leading, 62)
                        }
                    }
                }
            }
        }
    }

    private func appRow(_ app: AppMemory) -> some View {
        HStack(spacing: 11) {
            if app.preferenceKey != nil {
                Button {
                    monitor.toggleFavorite(app)
                } label: {
                    Image(systemName: app.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(app.isFavorite ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .help(app.isFavorite ? "Unpin app" : "Pin app to the top")
            } else {
                Color.clear.frame(width: 13, height: 13)
            }

            Image(nsImage: app.icon)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(app.name).font(.body.weight(.medium)).lineLimit(1)
                    if app.isPaused {
                        Text(app.isPausedByManager ? "PAUSED BY US" : "PAUSED")
                            .font(.caption2.bold())
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.12), in: Capsule())
                    }
                    if app.isIgnored {
                        Text("HIDDEN FROM MENU")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 5) {
                    if app.isSystemProcess {
                        Text(app.relatedPIDs.isEmpty ? "kernel and unreadable processes" : "system/background • PID \(app.pid)")
                    } else {
                        Text("PID \(app.pid)")
                    }
                    if !app.isSystemProcess && app.relatedPIDs.count > 1 {
                        Text("• \(app.relatedPIDs.count) processes")
                    } else if !app.isSystemProcess && app.isHelper {
                        Text("• helper")
                    }
                    if app.detachedProcessCount > 0 {
                        Text("• \(app.detachedProcessCount) sandbox/detached")
                            .foregroundStyle(.blue)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            appMetric(app)
                .frame(width: 190, alignment: .trailing)

            Group {
                if app.canControl {
                    HStack(spacing: 8) {
                        Button(app.isPaused ? "Resume" : "Pause") {
                            if app.isPaused { monitor.togglePause(app) } else { pendingPause = app }
                        }

                        Menu("Quit") {
                            Button("Quit Normally") { monitor.quit(app) }
                            Divider()
                            Button("Force Quit", role: .destructive) { pendingForceQuit = app }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                } else {
                    Text("Managed by macOS")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 205, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .contextMenu {
            if app.canControl {
                if app.preferenceKey != nil {
                    Button(app.isFavorite ? "Unpin App" : "Pin App") { monitor.toggleFavorite(app) }
                    Button(app.isIgnored ? "Show in Menu Bar" : "Hide from Menu Bar") { monitor.toggleIgnored(app) }
                    Divider()
                }
                Button(app.isPaused ? "Resume" : "Pause") {
                    if app.isPaused { monitor.togglePause(app) } else { pendingPause = app }
                }
                Button("Quit Normally") { monitor.quit(app) }
                Button("Force Quit", role: .destructive) { pendingForceQuit = app }
            } else {
                Text("This process is managed by macOS.")
            }
        }
    }

    private var pressureColor: Color {
        switch monitor.memory.pressure {
        case .normal: return .green
        case .elevated: return .orange
        case .critical: return .red
        }
    }

    private var nameSortSymbol: String {
        monitor.sortMode == .nameDescending ? "chevron.down" : "chevron.up"
    }
    private var memorySortSymbol: String {
        monitor.sortMode == .memoryAscending ? "chevron.up" : "chevron.down"
    }

    @ViewBuilder
    private func appMetric(_ app: AppMemory) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            switch monitor.dashboardMode {
            case .memory:
                Text(formatBytes(app.memoryBytes))
                    .font(.system(.body, design: .monospaced).weight(.medium))
                if let growth = monitor.growthInsight(for: app) {
                    Label(
                        "+\(formatBytes(UInt64(growth.rateBytesPerMinute)))/min",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.orange)
                } else if abs(app.memoryChangeBytes) >= 25 * 1_024 * 1_024 {
                    Text(formatMemoryChange(app.memoryChangeBytes))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(app.memoryChangeBytes > 0 ? .orange : .green)
                }
            case .cpu:
                Text(formatCPU(app.wholeMachineCPUPercent(
                    activeProcessorCount: monitor.cpu.activeCoreCount
                )))
                    .font(.system(.body, design: .monospaced).weight(.medium))
                Text(formatCoreUsage(app.cpuPercent))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            case .activity:
                Text("R \(formatRate(app.diskReadBytesPerSecond))")
                    .font(.caption.monospacedDigit())
                Text("W \(formatRate(app.diskWriteBytesPerSecond))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            case .storage:
                EmptyView()
            case .insights:
                EmptyView()
            }
        }
        .help(metricHelp)
    }

    private var metricHeaderTitle: String {
        switch monitor.dashboardMode {
        case .memory: return "FOOTPRINT"
        case .cpu: return "CPU SHARE / CORES"
        case .activity: return "DISK I/O"
        case .storage: return "SIZE"
        case .insights: return "INSIGHT"
        }
    }

    private var metricHelp: String {
        switch monitor.dashboardMode {
        case .memory: return "Physical footprint; change is since the previous sample"
        case .cpu: return "Percent of the whole Mac first; equivalent logical cores second"
        case .activity: return "Read and write rates since the previous sample"
        case .storage: return "Allocated storage size"
        case .insights: return "Longer-term resource insight"
        }
    }

    private var metricSortSymbol: String {
        switch monitor.dashboardMode {
        case .memory: return memorySortSymbol
        case .cpu: return monitor.sortMode == .cpuAscending ? "chevron.up" : "chevron.down"
        case .activity: return "chevron.down"
        case .storage: return "chevron.down"
        case .insights: return "chevron.down"
        }
    }

    private func togglePrimarySort() {
        switch monitor.dashboardMode {
        case .memory:
            monitor.sortMode = monitor.sortMode == .memoryDescending ? .memoryAscending : .memoryDescending
        case .cpu:
            monitor.sortMode = monitor.sortMode == .cpuDescending ? .cpuAscending : .cpuDescending
        case .activity:
            monitor.sortMode = .diskDescending
        case .storage:
            break
        case .insights:
            break
        }
    }

    private var historyRangePicker: some View {
        Picker("History range", selection: $monitor.historyRange) {
            ForEach(HistoryRange.allCases) { range in Text(range.label).tag(range) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 225)
        .controlSize(.small)
    }

    private var cpuColor: Color { cpuColor(for: monitor.cpu.overallPercent) }

    private func cpuColor(for percent: Double) -> Color {
        if percent >= 85 { return .red }
        if percent >= 60 { return .orange }
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
    private var errorIsPresented: Binding<Bool> {
        Binding(get: { monitor.errorMessage != nil }, set: { if !$0 { monitor.errorMessage = nil } })
    }
    private var forceQuitIsPresented: Binding<Bool> {
        Binding(get: { pendingForceQuit != nil }, set: { if !$0 { pendingForceQuit = nil } })
    }
    private var pauseIsPresented: Binding<Bool> {
        Binding(get: { pendingPause != nil }, set: { if !$0 { pendingPause = nil } })
    }
}

private struct MemoryBreakdownBar: View {
    let snapshot: MemorySnapshot

    var body: some View {
        VStack(spacing: 7) {
            GeometryReader { geometry in
                HStack(spacing: 1) {
                    segment(snapshot.appBytes, color: .blue, width: geometry.size.width)
                    segment(snapshot.wiredBytes, color: .purple, width: geometry.size.width)
                    segment(snapshot.compressedBytes, color: .orange, width: geometry.size.width)
                    segment(snapshot.cachedBytes, color: .green.opacity(0.7), width: geometry.size.width)
                    Spacer(minLength: 0)
                }
                .background(Color.secondary.opacity(0.1))
                .clipShape(Capsule())
            }
            .frame(height: 9)

            HStack(spacing: 16) {
                legend("App", snapshot.appBytes, .blue)
                legend("Wired", snapshot.wiredBytes, .purple)
                legend("Compressed", snapshot.compressedBytes, .orange)
                legend("Cached", snapshot.cachedBytes, .green)
                Spacer()
            }
        }
    }

    private func segment(_ bytes: UInt64, color: Color, width: Double) -> some View {
        color.frame(width: snapshot.totalBytes > 0 ? width * Double(bytes) / Double(snapshot.totalBytes) : 0)
    }

    private func legend(_ name: String, _ bytes: UInt64, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(name) \(formatBytes(bytes))")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private func formatMemoryChange(_ bytes: Int64) -> String {
    let prefix = bytes > 0 ? "+" : "−"
    let magnitude = UInt64(bytes.magnitude)
    return prefix + formatBytes(magnitude)
}

private func formatCPU(_ percent: Double) -> String {
    percent < 10 ? String(format: "%.1f%%", percent) : String(format: "%.0f%%", percent)
}

func formatRate(_ bytesPerSecond: UInt64) -> String {
    "\(formatBytes(bytesPerSecond))/s"
}

private func formatCoreUsage(_ cpuPercent: Double) -> String {
    let cores = cpuPercent / 100
    if cores == 0 { return "0 cores" }
    if cores < 0.01 { return String(format: "%.3f cores", cores) }
    if cores < 1 { return String(format: "%.2f cores", cores) }
    return String(format: "%.1f cores", cores)
}

#Preview {
    ContentView()
        .environmentObject(ProcessMonitor())
        .environmentObject(StorageMonitor())
        .frame(width: 920, height: 820)
}
