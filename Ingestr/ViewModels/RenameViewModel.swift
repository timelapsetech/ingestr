import SwiftUI
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
    
    // Constants for auto-split
    private let defaultGapThreshold: TimeInterval = 60 // 1 minute
    private let minImagesForGapDetection: Int = 3 // Minimum images needed to detect normal interval
    private let minSequenceSize: Int = 10 // Minimum number of images to consider a sequence
    
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
        sourceURL != nil && outputURL != nil
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
        isProcessing = true
        progress = 0
        currentOperation = Task {
            do {
                let fileManager = FileManager.default
                let enumerator = fileManager.enumerator(at: sourceURL,
                                                      includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                                                      options: [.skipsHiddenFiles])
                var totalFiles = 0
                var processedFiles = 0
                var filesToProcess: [(url: URL, date: Date)] = []
                var hasExtras = false
                var firstYear: Int?
                
                // First collect all files to process
                while let fileURL = enumerator?.nextObject() as? URL {
                    if shouldProcessFile(fileURL) {
                        let fileDate = getEffectiveDate(from: fileURL)
                        filesToProcess.append((fileURL, fileDate))
                        totalFiles += 1
                    }
                }
                
                if totalFiles == 0 {
                    await MainActor.run {
                        isProcessing = false
                        progress = 0
                        shouldResetSourceURL = true
                    }
                    return
                }
                
                // Sort files by date
                filesToProcess.sort { $0.date < $1.date }
                
                // Determine sequence breaks if auto-split is enabled
                var sequenceBreaks: [Int] = [0]
                if autoSplit {
                    if let normalInterval = detectNormalInterval(in: filesToProcess) {
                        sequenceBreaks = findSequenceBreaks(in: filesToProcess, normalInterval: normalInterval)
                    }
                }
                
                // Process each sequence
                for i in 0..<sequenceBreaks.count {
                    if Task.isCancelled { break }
                    
                    let startIndex = sequenceBreaks[i]
                    let endIndex = i < sequenceBreaks.count - 1 ? sequenceBreaks[i + 1] : filesToProcess.count
                    let sequenceFiles = Array(filesToProcess[startIndex..<endIndex])
                    
                    // Skip small sequences
                    if sequenceFiles.count < minSequenceSize {
                        hasExtras = true
                        continue
                    }
                    
                    try await processSequence(sequenceFiles, in: outputURL)
                    processedFiles += sequenceFiles.count
                    
                    let progressValue = min(Double(processedFiles) / Double(totalFiles), 1.0)
                    await MainActor.run {
                        progress = progressValue
                    }
                }
                
                // Set completion message and folder URL
                await MainActor.run {
                    if hasExtras {
                        completionMessage = "Extra files were found not matching any sequence. Check the Extras folder."
                        if let year = firstYear {
                            completionFolderURL = outputURL.appendingPathComponent("\(year)/Extras")
                        }
                    } else if let year = firstYear {
                        completionMessage = "Ingest has completed successfully to the \(year) folder"
                        completionFolderURL = outputURL.appendingPathComponent("\(year)")
                    }
                    showCompletionAlert = true
                    shouldResetSourceURL = true
                }
            } catch {
                print("Error during renaming: \(error)")
            }
            await MainActor.run {
                isProcessing = false
                progress = 0
            }
        }
    }
    
    func cancelRenaming() {
        currentOperation?.cancel()
        isProcessing = false
        progress = 0
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
        if let url = completionFolderURL {
            NSWorkspace.shared.open(url)
        }
    }
    
    // Handles copying and numbering for a sequence, supporting addToExisting logic
    private func processSequence(_ sequenceFiles: [(url: URL, date: Date)], in outputURL: URL) async throws {
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
            try fileManager.copyItem(at: fileURL, to: destinationURL)
            currentNumber += 1
            if idx == 0 { sequenceFolderURL = baseFolderURL }
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
    }
} 