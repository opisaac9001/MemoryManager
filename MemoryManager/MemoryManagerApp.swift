import AppKit
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var monitor: ProcessMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.resumeAllManaged()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func application(
        _ application: NSApplication,
        shouldRestoreWindowWithIdentifier identifier: NSUserInterfaceItemIdentifier,
        state: NSCoder
    ) -> Bool {
        false
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

@main
struct MemoryManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor = ProcessMonitor()
    @StateObject private var storage = StorageMonitor()
    @AppStorage("showMenuBar") private var showMenuBar = true

    var body: some Scene {
        WindowGroup("Memory Manager", id: "main") {
            ContentView()
                .environmentObject(monitor)
                .environmentObject(storage)
                .frame(minWidth: 920, minHeight: 680)
                .onAppear { appDelegate.monitor = monitor }
        }
        .defaultSize(width: 1100, height: 840)
        .windowStyle(.titleBar)
        .commands {
            CommandMenu("Memory") {
                Button("Refresh") { monitor.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Export Activity History…") { monitor.exportHistory() }
                    .disabled(monitor.historicalSampleCount == 0)
                Button("Export Diagnostic Snapshot…") { monitor.exportDiagnosticReport(storage: storage) }
                Button("Resume Everything Paused by Memory Manager") {
                    monitor.resumeAllManaged()
                }
                .disabled(monitor.managedPauseCount == 0)
            }
            CommandMenu("Storage") {
                Button(storage.isScanning ? "Cancel Storage Scan" : "Scan Storage") {
                    if storage.isScanning { storage.cancelScan() } else { storage.startScan() }
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                Button("Choose Folder to Scan…") { storage.chooseFolder() }
                    .disabled(storage.isScanning)
                Button("Find Duplicate Files…") { storage.chooseFolderForDuplicates() }
                    .disabled(storage.isFindingDuplicates)
                Divider()
                Button("Open Trash") { storage.openTrash() }
            }
        }

        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarView()
                .environmentObject(monitor)
        } label: {
            Label(monitor.menuBarTitle, systemImage: "memorychip")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(monitor)
                .environmentObject(storage)
        }
    }
}
