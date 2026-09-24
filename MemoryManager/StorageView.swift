import SwiftUI

struct StorageView: View {
    @EnvironmentObject private var storage: StorageMonitor
    @State private var pendingTrashItem: StorageItem?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    volumeOverview
                    scanControls
                    if storage.isScanning { scanProgress }
                    if let message = storage.statusMessage { statusBanner(message) }
                    if !storage.categories.isEmpty { categoryStrip }
                    if !storage.smartInsights.isEmpty { smartInsightsSection }
                    if storage.duplicateStatus != nil || !storage.duplicateGroups.isEmpty { duplicateSection }
                    transparencyNote
                }
                .padding(20)
            }
            .frame(maxHeight: 480)

            Divider()
            itemControls
            Divider()
            itemList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .confirmationDialog(
            "Move \(pendingTrashItem?.name ?? "this item") to the Trash?",
            isPresented: trashConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                if let item = pendingTrashItem { storage.moveToTrash(item) }
                pendingTrashItem = nil
            }
            Button("Cancel", role: .cancel) { pendingTrashItem = nil }
        } message: {
            if let item = pendingTrashItem {
                Text("This moves \(formatBytes(item.allocatedBytes)) at \(item.url.path) to the Trash. Space is reclaimed only after you empty the Trash.")
            }
        }
        .alert("Storage action couldn’t be completed", isPresented: errorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(storage.errorMessage ?? "An unknown error occurred.")
        }
    }

    private var volumeOverview: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.16), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: storage.volume.usedPercent / 100)
                    .stroke(storage.volume.usedPercent > 90 ? .red : .blue,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(Int(storage.volume.usedPercent.rounded()))%")
                        .font(.headline.monospacedDigit())
                    Text("used").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 86, height: 86)

            VStack(alignment: .leading, spacing: 5) {
                Text("Storage").font(.title2.weight(.semibold))
                Text("\(formatBytes(storage.volume.usedBytes)) of \(formatBytes(storage.volume.totalBytes)) used")
                    .font(.headline)
                Text("The scan explains where space is going, including normally opaque System Data locations.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)
            volumeMetric(formatBytes(storage.volume.freeBytes), "Free now")
            Divider().frame(height: 48)
            volumeMetric(formatBytes(storage.volume.reclaimableBytes), "Purgeable estimate")
            if storage.lastScanned != nil {
                Divider().frame(height: 48)
                volumeMetric(formatBytes(storage.scannedBytes), "Files classified")
            }
            if storage.spaceGainedThisSession > 0 {
                Divider().frame(height: 48)
                volumeMetric(formatBytes(storage.spaceGainedThisSession), "Free space gained")
            }
        }
    }

    private func volumeMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var scanControls: some View {
        HStack(spacing: 10) {
            if storage.isScanning {
                Button("Cancel Scan", role: .cancel) { storage.cancelScan() }
            } else {
                Button { storage.startScan() } label: {
                    Label(storage.lastScanned == nil ? "Scan Storage" : "Scan Again", systemImage: "internaldrive")
                }
                .buttonStyle(.borderedProminent)
            }
            Button { storage.chooseFolder() } label: {
                Label("Choose Folder…", systemImage: "folder.badge.plus")
            }
            .disabled(storage.isScanning)
            if storage.isFindingDuplicates {
                Button("Cancel Duplicates", role: .cancel) { storage.cancelDuplicateSearch() }
            } else {
                Button { storage.chooseFolderForDuplicates() } label: {
                    Label("Find Duplicates…", systemImage: "doc.on.doc")
                }
            }
            Toggle("Include protected system locations", isOn: $storage.includeProtectedLocations)
                .toggleStyle(.checkbox)
                .disabled(storage.isScanning)
            Spacer()
            Menu {
                Button("Open macOS Storage Settings") { storage.openStorageSettings() }
                Button("Open Full Disk Access Settings") { storage.openFullDiskAccessSettings() }
                Divider()
                Button("Open Trash") { storage.openTrash() }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }

    private var scanProgress: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(storage.currentLocation).font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Int((storage.progress * 100).rounded()))%")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            ProgressView(value: storage.progress)
            Text("Scanning runs only when requested so it does not continuously use the disk or battery.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func statusBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(message).font(.subheadline)
            Spacer()
            Button {
                storage.statusMessage = nil
            } label: {
                Image(systemName: "xmark").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(storage.categories) { category in
                    Button {
                        storage.searchText = category.name
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: categorySymbol(category))
                                    .foregroundStyle(riskColor(category.risk))
                                Text(category.name).font(.caption.weight(.semibold)).lineLimit(1)
                            }
                            Text(formatBytes(category.bytes)).font(.headline.monospacedDigit())
                            Text("\(category.itemCount) top-level items")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .frame(width: 180, alignment: .leading)
                        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var smartInsightsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Smart cleanup review", systemImage: "sparkles")
                .font(.headline)
            Text("Suggestions are review-only. Possible leftovers and older apps are never removed automatically.")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(storage.smartInsights.prefix(12)) { insight in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(insight.title, systemImage: insightSymbol(insight.kind))
                                .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                            Text(insight.item.name).font(.headline).lineLimit(1)
                            Text(formatBytes(insight.item.allocatedBytes)).font(.caption.monospacedDigit())
                            Text(insight.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                            HStack {
                                Button("Show in List") { storage.searchText = insight.item.name }
                                Button("Reveal") { storage.reveal(insight.item) }
                            }
                            .controlSize(.small)
                        }
                        .padding(10)
                        .frame(width: 225, alignment: .leading)
                        .frame(minHeight: 125, alignment: .topLeading)
                        .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    private var duplicateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Duplicate files", systemImage: "doc.on.doc")
                    .font(.headline)
                if storage.isFindingDuplicates { ProgressView().controlSize(.small) }
                Spacer()
                if !storage.isFindingDuplicates {
                    Button("Check Another Folder…") { storage.chooseFolderForDuplicates() }
                        .controlSize(.small)
                }
            }
            if let status = storage.duplicateStatus {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(storage.duplicateGroups.prefix(8)) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(group.files.count) identical files • \(formatBytes(group.fileSize)) each • up to \(formatBytes(group.reclaimableBytes)) recoverable")
                        .font(.caption.weight(.semibold))
                    ForEach(group.files.prefix(4), id: \.path) { url in
                        HStack {
                            Text(url.path).font(.caption2).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button("Reveal") { storage.reveal(url) }.controlSize(.mini)
                        }
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
            }
            if !storage.duplicateGroups.isEmpty {
                Text("Memory Manager compares file contents, not just names. Review each copy in Finder before removing anything.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.blue.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
    }

    private func insightSymbol(_ kind: StorageInsightKind) -> String {
        switch kind {
        case .installer: return "shippingbox"
        case .cache: return "bolt.horizontal.circle"
        case .olderApplication: return "app.badge.clock"
        case .possibleLeftover: return "questionmark.folder"
        }
    }

    private var transparencyNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: storage.inaccessibleCount > 0 ? "lock.trianglebadge.exclamationmark" : "info.circle")
                .foregroundStyle(storage.inaccessibleCount > 0 ? .orange : .blue)
            VStack(alignment: .leading, spacing: 3) {
                Text("What “System Data” means here").font(.subheadline.weight(.semibold))
                Text("App support, containers, caches, logs, developer files, backups, web data, temporary data, shared Library files, and /private/var are shown separately. Protected items can be inspected and revealed in Finder, but Memory Manager will not delete them.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Sizes are estimates. APFS snapshots, purgeable space, shared files, hard links, and inaccessible files can make the classified total differ from the volume’s used total.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Personal folders—including Desktop, Documents, Downloads, Music, Movies, Photos, Mail, Messages, and cloud drives—are not opened automatically. This avoids surprise privacy prompts and cloud downloads; use Choose Folder when you want to inspect one.")
                    .font(.caption).foregroundStyle(.secondary)
                if storage.inaccessibleCount > 0 {
                    HStack {
                        Text("\(storage.inaccessibleCount) folders or files could not be read.")
                            .font(.caption.weight(.medium)).foregroundStyle(.orange)
                        Button("Review Full Disk Access") { storage.openFullDiskAccessSettings() }
                            .font(.caption)
                    }
                }
            }
            Spacer()
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private var itemControls: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search files, categories, or paths", text: $storage.searchText)
                .textFieldStyle(.plain)
            if !storage.searchText.isEmpty {
                Button {
                    storage.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Picker("Safety", selection: $storage.selectedRisk) {
                Text("All safety levels").tag(Optional<StorageRisk>.none)
                ForEach(StorageRisk.allCases, id: \.rawValue) { risk in
                    Text(risk.label).tag(Optional(risk))
                }
            }
            .frame(width: 190)
            if storage.lastScanned != nil {
                Text("\(storage.filteredItems.count) items • \(storage.measuredItemCount.formatted()) measured")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }

    private var itemList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("ITEM / LOCATION")
                Spacer()
                Text("SAFETY").frame(width: 145, alignment: .leading)
                Text("SIZE").frame(width: 110, alignment: .trailing)
                Text("ACTIONS").frame(width: 160, alignment: .trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            Divider()

            if storage.items.isEmpty && !storage.isScanning {
                ContentUnavailableView(
                    storage.lastScanned == nil ? "Ready to Inspect Storage" : "No Storage Items Found",
                    systemImage: "internaldrive",
                    description: Text(storage.lastScanned == nil
                        ? "Run a scan to see large files and break down System Data."
                        : "Try clearing the search or changing the safety filter.")
                )
            } else if storage.filteredItems.isEmpty {
                ContentUnavailableView(
                    "No Matching Items", systemImage: "magnifyingglass",
                    description: Text("Try a different search or safety filter.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(storage.filteredItems) { item in
                            itemRow(item)
                            Divider().padding(.leading, 54)
                        }
                    }
                }
            }
        }
    }

    private func itemRow(_ item: StorageItem) -> some View {
        HStack(spacing: 11) {
            Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundStyle(riskColor(item.risk))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.body.weight(.medium)).lineLimit(1)
                Text("\(item.category) • \(item.url.path)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 10)
            Text(item.risk.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(riskColor(item.risk))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(riskColor(item.risk).opacity(0.10), in: Capsule())
                .frame(width: 145, alignment: .leading)
            VStack(alignment: .trailing, spacing: 2) {
                Text(item.isMeasured ? formatBytes(item.allocatedBytes) : "Couldn’t measure")
                    .font(.body.monospacedDigit().weight(.medium))
                    .foregroundStyle(item.isMeasured ? Color.primary : Color.orange)
                Text(item.isDirectory ? "Folder" : "File").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 110, alignment: .trailing)
            HStack(spacing: 7) {
                Button("Reveal") { storage.reveal(item) }
                if storage.canMoveToTrash(item) {
                    Button("Trash", role: .destructive) { pendingTrashItem = item }
                }
            }
            .frame(width: 160, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Reveal in Finder") { storage.reveal(item) }
            if storage.canMoveToTrash(item) {
                Divider()
                Button("Move to Trash", role: .destructive) { pendingTrashItem = item }
            }
        }
    }

    private func categorySymbol(_ category: StorageCategorySummary) -> String {
        let name = category.name.lowercased()
        if name.contains("cache") { return "bolt.horizontal.circle" }
        if name.contains("developer") { return "hammer" }
        if name.contains("system") || name.contains("library") { return "gearshape.2" }
        if name.contains("trash") { return "trash" }
        if name.contains("application") { return "app.dashed" }
        return "folder"
    }

    private func riskColor(_ risk: StorageRisk) -> Color {
        switch risk {
        case .usuallyRemovable: return .green
        case .reviewCarefully: return .orange
        case .protected: return .red
        }
    }

    private var trashConfirmationPresented: Binding<Bool> {
        Binding(get: { pendingTrashItem != nil }, set: { if !$0 { pendingTrashItem = nil } })
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { storage.errorMessage != nil }, set: { if !$0 { storage.errorMessage = nil } })
    }
}

#Preview {
    StorageView()
        .environmentObject(StorageMonitor())
        .frame(width: 1100, height: 800)
}
