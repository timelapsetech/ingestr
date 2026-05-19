import Foundation

enum IngestFilesystemError: LocalizedError {
    case outputAccessDenied(URL)
    case sourceAccessDenied(URL)
    case cannotCreateDirectory(attempted: URL, outputRoot: URL, label: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .outputAccessDenied(let outputRoot):
            return """
            Ingestr cannot write to the output folder:
            \(outputRoot.path)

            Click the Output Directory area and choose this folder again (or pick a different output folder). macOS requires you to grant access through the folder picker.
            """
        case .sourceAccessDenied(let sourceRoot):
            return """
            Ingestr cannot read the source folder:
            \(sourceRoot.path)

            Click the Source Directory area and choose this folder again.
            """
        case .cannotCreateDirectory(let attempted, let outputRoot, let label, let underlying):
            return """
            Could not create \(label) at:
            \(attempted.path)

            Output folder (destination):
            \(outputRoot.path)

            \(underlying.localizedDescription)
            """
        }
    }
}
