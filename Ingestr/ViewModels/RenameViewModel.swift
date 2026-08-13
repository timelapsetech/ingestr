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
        "Example output:\n\(IngestMode.sequenceOutputExample)\n\nEach folder under the source is ingested separately. Auto Split starts a new sequence when the gap between shots differs from the typical cadence by more than the Variation % (default 10%). Sets with fewer than 10 images go to Extras."
    
    /// Tooltip for photo mode (flat date hierarchy + timestamp filenames).
    static let photoHelp =
        "Example output:\n\(IngestMode.photoOutputExample)\n\nDoes not group sequences. Each file goes under Year/Month/Day and is renamed to its capture date, time, and milliseconds."
}

private enum IngestModeUserDefaults {
    static let key = "ingestMode"
}

private enum AutoSplitVariationUserDefaults {
    static let key = "autoSplitVariationPercent"
    static let defaultPercent = 10
    static let allowedRange = 1...1000
}

private enum DirectoryBookmarkKey {
    static let output = "outputDirectoryBookmark"
    static let source = "sourceDirectoryBookmark"
}

class RenameViewModel: ObservableObject {
    @Published var sourceURL: URL? {
        didSet {
            if let url = sourceURL {
                DirectoryBookmark.captureUserSelectedDirectory(url, key: DirectoryBookmarkKey.source)
            } else {
                DirectoryBookmark.clear(key: DirectoryBookmarkKey.source)
            }
        }
    }
    @Published var outputURL: URL? {
        didSet {
            if let url = outputURL {
                DirectoryBookmark.captureUserSelectedDirectory(url, key: DirectoryBookmarkKey.output)
            } else {
                DirectoryBookmark.clear(key: DirectoryBookmarkKey.output)
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
    /// How far a gap may differ from typical cadence before Auto Split starts a new sequence (default 10%).
    @Published var autoSplitVariationPercent: Int = AutoSplitVariationUserDefaults.defaultPercent {
        didSet {
            let clamped = min(
                max(autoSplitVariationPercent, AutoSplitVariationUserDefaults.allowedRange.lowerBound),
                AutoSplitVariationUserDefaults.allowedRange.upperBound
            )
            if clamped != autoSplitVariationPercent {
                autoSplitVariationPercent = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: AutoSplitVariationUserDefaults.key)
        }
    }
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
    
    // Constants for auto-split cadence detection
    /// When estimating shot cadence, ignore gaps longer than this (they are session breaks, not frame spacing).
    private let maxCadenceSample: TimeInterval = 180
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
            _ = url.startAccessingSecurityScopedResource()
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
    
    /// Parses the numeric index from a sequence folder name such as `202505041CO` or `2025050412CO`.
    func parseSequenceIndex(fromFolderName folderName: String, datePrefix: String) -> Int? {
        guard folderName.hasPrefix(datePrefix), folderName.hasSuffix("CO") else { return nil }
        let indexPart = folderName.dropFirst(datePrefix.count).dropLast(2)
        guard !indexPart.isEmpty, indexPart.allSatisfy(\.isNumber) else { return nil }
        return Int(indexPart)
    }
    
    private func highestSequenceIndexOnDisk(for dateString: String, year: Int, in outputURL: URL) -> Int {
        let fileManager = FileManager.default
        let yearFolder = outputURL.appendingPathComponent("\(year)")
        guard fileManager.fileExists(atPath: yearFolder.path),
              let contents = try? fileManager.contentsOfDirectory(at: yearFolder, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return 0
        }
        return contents.compactMap { url -> Int? in
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return nil
            }
            return parseSequenceIndex(fromFolderName: url.lastPathComponent, datePrefix: dateString)
        }.max() ?? 0
    }
    
    /// Next `N` for `YYYYMMDDNCO_`, considering existing output folders and sequences already created in this run.
    private func getNextSequenceNumber(
        for date: Date,
        in outputURL: URL,
        assignedInRun: inout [String: Int]
    ) -> Int {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let dateString = formatter.string(from: date)
        let year = Calendar.current.component(.year, from: date)
        let runKey = "\(year)-\(dateString)"
        
        let maxOnDisk = highestSequenceIndexOnDisk(for: dateString, year: year, in: outputURL)
        let maxInRun = assignedInRun[runKey] ?? 0
        let next = max(maxOnDisk, maxInRun) + 1
        assignedInRun[runKey] = next
        return next
    }
    
    /// Parent path of a file relative to the source root (e.g. `ShootA` or `ShootA/nested`). Empty for files at the source root.
    func sourceRelativeGroupKey(for fileURL: URL, sourceRoot: URL) -> String {
        let rootPath = sourceRoot.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath) else { return "" }
        var relative = String(filePath.dropFirst(rootPath.count))
        if relative.hasPrefix("/") {
            relative = String(relative.dropFirst())
        }
        return (relative as NSString).deletingLastPathComponent
    }
    
    /// Groups files by their folder under the source root so each shoot folder is split and ingested independently.
    func groupFilesBySourceFolder(
        _ files: [(url: URL, date: Date)],
        sourceRoot: URL
    ) -> [String: [(url: URL, date: Date)]] {
        var groups: [String: [(url: URL, date: Date)]] = [:]
        for file in files {
            let key = sourceRelativeGroupKey(for: file.url, sourceRoot: sourceRoot)
            groups[key, default: []].append(file)
        }
        return groups
    }
    
    func detectNormalInterval(in files: [(url: URL, date: Date)]) -> TimeInterval? {
        guard files.count >= minImagesForGapDetection else { return nil }
        
        var intervals: [TimeInterval] = []
        for i in 1..<files.count {
            let interval = files[i].date.timeIntervalSince(files[i-1].date)
            // Sample only within-shoot spacing (roughly 3–120s, with headroom), not session-length gaps.
            if interval > 0 && interval <= maxCadenceSample {
                intervals.append(interval)
            }
        }
        
        let sortedIntervals = intervals.sorted()
        guard !sortedIntervals.isEmpty else { return nil }
        let medianIndex = sortedIntervals.count / 2
        return sortedIntervals[medianIndex]
    }
    
    /// Absolute seconds a gap may differ from `normalInterval` before a split (Variation %).
    func sequenceSplitAllowedDeviation(for normalInterval: TimeInterval, variationPercent: Int) -> TimeInterval {
        let percent = Double(
            min(
                max(variationPercent, AutoSplitVariationUserDefaults.allowedRange.lowerBound),
                AutoSplitVariationUserDefaults.allowedRange.upperBound
            )
        )
        return normalInterval * (percent / 100.0)
    }
    
    /// Starts a new sequence when a gap differs from typical cadence by ≥ Variation % (faster or slower).
    func findSequenceBreaks(
        in files: [(url: URL, date: Date)],
        normalInterval: TimeInterval,
        variationPercent: Int = AutoSplitVariationUserDefaults.defaultPercent
    ) -> [Int] {
        var breaks: [Int] = [0]
        let allowedDeviation = sequenceSplitAllowedDeviation(
            for: normalInterval,
            variationPercent: variationPercent
        )
        
        for i in 1..<files.count {
            let interval = files[i].date.timeIntervalSince(files[i-1].date)
            if abs(interval - normalInterval) >= allowedDeviation {
                breaks.append(i)
            }
        }
        
        return breaks
    }
    
    func startRenaming() {
        guard let sourceStored = sourceURL, let outputStored = outputURL else { return }
        let verificationMode = copyVerificationMode
        isProcessing = true
        progress = 0
        progressDetail = "Listing files…"
        // Run off the main actor so enumeration and copies don't block UI updates (ProgressView would stay at 0%).
        currentOperation = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let sourceURL = DirectoryBookmark.resolve(stored: sourceStored, key: DirectoryBookmarkKey.source) ?? sourceStored
            let outputURL = DirectoryBookmark.resolve(stored: outputStored, key: DirectoryBookmarkKey.output) ?? outputStored
            let accessingSource = DirectoryBookmark.beginAccess(to: sourceURL)
            let accessingOutput = DirectoryBookmark.beginAccess(to: outputURL)
            defer {
                if accessingSource {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
                if accessingOutput {
                    outputURL.stopAccessingSecurityScopedResource()
                }
            }
            await Task.yield()
            if !accessingSource {
                await MainActor.run {
                    self.completionMessage = IngestFilesystemError.sourceAccessDenied(sourceURL).localizedDescription
                    self.completionFolderURL = nil
                    self.showCompletionAlert = true
                    self.isProcessing = false
                    self.progress = 0
                    self.progressDetail = ""
                }
                return
            }
            if !accessingOutput {
                await MainActor.run {
                    self.completionMessage = IngestFilesystemError.outputAccessDenied(outputURL).localizedDescription
                    self.completionFolderURL = nil
                    self.showCompletionAlert = true
                    self.isProcessing = false
                    self.progress = 0
                    self.progressDetail = ""
                }
                return
            }
            do {
                try DirectoryBookmark.verifyCanWrite(to: outputURL)
                let fileManager = FileManager.default
                let enumerator = fileManager.enumerator(at: sourceURL,
                                                      includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                                                      options: [.skipsHiddenFiles])
                var filesToProcess: [(url: URL, date: Date)] = []
                var hasExtras = false
                var firstYear: Int?
                
                // Pass 1: collect matching file URLs (fast — no EXIF yet) so we know N for accurate progress
                var candidateURLs: [URL] = []
                let extensionFilter = await MainActor.run { self.extensionFilter }
                while let fileURL = enumerator?.nextObject() as? URL {
                    if IngestFileFilter.isIngestible(
                        url: fileURL,
                        relativeTo: sourceURL,
                        extensionFilter: extensionFilter
                    ) {
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
                    let latestRevealFolder = try await self.processPhotoModeFiles(
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
                            self.completionFolderURL = latestRevealFolder
                                ?? outputURL.appendingPathComponent("\(year)")
                        } else {
                            self.completionMessage = "Ingest finished."
                            self.completionFolderURL = latestRevealFolder ?? outputURL
                        }
                        self.showCompletionAlert = true
                        self.shouldResetSourceURL = true
                    }
                } else {
                    await MainActor.run {
                        self.progressDetail = "Preparing sequences…"
                    }
                    
                    var filesCopied = 0
                    var latestRevealFolder: URL?
                    let wCopy = Self.copyProgressWeight
                    var didProcessFullSequence = false
                    var assignedSequenceNumbers: [String: Int] = [:]
                    func updateRevealFolder(_ folder: URL?) {
                        if let folder { latestRevealFolder = folder }
                    }
                    
                    // Each folder under the source is ingested as its own timeline (then auto-split within it).
                    let shootGroups = self.groupFilesBySourceFolder(filesToProcess, sourceRoot: sourceURL)
                    let orderedGroupKeys = shootGroups.keys.sorted { lhs, rhs in
                        let lhsDate = shootGroups[lhs]!.map(\.date).min()!
                        let rhsDate = shootGroups[rhs]!.map(\.date).min()!
                        if lhsDate != rhsDate { return lhsDate < rhsDate }
                        return lhs < rhs
                    }
                    
                    for groupKey in orderedGroupKeys {
                        if Task.isCancelled { break }
                        
                        var groupFiles = shootGroups[groupKey]!
                        groupFiles.sort { $0.date < $1.date }
                        
                        var sequenceBreaks: [Int] = [0]
                        if self.autoSplit {
                            if let normalInterval = self.detectNormalInterval(in: groupFiles) {
                                sequenceBreaks = self.findSequenceBreaks(
                                    in: groupFiles,
                                    normalInterval: normalInterval,
                                    variationPercent: self.autoSplitVariationPercent
                                )
                            }
                        }
                        
                        for i in 0..<sequenceBreaks.count {
                            if Task.isCancelled { break }
                            
                            let startIndex = sequenceBreaks[i]
                            let endIndex = i < sequenceBreaks.count - 1 ? sequenceBreaks[i + 1] : groupFiles.count
                            let sequenceFiles = Array(groupFiles[startIndex..<endIndex])
                            
                            if sequenceFiles.count < self.minSequenceSize {
                                hasExtras = true
                                let extrasFolder = try await self.copySmallSequenceToExtras(
                                    sequenceFiles,
                                    in: outputURL,
                                    totalFileCount: totalFileCount,
                                    filesCopied: &filesCopied,
                                    wMeta: wMeta,
                                    wCopy: wCopy,
                                    verificationMode: verificationMode
                                )
                                updateRevealFolder(extrasFolder)
                                continue
                            }
                            
                            let sequenceFolder = try await self.processSequence(
                                sequenceFiles,
                                in: outputURL,
                                totalFileCount: totalFileCount,
                                filesCopied: &filesCopied,
                                wMeta: wMeta,
                                wCopy: wCopy,
                                verificationMode: verificationMode,
                                assignedSequenceNumbers: &assignedSequenceNumbers
                            )
                            updateRevealFolder(sequenceFolder)
                            didProcessFullSequence = true
                        }
                    }
                    
                    // Set completion message and folder URL
                    let yearForCompletion = firstYear
                    let hasExtrasSnapshot = hasExtras
                    let didProcessFullSequenceSnapshot = didProcessFullSequence
                    let revealFolderForCompletion = latestRevealFolder
                    await MainActor.run {
                        guard let year = yearForCompletion else {
                            self.completionMessage = "Ingest finished."
                            self.completionFolderURL = nil
                            self.showCompletionAlert = true
                            self.shouldResetSourceURL = true
                            return
                        }
                        let yearFolder = outputURL.appendingPathComponent("\(year)", isDirectory: true)
                        let extrasFolder = yearFolder.appendingPathComponent("Extras", isDirectory: true)
                        if hasExtrasSnapshot && didProcessFullSequenceSnapshot {
                            self.completionMessage = "Ingest finished. Full sequences are in dated folders; sets with fewer than \(self.minSequenceSize) images are in Extras."
                            self.completionFolderURL = revealFolderForCompletion ?? yearFolder
                        } else if hasExtrasSnapshot {
                            self.completionMessage = "Files were copied to Extras (each sequence had fewer than \(self.minSequenceSize) images)."
                            self.completionFolderURL = revealFolderForCompletion ?? extrasFolder
                        } else {
                            self.completionMessage = "Ingest has completed successfully to the \(year) folder"
                            self.completionFolderURL = revealFolderForCompletion ?? yearFolder
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
        let preferred = completionFolderURL ?? outputURL
        guard let preferred else { return }
        let outputRoot = DirectoryBookmark.resolve(stored: outputURL, key: DirectoryBookmarkKey.output) ?? outputURL

        // Ingest releases scoped access when the background task ends; reopen via the output bookmark.
        let accessingOutput = outputRoot.map { DirectoryBookmark.beginAccess(to: $0) } ?? false
        defer {
            if accessingOutput, let outputRoot {
                outputRoot.stopAccessingSecurityScopedResource()
            }
        }

        guard let urlToReveal = Self.resolvedDirectoryForFinder(preferred: preferred, outputRoot: outputRoot) else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([urlToReveal])
    }

    /// Picks the best on-disk folder to reveal in Finder (must be under the user-selected output).
    private static func resolvedDirectoryForFinder(preferred: URL, outputRoot: URL?) -> URL? {
        let fm = FileManager.default
        let candidates = [preferred, outputRoot].compactMap { $0?.standardizedFileURL }
        for url in candidates {
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return url
            }
        }
        return preferred.standardizedFileURL
    }
    
    /// Copies files from short sequences into `Output/YYYY/Extras/` using `yyyyMMdd-HHmmss` names (README).
    @discardableResult
    private func copySmallSequenceToExtras(
        _ sequenceFiles: [(url: URL, date: Date)],
        in outputURL: URL,
        totalFileCount: Int,
        filesCopied: inout Int,
        wMeta: Double,
        wCopy: Double,
        verificationMode: CopyVerificationMode
    ) async throws -> URL? {
        let fileManager = FileManager.default
        var lastExtrasFolder: URL?
        for fileInfo in sequenceFiles {
            if Task.isCancelled { break }
            let fileDate = fileInfo.date
            let year = Calendar.current.component(.year, from: fileDate)
            let extrasFolder = outputURL
                .appendingPathComponent("\(year)", isDirectory: true)
                .appendingPathComponent("Extras", isDirectory: true)
            try DirectoryBookmark.createDirectory(at: extrasFolder, outputRoot: outputURL, label: "the Extras folder")
            lastExtrasFolder = extrasFolder
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
        return lastExtrasFolder
    }
    
    // Handles copying and numbering for a sequence, supporting addToExisting logic
    @discardableResult
    private func processSequence(
        _ sequenceFiles: [(url: URL, date: Date)],
        in outputURL: URL,
        totalFileCount: Int,
        filesCopied: inout Int,
        wMeta: Double,
        wCopy: Double,
        verificationMode: CopyVerificationMode,
        assignedSequenceNumbers: inout [String: Int]
    ) async throws -> URL? {
        let fileManager = FileManager.default
        var effectiveBasename = basename
        var sequenceNumber = 1
        var effectivePadding = numberPadding
        var currentNumber = startNumber

        if autoRename {
            let firstFileDate = sequenceFiles[0].date
            sequenceNumber = getNextSequenceNumber(for: firstFileDate, in: outputURL, assignedInRun: &assignedSequenceNumbers)
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

        var sequenceFolderURL: URL?
        for fileInfo in sequenceFiles {
            if Task.isCancelled { break }
            let fileURL = fileInfo.url
            let fileDate = fileInfo.date
            let year = Calendar.current.component(.year, from: fileDate)
            let baseFolder = effectiveBasename.hasSuffix("_") ? String(effectiveBasename.dropLast()) : effectiveBasename
            let yearFolder = outputURL.appendingPathComponent("\(year)", isDirectory: true)
            let baseFolderURL = yearFolder.appendingPathComponent(baseFolder, isDirectory: true)
            try DirectoryBookmark.createDirectory(at: baseFolderURL, outputRoot: outputURL, label: "the sequence folder")
            sequenceFolderURL = baseFolderURL
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
            filesCopied += 1
            let copiedCount = filesCopied
            let p = wMeta + wCopy * Double(copiedCount) / Double(max(totalFileCount, 1))
            await MainActor.run {
                self.progress = min(1.0, p)
                self.progressDetail = "Copying \(copiedCount) / \(totalFileCount): → \(writtenName)"
            }
        }
        return sequenceFolderURL
    }
    
    init() {
        if let restoredOutput = DirectoryBookmark.restore(key: DirectoryBookmarkKey.output) {
            outputURL = restoredOutput
        } else if let legacyPath = UserDefaults.standard.string(forKey: "lastOutputDirectory") {
            outputURL = URL(fileURLWithPath: legacyPath)
        }
        if let restoredSource = DirectoryBookmark.restore(key: DirectoryBookmarkKey.source) {
            sourceURL = restoredSource
        }
        if let raw = UserDefaults.standard.string(forKey: CopyVerificationMode.userDefaultsKey),
           let mode = CopyVerificationMode(rawValue: raw) {
            copyVerificationMode = mode
        }
        if let raw = UserDefaults.standard.string(forKey: IngestModeUserDefaults.key),
           let mode = IngestMode(rawValue: raw) {
            ingestMode = mode
        }
        let storedVariation = UserDefaults.standard.object(forKey: AutoSplitVariationUserDefaults.key) as? Int
            ?? AutoSplitVariationUserDefaults.defaultPercent
        autoSplitVariationPercent = min(
            max(storedVariation, AutoSplitVariationUserDefaults.allowedRange.lowerBound),
            AutoSplitVariationUserDefaults.allowedRange.upperBound
        )
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
    @discardableResult
    private func processPhotoModeFiles(
        _ files: [(url: URL, date: Date)],
        in outputURL: URL,
        totalFileCount: Int,
        filesCopied: inout Int,
        wMeta: Double,
        wCopy: Double,
        verificationMode: CopyVerificationMode
    ) async throws -> URL? {
        let fileManager = FileManager.default
        let calendar = Calendar.current
        var lastDayFolder: URL?
        
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
                .appendingPathComponent("\(year)", isDirectory: true)
                .appendingPathComponent(monthStr, isDirectory: true)
                .appendingPathComponent(dayStr, isDirectory: true)
            try DirectoryBookmark.createDirectory(at: dayFolder, outputRoot: outputURL, label: "the date folder")
            lastDayFolder = dayFolder
            
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
        return lastDayFolder
    }
} 