//
//  FolderWatcherService.swift
//  HiFidelity
//
//  Monitors music folders for file system changes and automatically updates the library
//

import Foundation
import Combine

/// Service that monitors music folders for changes and triggers automatic rescans
@MainActor
class FolderWatcherService: ObservableObject {
    static let shared = FolderWatcherService()

    @Published private(set) var isWatching = false
    @Published private(set) var watchedFoldersCount = 0

    private var eventMonitors: [String: FSEventStreamRef] = [:]
    private var rescanDebounceTimers: [String: Timer] = [:]
    private let debounceInterval: TimeInterval = 2.0 // Wait 2 seconds after last change before rescanning

    // Track files being modified by the app to ignore their events
    private var ignoredFiles: Set<String> = []
    private var ignoreTimers: [String: Timer] = [:]
    private let ignoreTimeout: TimeInterval = 5.0 // Ignore file events for 5 seconds after save

    private weak var databaseManager: DatabaseManager?

    private init() {}
    
    // MARK: - Public Methods
    
    /// Start watching all folders in the database
    func startWatching(databaseManager: DatabaseManager) {
        guard !isWatching else { return }
        
        self.databaseManager = databaseManager
        
        let folders = databaseManager.getAllFolders()
        
        guard !folders.isEmpty else {
            Logger.info("No folders to watch")
            return
        }
        
        for folder in folders {
            startWatching(folder: folder)
        }
        
        isWatching = true
        watchedFoldersCount = folders.count
        
        Logger.info("📁 [FOLDER WATCHER] Started watching \(folders.count) folder(s)")
        NotificationManager.shared.addMessage(.info, "Folder Monitoring active")
    }
    
    /// Stop watching all folders
    func stopWatching() {
        guard isWatching else { return }
        
        // Cancel all debounce timers
        for timer in rescanDebounceTimers.values {
            timer.invalidate()
        }
        rescanDebounceTimers.removeAll()
        
        // Stop all event monitors
        for (path, streamRef) in eventMonitors {
            FSEventStreamStop(streamRef)
            FSEventStreamSetDispatchQueue(streamRef, nil) // Clear dispatch queue
            FSEventStreamInvalidate(streamRef)
            FSEventStreamRelease(streamRef)
            Logger.debug("Stopped monitoring: \(path)")
        }
        
        eventMonitors.removeAll()
        isWatching = false
        watchedFoldersCount = 0
        
        Logger.info("Stopped folder monitoring")
        NotificationManager.shared.addMessage(.info, "Folder monitoring stopped")
    }

    /// Temporarily ignore events for a file (called before saving metadata)
    func ignoreFile(at url: URL) {
        let path = url.path

        // Cancel existing timer for this file
        ignoreTimers[path]?.invalidate()

        // Add to ignored files
        ignoredFiles.insert(path)

        // Set timer to remove from ignored list after timeout
        let timer = Timer.scheduledTimer(withTimeInterval: ignoreTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.ignoredFiles.remove(path)
                self?.ignoreTimers.removeValue(forKey: path)
                Logger.debug("📁 [FOLDER WATCHER] Stopped ignoring: \(url.lastPathComponent)")
            }
        }

        ignoreTimers[path] = timer
        Logger.debug("📁 [FOLDER WATCHER] Ignoring file events for: \(url.lastPathComponent)")
    }

    /// Watch a specific folder
    func startWatching(folder: Folder) {
        let path = folder.url.path
        
        // Don't watch if already watching
        guard eventMonitors[path] == nil else {
            Logger.debug("Already watching: \(path)")
            return
        }
        
        // Check if folder exists
        guard FileManager.default.fileExists(atPath: path) else {
            Logger.warning("Cannot watch non-existent folder: \(path)")
            return
        }
        
        // Create event stream context
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        
        let pathsToWatch = [path] as CFArray
        let callback: FSEventStreamCallback = { (
            streamRef,
            clientCallBackInfo,
            numEvents,
            eventPaths,
            eventFlags,
            eventIds
        ) in
            guard let info = clientCallBackInfo else { return }
            let watcher = Unmanaged<FolderWatcherService>.fromOpaque(info).takeUnretainedValue()
            
            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as! [String]
            let flags = UnsafeBufferPointer(start: eventFlags, count: numEvents)
            
            for i in 0..<numEvents {
                let path = paths[i]
                let flag = flags[i]
                
                Task { @MainActor in
                    watcher.handleFileSystemEvent(path: path, flags: flag)
                }
            }
        }
        
        // Create the event stream
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0, // Latency in seconds
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) else {
            Logger.error("Failed to create FSEventStream for: \(path)")
            return
        }
        
        // Set dispatch queue (modern API)
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        
        // Start the stream
        if FSEventStreamStart(stream) {
            eventMonitors[path] = stream
            watchedFoldersCount = eventMonitors.count
            Logger.info("📁 [FOLDER WATCHER] Started monitoring: \(folder.name) at \(path)")
        } else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            Logger.error("📁 [FOLDER WATCHER] Failed to start FSEventStream for: \(path)")
        }
    }
    
    /// Stop watching a specific folder
    func stopWatching(folder: Folder) {
        let path = folder.url.path
        
        guard let streamRef = eventMonitors[path] else {
            Logger.debug("Not watching: \(path)")
            return
        }
        
        // Cancel debounce timer if exists
        rescanDebounceTimers[path]?.invalidate()
        rescanDebounceTimers.removeValue(forKey: path)
        
        // Stop and release the stream
        FSEventStreamStop(streamRef)
        FSEventStreamSetDispatchQueue(streamRef, nil) // Clear dispatch queue
        FSEventStreamInvalidate(streamRef)
        FSEventStreamRelease(streamRef)
        
        eventMonitors.removeValue(forKey: path)
        watchedFoldersCount = eventMonitors.count
        
        Logger.info("Stopped monitoring: \(folder.name)")
    }
    
    // MARK: - Private Methods
    
    private func handleFileSystemEvent(path: String, flags: FSEventStreamEventFlags) {
        // Log all events for debugging (even if we don't process them)
        Logger.debug("📁 [FOLDER WATCHER] Received event for: \(URL(fileURLWithPath: path).lastPathComponent) (flags: \(flags))")

        // Check if this file is being ignored (app is currently saving it)
        if ignoredFiles.contains(path) {
            Logger.debug("📁 [FOLDER WATCHER] Ignoring event for file being saved by app: \(URL(fileURLWithPath: path).lastPathComponent)")
            return
        }

        // Filter out events we don't care about
        let relevantFlags: FSEventStreamEventFlags =
            FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated) |
            FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved) |
            FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed) |
            FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)

        guard flags & relevantFlags != 0 else {
            Logger.debug("📁 [FOLDER WATCHER] Ignoring event (not relevant)")
            return
        }

        // Check if it's a supported audio file
        let fileExtension = URL(fileURLWithPath: path).pathExtension.lowercased()
        guard !fileExtension.isEmpty && AudioFormat.isSupported(fileExtension) else {
            Logger.debug("📁 [FOLDER WATCHER] Ignoring non-audio file: \(fileExtension.isEmpty ? "no extension" : fileExtension)")
            return
        }
        
        // Find the folder that contains this file
        guard let folderPath = findWatchedFolder(for: path),
              let folder = databaseManager?.getAllFolders().first(where: { $0.url.path == folderPath }) else {
            Logger.debug("📁 [FOLDER WATCHER] Could not find watched folder for: \(path)")
            return
        }
        
        // Log the event (use INFO level so it's visible in console)
        let eventType = describeEvent(flags: flags)
        Logger.info("📁 [FOLDER WATCHER] File system event in \(folder.name): \(eventType) - \(URL(fileURLWithPath: path).lastPathComponent)")
        
        // Debounce the rescan - cancel existing timer and create a new one
        rescanDebounceTimers[folderPath]?.invalidate()
        
        let timer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.rescanFolder(folder)
            }
        }
        
        rescanDebounceTimers[folderPath] = timer
    }
    
    private func findWatchedFolder(for filePath: String) -> String? {
        // Find the watched folder that contains this file
        for watchedPath in eventMonitors.keys {
            if filePath.hasPrefix(watchedPath) {
                return watchedPath
            }
        }
        return nil
    }
    
    private func rescanFolder(_ folder: Folder) {
        guard let databaseManager = databaseManager else { return }
        
        Logger.info("Auto-rescanning folder: \(folder.name)")
        
        Task {
            do {
                try await databaseManager.rescanFolder(folder)
                await MainActor.run {
                    NotificationManager.shared.addMessage(.info, "Updated '\(folder.name)'")
                }
            } catch {
                Logger.error("Failed to auto-rescan folder \(folder.name): \(error)")
                await MainActor.run {
                    NotificationManager.shared.addMessage(.error, "Failed to update '\(folder.name)'")
                }
            }
        }
    }
    
    private func describeEvent(flags: FSEventStreamEventFlags) -> String {
        var events: [String] = []
        
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated) != 0 {
            events.append("created")
        }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved) != 0 {
            events.append("removed")
        }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed) != 0 {
            events.append("renamed")
        }
        if flags & FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified) != 0 {
            events.append("modified")
        }
        
        return events.isEmpty ? "unknown" : events.joined(separator: ", ")
    }
}

// MARK: - DatabaseManager Extension

extension DatabaseManager {
    /// Get all folders from the database
    func getAllFolders() -> [Folder] {
        do {
            return try dbQueue.read { db in
                try Folder.fetchAll(db)
            }
        } catch {
            Logger.error("Failed to fetch folders: \(error)")
            return []
        }
    }
}

