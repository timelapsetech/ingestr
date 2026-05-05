import SwiftUI
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum NonSequentialPattern: String, CaseIterable {
    case dateTime
    case random
    
    var displayName: String {
        switch self {
        case .dateTime: return "Date & Time"
        case .random: return "Random"
        }
    }
}

/// Controls whether ingest groups files into sequences or treats each file independently (photo layout).
enum IngestMode: String, CaseIterable, Identifiable {
    case sequence
    case photo
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .sequence: return "Sequence mode"
        case .photo: return "Photo mode"
        }
    }
    
    /// Shown in UI copy as an example path (matches real auto-rename folder/file prefixes; tooltip prose avoids spelling out this suffix).
    static let sequenceOutputExample =
        "Output/2025/202505041CO_/202505041CO_0001.jpg"
    
    static let photoOutputExample =
        "Output/2025/05/04/2025-05-04-143052-847.jpg"
    
    /// Tooltip for sequence mode (full ingest behavior).
    static let sequenceHelp =
        "Example output:\n\(IngestMode.sequenceOutputExample)\n\nDetects sequences by capture time, splits on gaps when enabled, and moves small sets to Extras."
    
    /// Tooltip for photo mode (flat date hierarchy + timestamp filenames).
    static let photoHelp =
        "Example output:\n\(IngestMode.photoOutputExample)\n\nDoes not group sequences. Each file goes under Year/Month/Day and is renamed to its capture date, time, and milliseconds."
}

private enum IngestModeUserDefaults {
    static let key = "ingestMode"
}

class RenameViewModel: ObservableObject {
    @Published var sourceURL: URL?
    @Published var outputURL: URL? {
        didSet {
            if let url = outputURL {
                UserDefaults.standard.set(url.path, forKey: "lastOutputDirectory")
            }
        }
    }
    @Published var basename: String = ""
    @Published var numberPadding: Int = 4
    @Published var startNumber: Int = 1
    @Published var isProcessing: Bool = false
    @Published var progress: Double = 0
    /// Current step description, e.g. "Reading metadata 4 / 1200: IMG_001.jpg"
    @Published var progressDetail: String = ""
    @Published var isSourceTargeted: Bool = false
    @Published var isOutputTargeted: Bool = false
    @Published var extensionFilter: String = ""
    @Published var shouldResetSourceURL: Bool = false
    @Published var autoRename: Bool = false
    @Published var autoSplit: Bool = false
    @Published var addToExisting: Bool = false
    @Published var showCompletionAlert: Bool = false
    @Published var completionMessage: String = ""
    @Published var completionFolderURL: URL?
    /// After-ingest copy check. Default is **Full**; **None** matches legacy `copyItem`-only behavior.
    @Published var copyVerificationMode: CopyVerificationMode = .full {
        didSet {
            UserDefaults.standard.set(copyVerificationMode.rawValue, forKey: CopyVerificationMode.userDefaultsKey)
        }
    }
    
    /// Sequence mode preserves existing behavior; photo mode uses Year/Month/Day folders and timestamp filenames only.
    @Published var ingestMode: IngestMode = .sequence {
        didSet {
            UserDefaults.standard.set(ingestMode.rawValue, forKey: IngestModeUserDefaults.key)
        }
    }
    
    // Constants for auto-split
    private let defaultGapThreshold: TimeInterval = 60 // 1 minute
    private let minImagesForGapDetection: Int = 3 // Minimum images needed to detect normal interval
    private let minSequenceSize: Int = 10 // Minimum number of images to consider a sequence
    /// Share of the bar used while reading EXIF/metadata (rest is copy).
    private static let metadataProgressWeight: Double = 0.38
    private static var copyProgressWeight: Double { 1.0 - metadataProgressWeight }
    
    // Rename mode
    @Published var sequentialMode: Bool = true
    
    // Non-sequential options
    @Published var nonSequentialPattern: NonSequentialPattern = .dateTime
    @Published var randomNameLength: Int = 8
    
    // Track which naming scheme is being used
    @Published var isUsingDatePattern: Bool = false
    @Published var showingDateInfo: Bool = false
    
    // Presets for base name patterns
    let presets = [
        "TimelapseSequence": "Time Lapse Sequence",
        "DateSequence": "Date Sequence (YYYYMMDD_)",
        "IMG_": "Simple (IMG_)",
        "Photo_": "Photo_",
        "Scan_": "Scan_"
    ]
    
    private var currentOperation: Task<Void, Never>?
    private var usedRandomNames = Set<String>()
    
    var canStartRenaming: Bool {
        sourceURL != nil && outputURL != nil && !isProcessing
    }
    
    func selectPreset(_ key: String) {
        if key == "TimelapseSequence" {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd"
            basename = formatter.string(from: Date()) + "1CO_"
            showingDateInfo = true
        } else if key == "DateSequence" {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd"
            basename = formatter.string(from: Date()) + "_"
            showingDateInfo = true
        } else {
            basename = key
            showingDateInfo = false
        }
    }
    
    func handleSourceDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier("public.file-url") {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { (urlData, error) in
                DispatchQueue.main.async {
                    if let urlData = urlData as? Data,
                       let url = NSURL(dataRepresentation: urlData, relativeTo: nil) as URL? {
                        self.sourceURL = url
                    }
                }
            }
            return true
        }
        return false
    }
    
    func handleOutputDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier("public.file-url") {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { (urlData, error) in
                DispatchQueue.main.async {
                    if let urlData = urlData as? Data,
                       let url = NSURL(dataRepresentation: urlData, relativeTo: nil) as URL? {
                        self.outputURL = url
                    }
                }
            }
            return true
        }
        return false
    }
    
    func selectSourceFolder() {
        presentFolderPicker { self.sourceURL = $0 }
    }
    
    func selectOutputFolder() {
        presentFolderPicker { self.outputURL = $0 }
    }
    
    private func presentFolderPicker(onPicked: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Choose Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            DispatchQueue.main.async {
                onPicked(url)
            }
        }
        
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }
    
    // Improved: Find last sequence number for files matching 'basename + zero-padded number + .ext'
    func findLastSequenceNumber(in folderURL: URL, baseName: String) -> (lastNumber: Int, padding: Int)? {
        do {
            let fileManager = FileManager.default
            let contents = try fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
            // Match files like baseName + zero-padded number + .ext (e.g., 200704161CO_0599.jpg)
            let regexPattern = "^" + NSRegularExpression.escapedPattern(for: baseName) + "(\\d+)\\.[^.]+$"
            let regex = try NSRegularExpression(pattern: regexPattern)
            var maxNumber = 0
            var maxPadding = 0
            for url in contents {
                let fileName = url.lastPathComponent
                if let match = regex.firstMatch(in: fileName, range: NSRange(location: 0, length: fileName.utf16.count)),
                   let numberRange = Range(match.range(at: 1), in: fileName) {
                    let numberStr = String(fileName[numberRange])
                    if let number = Int(numberStr) {
                        if number > maxNumber {
                            maxNumber = number
                            maxPadding = numberStr.count
                        }
                    }
                }
            }
            if maxNumber == 0 { return nil }
            return (maxNumber, maxPadding)
        } catch {
            print("Error finding last sequence number: \(error)")
            return nil
        }
    }
    
    private func getNextSequenceNumber(for date: Date, in outputURL: URL) -> Int {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let dateString = formatter.string(from: date)
        
        do {
            let fileManager = FileManager.default
            let year = Calendar.current.component(.year, from: date)
            let yearFolder = outputURL.appendingPathComponent("\(year)")
            
            // Check if year folder exists
            guard fileManager.fileExists(atPath: yearFolder.path) else {
                return 1
            }
            
            // Get all folders in the year directory
            let contents = try fileManager.contentsOfDirectory(at: yearFolder, includingPropertiesForKeys: nil)
            
            // Filter for folders matching the pattern YYYYMMDDXCO
            let sequenceFolders = contents.filter { url in
                let folderName = url.lastPathComponent
                return folderName.hasPrefix(dateString) && 
                       folderName.hasSuffix("CO") &&
                       folderName.count == dateString.count + 3 // YYYYMMDD + X + CO
            }
            
            if sequenceFolders.isEmpty {
                return 1
            }
            
            // Extract sequence numbers and find the highest
            let sequenceNumbers = sequenceFolders.compactMap { url -> Int? in
                let folderName = url.lastPathComponent
                let startIndex = folderName.index(folderName.startIndex, offsetBy: dateString.count)
                let endIndex = folderName.index(folderName.endIndex, offsetBy: -2) // Remove "CO"
                let numberStr = String(folderName[startIndex..<endIndex])
                return Int(numberStr)
            }
            
            return (sequenceNumbers.max() ?? 0) + 1
        } catch {
            print("Error checking sequence numbers: \(error)")
            return 1
        }
    }
    
    private func detectNormalInterval(in files: [(url: URL, date: Date)]) -> TimeInterval? {
        guard files.count >= minImagesForGapDetection else { return nil }
        
        var intervals: [TimeInterval] = []
        for i in 1..<files.count {
            let interval = files[i].date.timeIntervalSince(files[i-1].date)
            if interval > 0 && interval < defaultGapThreshold * 2 { // Only consider reasonable intervals
                intervals.append(interval)
            }
        }
        
        // Calculate median interval
        let sortedIntervals = intervals.sorted()
        guard !sortedIntervals.isEmpty else { return nil }
        let medianIndex = sortedIntervals.count / 2
        return sortedIntervals[medianIndex]
    }
    
    private func findSequenceBreaks(in files: [(url: URL, date: Date)], normalInterval: TimeInterval) -> [Int] {
        var breaks: [Int] = [0] // Start with first file
        let gapThreshold = normalInterval * 3 // Consider it a break if gap is 3x normal interval
        
        for i in 1..<files.count {
            let interval = files[i].date.timeIntervalSince(files[i-1].date)
            if interval > gapThreshold {
                breaks.append(i)
            }
        }
        
        return breaks
    }
    
    func startRenaming() {
        guard let sourceURL = sourceURL, let outputURL = outputURL else { return }
        let verificationMode = copyVerificationMode
        isProcessing = true
        progress = 0
        progressDetail = "Listing files…"
        // Run off the main actor so enumeration and copies don't block UI updates (ProgressView would stay at 0%).
        currentOperation = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let accessingSource = sourceURL.startAccessingSecurityScopedResource()
            let accessingOutput = outputURL.startAccessingSecurityScopedResource()
            defer {
                if accessingSource {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
                if accessingOutput {
                    outputURL.stopAccessingSecurityScopedResource()
                }
            }
            await Task.yield()
            do {
                let fileManager = FileManager.default
                let enumerator = fileManager.enumerator(at: sourceURL,
                                                      includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                                                      options: [.skipsHiddenFiles])
                var filesToProcess: [(url: URL, date: Date)] = []
                var hasExtras = false
                var firstYear: Int?
                
                // Pass 1: collect matching file URLs (fast — no EXIF yet) so we know N for accurate progress
                var candidateURLs: [URL] = []
                while let fileURL = enumerator?.nextObject() as? URL {
                    if self.shouldProcessFile(fileURL) {
                        candidateURLs.append(fileURL)
                    }
                }
                let totalFileCount = candidateURLs.count
                
                if totalFileCount == 0 {
                    await MainActor.run {
                        self.completionMessage = "No files were found to process. Check the extension filter, folder access, and try choosing the folders again (drag them onto the drop zones)."
                        self.completionFolderURL = nil
                        self.showCompletionAlert = true
                        self.isProcessing = false
                        self.progress = 0
                        self.progressDetail = ""
                        self.shouldResetSourceURL = true
                    }
                    return
                }
                
                // Pass 2: read dates / metadata — linear progress 0 … metadataProgressWeight
                let wMeta = Self.metadataProgressWeight
                filesToProcess.reserveCapacity(totalFileCount)
                for (idx, fileURL) in candidateURLs.enumerated() {
                    if Task.isCancelled { break }
                    let fileDate = self.getEffectiveDate(from: fileURL)
                    filesToProcess.append((fileURL, fileDate))
                    let done = idx + 1
                    await MainActor.run {
                        let p = wMeta * Double(done) / Double(totalFileCount)
                        self.progress = min(1.0, p)
                        self.progressDetail = "Reading metadata \(done) / \(totalFileCount): \(fileURL.lastPathComponent)"
                    }
                }
                
                // Sort files by date
                filesToProcess.sort { $0.date < $1.date }
                let derivedYear = Calendar.current.component(.year, from: filesToProcess[0].date)
                firstYear = derivedYear
                
                let mode = await MainActor.run { self.ingestMode }
                
                if mode == .photo {
                    await MainActor.run {
                        self.progressDetail = "Copying into date folders…"
                    }
                    var filesCopied = 0
                    let wCopy = Self.copyProgressWeight
                    try await self.processPhotoModeFiles(
                        filesToProcess,
                        in: outputURL,
                        totalFileCount: totalFileCount,
                        filesCopied: &filesCopied,
                        wMeta: wMeta,
                        wCopy: wCopy,
                        verificationMode: verificationMode
                    )
                    let yearForCompletion = firstYear
                    await MainActor.run {
                        if let year = yearForCompletion {
                            self.completionMessage = "Ingest finished. Files were organized under Year/Month/Day with timestamp names (see the \(year) folder)."
                            self.completionFolderURL = outputURL.appendingPathComponent("\(year)")
                        } else {
                            self.completionMessage = "Ingest finished."
                            self.completionFolderURL = outputURL
                        }
                        self.showCompletionAlert = true
                        self.shouldResetSourceURL = true
                    }
                } else {
                    await MainActor.run {
                        self.progressDetail = "Preparing sequences…"
                    }
                    
                    // Determine sequence breaks if auto-split is enabled
                    var sequenceBreaks: [Int] = [0]
                    if self.autoSplit {
                        if let normalInterval = self.detectNormalInterval(in: filesToProcess) {
                            sequenceBreaks = self.findSequenceBreaks(in: filesToProcess, normalInterval: normalInterval)
                        }
                    }
                    
                    // Copy phase: linear progress metadataWeight … 1.0, updated after each file copied
                    var filesCopied = 0
                    let wCopy = Self.copyProgressWeight
                    
                    // Process each sequence
                    var didProcessFullSequence = false
                    for i in 0..<sequenceBreaks.count {
                        if Task.isCancelled { break }
                        
                        let startIndex = sequenceBreaks[i]
                        let endIndex = i < sequenceBreaks.count - 1 ? sequenceBreaks[i + 1] : filesToProcess.count
                        let sequenceFiles = Array(filesToProcess[startIndex..<endIndex])
                        
                        // Sequences smaller than min size go to Extras (see README)
                        if sequenceFiles.count < self.minSequenceSize {
                            hasExtras = true
                            try await self.copySmallSequenceToExtras(sequenceFiles, in: outputURL, totalFileCount: totalFileCount, filesCopied: &filesCopied, wMeta: wMeta, wCopy: wCopy, verificationMode: verificationMode)
                            continue
                        }
                        
                        try await self.processSequence(sequenceFiles, in: outputURL, totalFileCount: totalFileCount, filesCopied: &filesCopied, wMeta: wMeta, wCopy: wCopy, verificationMode: verificationMode)
                        didProcessFullSequence = true
                    }
                    
                    // Set completion message and folder URL
                    let yearForCompletion = firstYear
                    let hasExtrasSnapshot = hasExtras
                    let didProcessFullSequenceSnapshot = didProcessFullSequence
                    await MainActor.run {
                        guard let year = yearForCompletion else {
                            self.completionMessage = "Ingest finished."
                            self.completionFolderURL = nil
                            self.showCompletionAlert = true
                            self.shouldResetSourceURL = true
                            return
                        }
                        if hasExtrasSnapshot && didProcessFullSequenceSnapshot {
                            self.completionMessage = "Ingest finished. Full sequences are in dated folders; sets with fewer than \(self.minSequenceSize) images are in Extras."
                            self.completionFolderURL = outputURL.appendingPathComponent("\(year)/Extras")
                        } else if hasExtrasSnapshot {
                            self.completionMessage = "Files were copied to Extras (each sequence had fewer than \(self.minSequenceSize) images)."
                            self.completionFolderURL = outputURL.appendingPathComponent("\(year)/Extras")
                        } else {
                            self.completionMessage = "Ingest has completed successfully to the \(year) folder"
                            self.completionFolderURL = outputURL.appendingPathComponent("\(year)")
                        }
                        self.showCompletionAlert = true
                        self.shouldResetSourceURL = true
                    }
                }
            } catch {
                print("Error during renaming: \(error)")
                await MainActor.run {
                    self.completionMessage = "Ingest failed: \(error.localizedDescription)"
                    self.completionFolderURL = nil
                    self.showCompletionAlert = true
                    self.progressDetail = ""
                }
            }
            await MainActor.run {
                self.isProcessing = false
                self.progress = 0
                self.progressDetail = ""
            }
        }
    }
    
    func cancelRenaming() {
        currentOperation?.cancel()
        isProcessing = false
        progress = 0
        progressDetail = ""
    }
    
    private func shouldProcessFile(_ url: URL) -> Bool {
        // Skip directories, only process files
        do {
            let resourceValues = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard let isRegularFile = resourceValues.isRegularFile, isRegularFile else {
                return false
            }
        } catch {
            return false
        }
        
        // If no extension filter is specified, include all files
        if extensionFilter.isEmpty {
            return true
        }
        
        // Otherwise, match the extension
        let fileExtension = url.pathExtension.lowercased()
        return fileExtension.lowercased() == extensionFilter.lowercased()
    }
    
    // SEQUENTIAL NAMING LOGIC
    func generateNewSequentialName(currentNumber: Int, fileURL: URL) -> String {
        let paddedNumber = String(format: "%0\(numberPadding)d", currentNumber)
        let fileExtension = fileURL.pathExtension
        
        // For date-based patterns, extract the date from the file
        if isUsingDatePattern {
            var datePrefix = ""
            
            // If it's a TimeLapseSequence (with 1CO_) or a DateSequence (with _)
            if basename.hasSuffix("1CO_") || basename.hasSuffix("_") {
                datePrefix = getDatePrefix(from: fileURL)
                
                if basename.hasSuffix("1CO_") {
                    return "\(datePrefix)1CO_\(paddedNumber).\(fileExtension)"
                } else {
                    return "\(datePrefix)_\(paddedNumber).\(fileExtension)"
                }
            }
            
            return "\(basename)\(paddedNumber).\(fileExtension)"
        } else {
            return "\(basename)\(paddedNumber).\(fileExtension)"
        }
    }
    
    // NON-SEQUENTIAL NAMING LOGIC
    private func generateNewNonSequentialName(fileURL: URL) -> String {
        let fileExtension = fileURL.pathExtension
        
        switch nonSequentialPattern {
        case .dateTime:
            return generateDateTimeFileName(fileURL: fileURL)
        case .random:
            return generateRandomFileName(fileExtension: fileExtension)
        }
    }
    
    private func generateDateTimeFileName(fileURL: URL) -> String {
        let fileExtension = fileURL.pathExtension
        let dateTimeString = getDateTimeString(from: fileURL)
        return "\(dateTimeString).\(fileExtension)"
    }
    
    private func generateRandomFileName(fileExtension: String) -> String {
        var randomName: String
        
        // Generate a unique random name
        repeat {
            randomName = generateRandomString(length: randomNameLength)
        } while usedRandomNames.contains(randomName)
        
        // Add to used names to ensure uniqueness
        usedRandomNames.insert(randomName)
        
        return "\(randomName).\(fileExtension)"
    }
    
    private func generateRandomString(length: Int) -> String {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map { _ in chars.randomElement()! })
    }
    
    private func getDateTimeString(from fileURL: URL) -> String {
        let date: Date
        
        // Try to get date from EXIF data first
        if let exifDate = getExifDate(from: fileURL) {
            date = exifDate
        }
        // Try file modification date next
        else if let modDate = getFileModificationDate(from: fileURL) {
            date = modDate
        }
        // Fall back to current date/time
        else {
            date = Date()
        }
        
        // Format as YYYY-MM-DD-HHMMSS-MSS
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let baseString = formatter.string(from: date)
        
        // Add milliseconds for uniqueness
        let milliseconds = Int((date.timeIntervalSince1970.truncatingRemainder(dividingBy: 1)) * 1000)
        return "\(baseString)-\(String(format: "%03d", milliseconds))"
    }
    
    private func getFileModificationDate(from fileURL: URL) -> Date? {
        do {
            let resourceValues = try fileURL.resourceValues(forKeys: [.contentModificationDateKey])
            return resourceValues.contentModificationDate
        } catch {
            print("Error reading file modification date: \(error)")
            return nil
        }
    }
    
    private func getDatePrefix(from fileURL: URL) -> String {
        // Try to get date from EXIF data first (for images)
        if let exifDate = getExifDate(from: fileURL) {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd"
            return formatter.string(from: exifDate)
        }
        
        // Try to get file modification date as fallback
        if let modificationDate = getFileModificationDate(from: fileURL) {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd"
            return formatter.string(from: modificationDate)
        }
        
        // Use current date as final fallback
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: Date())
    }
    
    private func getExifDate(from fileURL: URL) -> Date? {
        // Check if the file is an image type
        let fileExtension = fileURL.pathExtension.lowercased()
        let imageExtensions = ["jpg", "jpeg", "tiff", "heic", "png", "raw", "cr2", "crw", "nef", "arw"]
        
        if !imageExtensions.contains(fileExtension) {
            return nil
        }
        
        guard let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            return nil
        }
        
        guard let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] else {
            return nil
        }
        
        // Try to get EXIF dictionary
        guard let exifDict = imageProperties["{Exif}"] as? [String: Any] else {
            // If no EXIF, try to get the creation date from the main properties
            if let tiffDict = imageProperties["{TIFF}"] as? [String: Any],
               let dateTimeStr = tiffDict["DateTime"] as? String {
                return parseExifDate(dateTimeStr)
            }
            
            return nil
        }
        
        // Check for DateTimeOriginal first (when the image was taken)
        if let dateTimeOriginal = exifDict["DateTimeOriginal"] as? String {
            return parseExifDate(dateTimeOriginal)
        }
        
        // Fallback to DateTime
        if let dateTime = exifDict["DateTime"] as? String {
            return parseExifDate(dateTime)
        }
        
        return nil
    }
    
    private func parseExifDate(_ dateString: String) -> Date? {
        // EXIF dates are typically in format: "YYYY:MM:DD HH:MM:SS"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: dateString)
    }
    
    func resetSourceURLIfNeeded() {
        if shouldResetSourceURL {
            sourceURL = nil
            shouldResetSourceURL = false
        }
    }
    
    // Add a helper method to get the effective date for a file
    private func getEffectiveDate(from fileURL: URL) -> Date {
        // Try to get date from EXIF data first (for images)
        if let exifDate = getExifDate(from: fileURL) {
            return exifDate
        }
        
        // Try to get file modification date as fallback
        if let modificationDate = getFileModificationDate(from: fileURL) {
            return modificationDate
        }
        
        // Use current date as final fallback
        return Date()
    }
    
    func openCompletionFolder() {
        guard let folder = completionFolderURL else { return }
        
        // Ingest ends with `stopAccessingSecurityScopedResource()` on the output URL. App Sandbox
        // requires scoped access again before `NSWorkspace` can open paths under a user-selected folder.
        let accessingOutput = outputURL?.startAccessingSecurityScopedResource() ?? false
        let accessingFolder = folder.startAccessingSecurityScopedResource()
        defer {
            if accessingFolder {
                folder.stopAccessingSecurityScopedResource()
            }
            if accessingOutput {
                outputURL?.stopAccessingSecurityScopedResource()
            }
        }
        
        let fm = FileManager.default
        var urlToOpen = folder
        if !fm.fileExists(atPath: urlToOpen.path), let output = outputURL, fm.fileExists(atPath: output.path) {
            urlToOpen = output
        }
        
        if NSWorkspace.shared.open(urlToOpen) {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([urlToOpen])
    }
    
    /// Copies files from short sequences into `Output/YYYY/Extras/` using `yyyyMMdd-HHmmss` names (README).
    private func copySmallSequenceToExtras(
        _ sequenceFiles: [(url: URL, date: Date)],
        in outputURL: URL,
        totalFileCount: Int,
        filesCopied: inout Int,
        wMeta: Double,
        wCopy: Double,
        verificationMode: CopyVerificationMode
    ) async throws {
        let fileManager = FileManager.default
        for fileInfo in sequenceFiles {
            if Task.isCancelled { break }
            let fileDate = fileInfo.date
            let year = Calendar.current.component(.year, from: fileDate)
            let extrasFolder = outputURL
                .appendingPathComponent("\(year)")
                .appendingPathComponent("Extras")
            try fileManager.createDirectory(at: extrasFolder, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let baseName = formatter.string(from: fileDate)
            let ext = fileInfo.url.pathExtension
            var destURL = extrasFolder.appendingPathComponent("\(baseName).\(ext)")
            var collision = 2
            while fileManager.fileExists(atPath: destURL.path) {
                destURL = extrasFolder.appendingPathComponent("\(baseName)_\(collision).\(ext)")
                collision += 1
            }
            let name = destURL.lastPathComponent
            let upcoming = filesCopied + 1
            await MainActor.run {
                self.progressDetail = "Copying \(upcoming) / \(totalFileCount): \(fileInfo.url.lastPathComponent)…"
            }
            try await VerifiedFileCopy.copyWithVerification(from: fileInfo.url, to: destURL, mode: verificationMode)
            filesCopied += 1
            let copiedCount = filesCopied
            let p = wMeta + wCopy * Double(copiedCount) / Double(max(totalFileCount, 1))
            await MainActor.run {
                self.progress = min(1.0, p)
                self.progressDetail = "Copying \(copiedCount) / \(totalFileCount): → \(name)"
            }
        }
    }
    
    // Handles copying and numbering for a sequence, supporting addToExisting logic
    private func processSequence(
        _ sequenceFiles: [(url: URL, date: Date)],
        in outputURL: URL,
        totalFileCount: Int,
        filesCopied: inout Int,
        wMeta: Double,
        wCopy: Double,
        verificationMode: CopyVerificationMode
    ) async throws {
        let fileManager = FileManager.default
        var effectiveBasename = basename
        var sequenceNumber = 1
        var effectivePadding = numberPadding
        var currentNumber = startNumber
        var sequenceFolderURL: URL? = nil

        if autoRename {
            let firstFileDate = sequenceFiles[0].date
            sequenceNumber = getNextSequenceNumber(for: firstFileDate, in: outputURL)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd"
            // Always add underscore after CO for autoRename
            effectiveBasename = formatter.string(from: firstFileDate) + "\(sequenceNumber)CO_"
        }

        // If adding to existing, find the last number and padding
        if addToExisting {
            let year = Calendar.current.component(.year, from: sequenceFiles[0].date)
            let yearFolder = outputURL.appendingPathComponent("\(year)")
            let baseFolder = effectiveBasename.hasSuffix("_") ? String(effectiveBasename.dropLast()) : effectiveBasename
            let baseFolderURL = yearFolder.appendingPathComponent(baseFolder)
            // Always use baseName with trailing underscore for matching
            let matchBaseName = effectiveBasename.hasSuffix("_") ? effectiveBasename : effectiveBasename + "_"
            if let existingInfo = findLastSequenceNumber(in: baseFolderURL, baseName: matchBaseName) {
                currentNumber = existingInfo.lastNumber + 1
                effectivePadding = existingInfo.padding
            }
        }

        for (idx, fileInfo) in sequenceFiles.enumerated() {
            if Task.isCancelled { break }
            let fileURL = fileInfo.url
            let fileDate = fileInfo.date
            let year = Calendar.current.component(.year, from: fileDate)
            let baseFolder = effectiveBasename.hasSuffix("_") ? String(effectiveBasename.dropLast()) : effectiveBasename
            let yearFolder = outputURL.appendingPathComponent("\(year)")
            let baseFolderURL = yearFolder.appendingPathComponent(baseFolder)
            try fileManager.createDirectory(at: baseFolderURL, withIntermediateDirectories: true)
            // Always ensure underscore is present
            let baseNameWithUnderscore = effectiveBasename.hasSuffix("_") ? effectiveBasename : effectiveBasename + "_"
            let paddedNumber = String(format: "%0\(effectivePadding)d", currentNumber)
            let fileExtension = fileURL.pathExtension
            let newName = "\(baseNameWithUnderscore)\(paddedNumber).\(fileExtension)"
            let destinationURL = baseFolderURL.appendingPathComponent(newName)
            let writtenName = destinationURL.lastPathComponent
            let upcoming = filesCopied + 1
            await MainActor.run {
                self.progressDetail = "Copying \(upcoming) / \(totalFileCount): \(fileURL.lastPathComponent)…"
            }
            try await VerifiedFileCopy.copyWithVerification(from: fileURL, to: destinationURL, mode: verificationMode)
            currentNumber += 1
            if idx == 0 { sequenceFolderURL = baseFolderURL }
            filesCopied += 1
            let copiedCount = filesCopied
            let p = wMeta + wCopy * Double(copiedCount) / Double(max(totalFileCount, 1))
            await MainActor.run {
                self.progress = min(1.0, p)
                self.progressDetail = "Copying \(copiedCount) / \(totalFileCount): → \(writtenName)"
            }
        }
        // Set the completion folder to the sequence folder if available
        if let folder = sequenceFolderURL {
            await MainActor.run {
                self.completionFolderURL = folder
            }
        }
    }
    
    init() {
        // Load last output directory from UserDefaults
        if let lastOutputPath = UserDefaults.standard.string(forKey: "lastOutputDirectory") {
            outputURL = URL(fileURLWithPath: lastOutputPath)
        }
        if let raw = UserDefaults.standard.string(forKey: CopyVerificationMode.userDefaultsKey),
           let mode = CopyVerificationMode(rawValue: raw) {
            copyVerificationMode = mode
        }
        if let raw = UserDefaults.standard.string(forKey: IngestModeUserDefaults.key),
           let mode = IngestMode(rawValue: raw) {
            ingestMode = mode
        }
    }
    
    /// Photo mode: `Output/YYYY/MM/DD/yyyy-MM-dd-HHmmss-SSS.ext` (adds `_2`, `_3`, … if the name still collides).
    private func photoModeTimestampBase(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let baseString = formatter.string(from: date)
        let milliseconds = Int((date.timeIntervalSince1970.truncatingRemainder(dividingBy: 1)) * 1000)
        return "\(baseString)-\(String(format: "%03d", milliseconds))"
    }
    
    /// Copies each file into year/month/day folders with a timestamp-based filename (no sequence grouping).
    private func processPhotoModeFiles(
        _ files: [(url: URL, date: Date)],
        in outputURL: URL,
        totalFileCount: Int,
        filesCopied: inout Int,
        wMeta: Double,
        wCopy: Double,
        verificationMode: CopyVerificationMode
    ) async throws {
        let fileManager = FileManager.default
        let calendar = Calendar.current
        
        for fileInfo in files {
            if Task.isCancelled { break }
            let fileURL = fileInfo.url
            let date = fileInfo.date
            let year = calendar.component(.year, from: date)
            let month = calendar.component(.month, from: date)
            let day = calendar.component(.day, from: date)
            let monthStr = String(format: "%02d", month)
            let dayStr = String(format: "%02d", day)
            
            let dayFolder = outputURL
                .appendingPathComponent("\(year)")
                .appendingPathComponent(monthStr)
                .appendingPathComponent(dayStr)
            try fileManager.createDirectory(at: dayFolder, withIntermediateDirectories: true)
            
            let baseStamp = photoModeTimestampBase(from: date)
            let ext = fileURL.pathExtension
            var destURL = dayFolder.appendingPathComponent("\(baseStamp).\(ext)")
            var collision = 2
            while fileManager.fileExists(atPath: destURL.path) {
                destURL = dayFolder.appendingPathComponent("\(baseStamp)_\(collision).\(ext)")
                collision += 1
            }
            let writtenName = destURL.lastPathComponent
            let upcoming = filesCopied + 1
            await MainActor.run {
                self.progressDetail = "Copying \(upcoming) / \(totalFileCount): \(fileURL.lastPathComponent)…"
            }
            try await VerifiedFileCopy.copyWithVerification(from: fileURL, to: destURL, mode: verificationMode)
            filesCopied += 1
            let copiedCount = filesCopied
            let p = wMeta + wCopy * Double(copiedCount) / Double(max(totalFileCount, 1))
            await MainActor.run {
                self.progress = min(1.0, p)
                self.progressDetail = "Copying \(copiedCount) / \(totalFileCount): → \(writtenName)"
            }
        }
    }
} 