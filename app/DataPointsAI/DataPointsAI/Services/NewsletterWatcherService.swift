import Foundation
import Combine

/// Service for watching a folder for new .eml files and automatically importing them
/// Uses FSEvents for efficient file system monitoring on macOS
actor NewsletterWatcherService {
    static let shared = NewsletterWatcherService()

    /// The folder being watched (stored in UserDefaults)
    private static let watchFolderKey = "newsletterWatchFolder"

    /// Whether auto-import is enabled
    private static let autoImportEnabledKey = "newsletterAutoImportEnabled"

    /// Whether to auto-summarize imported newsletters
    private static let autoSummarizeKey = "newsletterAutoSummarize"

    /// Whether to delete .eml files after successful import
    private static let deleteAfterImportKey = "newsletterDeleteAfterImport"

    /// Current watch folder URL
    private var watchFolderURL: URL?

    /// FSEvents stream for monitoring
    private var eventStream: FSEventStreamRef?

    /// Files currently being processed (to avoid duplicates)
    private var processingFiles: Set<String> = []

    /// Files that have been processed (to avoid re-importing on restart)
    private var processedFiles: Set<String> = []

    /// Callback for import results
    private var onImportResult: ((ImportResult) -> Void)?

    /// Result of importing a newsletter
    struct ImportResult: Sendable {
        let filename: String
        let success: Bool
        let title: String?
        let error: String?
    }

    private init() {}

    /// Start watching if auto-import is enabled - call this on app launch
    func startWatchingIfEnabled() async {
        if isAutoImportEnabled && watchFolder != nil {
            await startWatching()
        }
    }

    // MARK: - Configuration

    /// Get the current watch folder path
    var watchFolder: URL? {
        get {
            guard let path = UserDefaults.standard.string(forKey: Self.watchFolderKey) else {
                return nil
            }
            return URL(fileURLWithPath: path)
        }
    }

    /// Set the watch folder path
    func setWatchFolder(_ url: URL?) async {
        if let url = url {
            UserDefaults.standard.set(url.path, forKey: Self.watchFolderKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.watchFolderKey)
        }

        // Restart watching if enabled
        if isAutoImportEnabled {
            await stopWatching()
            if url != nil {
                await startWatching()
            }
        }
    }

    /// Check if auto-import is enabled
    var isAutoImportEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.autoImportEnabledKey)
    }

    /// Enable/disable auto-import
    func setAutoImportEnabled(_ enabled: Bool) async {
        UserDefaults.standard.set(enabled, forKey: Self.autoImportEnabledKey)

        if enabled {
            await startWatching()
        } else {
            await stopWatching()
        }
    }

    /// Check if auto-summarize is enabled
    var isAutoSummarizeEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.autoSummarizeKey)
    }

    /// Enable/disable auto-summarize
    func setAutoSummarizeEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.autoSummarizeKey)
    }

    /// Check if delete-after-import is enabled
    var isDeleteAfterImportEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.deleteAfterImportKey)
    }

    /// Enable/disable delete-after-import
    func setDeleteAfterImportEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.deleteAfterImportKey)
    }

    /// Set callback for import results
    func setImportResultCallback(_ callback: @escaping @Sendable (ImportResult) -> Void) {
        self.onImportResult = callback
    }

    // MARK: - Folder Watching

    /// Helper class to bridge FSEvents callback to actor
    private class FSEventContext {
        weak var service: NewsletterWatcherService?
        init(service: NewsletterWatcherService) {
            self.service = service
        }
    }

    /// Stored reference to the context to prevent deallocation
    private var fsEventContext: FSEventContext?

    /// Start watching the configured folder
    func startWatching() async {
        guard eventStream == nil else { return }  // Already watching

        guard let folderURL = watchFolder else {
            print("Newsletter watcher: No folder configured")
            return
        }

        // Ensure folder exists
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            print("Newsletter watcher: Folder does not exist: \(folderURL.path)")
            return
        }

        watchFolderURL = folderURL

        // Process any existing .eml files first
        await processExistingFiles()

        // Set up FSEvents stream with a context wrapper
        let pathsToWatch = [folderURL.path] as CFArray

        // Create context wrapper that holds a reference to self
        let contextWrapper = FSEventContext(service: self)
        fsEventContext = contextWrapper

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(contextWrapper).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, clientCallBackInfo, _, eventPaths, _, _ in
            guard let clientCallBackInfo = clientCallBackInfo else { return }
            let contextWrapper = Unmanaged<FSEventContext>.fromOpaque(clientCallBackInfo).takeUnretainedValue()
            guard let service = contextWrapper.service else { return }

            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as! [String]

            Task {
                await service.handleFSEvents(paths: paths)
            }
        }

        eventStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,  // Reduced latency for faster response
            UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        )

        if let stream = eventStream {
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
            FSEventStreamStart(stream)
            print("Newsletter watcher: Started watching \(folderURL.path)")
        }
    }

    /// Stop watching the folder
    func stopWatching() async {
        guard let stream = eventStream else { return }

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        eventStream = nil
        watchFolderURL = nil
        fsEventContext = nil

        print("Newsletter watcher: Stopped watching")
    }

    /// Handle FSEvents callback
    private func handleFSEvents(paths: [String]) async {
        for path in paths {
            let url = URL(fileURLWithPath: path)

            // Only process .eml files
            guard url.pathExtension.lowercased() == "eml" else { continue }

            // Check if file exists and is not a directory
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else { continue }

            await processEmlFile(at: url)
        }
    }

    /// Process existing .eml files in the watch folder
    private func processExistingFiles() async {
        guard let folderURL = watchFolderURL else { return }

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )

            for url in contents where url.pathExtension.lowercased() == "eml" {
                await processEmlFile(at: url)
            }
        } catch {
            print("Newsletter watcher: Failed to scan folder: \(error)")
        }
    }

    /// Process a single .eml file
    private func processEmlFile(at url: URL) async {
        let filename = url.lastPathComponent

        // Skip if already processing
        guard !processingFiles.contains(filename) else { return }
        processingFiles.insert(filename)

        defer {
            processingFiles.remove(filename)
        }

        print("Newsletter watcher: Processing \(filename)")

        do {
            // Read file data
            let data = try Data(contentsOf: url)

            // Import via API
            let apiClient = await APIClient()
            let response = try await apiClient.importNewsletters(
                files: [(filename: filename, data: data)],
                autoSummarize: isAutoSummarizeEnabled
            )

            // Check result
            if let result = response.results.first {
                if result.success {
                    print("Newsletter watcher: Imported '\(result.title ?? filename)'")

                    // Delete file if configured
                    if isDeleteAfterImportEnabled {
                        try? FileManager.default.removeItem(at: url)
                        print("Newsletter watcher: Deleted \(filename)")
                    }

                    onImportResult?(ImportResult(
                        filename: filename,
                        success: true,
                        title: result.title,
                        error: nil
                    ))
                } else {
                    print("Newsletter watcher: Failed to import \(filename): \(result.error ?? "Unknown error")")

                    onImportResult?(ImportResult(
                        filename: filename,
                        success: false,
                        title: nil,
                        error: result.error
                    ))
                }
            }
        } catch {
            print("Newsletter watcher: Error processing \(filename): \(error)")

            onImportResult?(ImportResult(
                filename: filename,
                success: false,
                title: nil,
                error: error.localizedDescription
            ))
        }
    }

    // MARK: - Manual Import

    /// Manually import .eml files from given URLs
    func importFiles(urls: [URL], autoSummarize: Bool = false) async throws -> [(filename: String, success: Bool, title: String?, error: String?)] {
        var results: [(filename: String, success: Bool, title: String?, error: String?)] = []

        // Prepare file data
        var files: [(filename: String, data: Data)] = []
        for url in urls {
            guard url.pathExtension.lowercased() == "eml" else {
                results.append((url.lastPathComponent, false, nil, "Not an .eml file"))
                continue
            }

            do {
                let data = try Data(contentsOf: url)
                files.append((url.lastPathComponent, data))
            } catch {
                results.append((url.lastPathComponent, false, nil, error.localizedDescription))
            }
        }

        guard !files.isEmpty else {
            return results
        }

        // Import via API
        let apiClient = await APIClient()
        let response = try await apiClient.importNewsletters(
            files: files,
            autoSummarize: autoSummarize
        )

        // Map results back
        for (index, apiResult) in response.results.enumerated() {
            let filename = index < files.count ? files[index].filename : "unknown"
            results.append((
                filename,
                apiResult.success,
                apiResult.title,
                apiResult.error
            ))
        }

        return results
    }

    // MARK: - Suggested Folder

    /// Get the suggested folder for newsletter import
    /// Creates it if it doesn't exist
    static func suggestedWatchFolder() -> URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let oldFolder = documentsURL.appendingPathComponent("DataPointsAI Newsletters", isDirectory: true)
        let newsletterFolder = documentsURL.appendingPathComponent("Data Points AI Newsletters", isDirectory: true)

        // Migrate old folder to new name if it exists
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: oldFolder.path) && !fileManager.fileExists(atPath: newsletterFolder.path) {
            try? fileManager.moveItem(at: oldFolder, to: newsletterFolder)
            print("Migrated newsletter folder from '\(oldFolder.lastPathComponent)' to '\(newsletterFolder.lastPathComponent)'")
        }

        // Create if doesn't exist
        try? fileManager.createDirectory(at: newsletterFolder, withIntermediateDirectories: true)

        return newsletterFolder
    }
}
