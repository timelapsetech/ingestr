import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = RenameViewModel()
    @Environment(\.colorScheme) var colorScheme
    
    /// Tooltip copy for Auto Rename / Auto Split (also used for VoiceOver hints).
    private enum RenameTooltip {
        static let autoRename =
            "Uses image metadata (such as EXIF capture date) from the first image in each sequence to determine that sequence's date, then builds folder and file names from it—for example the dated sequence folder pattern."
        static let autoSplit =
            "When Auto Rename is on: detects breaks in image sequence cadence—intervals between shots much larger than the usual spacing—and starts a new sequence automatically."
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 15) {
                // App Title and Tagline
                VStack(spacing: 2) {
                    Text("Ingestr")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Ingest and organize image sequences.")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)
                
                // Ingest mode: sequence (existing behavior) vs photo (date folders + timestamp names)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Ingest mode")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 8) {
                        IngestModeRow(
                            title: IngestMode.sequence.title,
                            subtitle: "Group images into sequences with numbered dated folders.",
                            isSelected: viewModel.ingestMode == .sequence,
                            tooltip: IngestMode.sequenceHelp
                        ) {
                            viewModel.ingestMode = .sequence
                        }
                        IngestModeRow(
                            title: IngestMode.photo.title,
                            subtitle: "No sequences—each file under Year/Month/Day with a timestamp name.",
                            isSelected: viewModel.ingestMode == .photo,
                            tooltip: IngestMode.photoHelp
                        ) {
                            viewModel.ingestMode = .photo
                        }
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.gray.opacity(0.1))
                )
                
                // Source Directory Section
                DirectoryDropZone(
                    title: "Source Directory",
                    subtitle: "Drag a folder here, or click to choose",
                    isTargeted: $viewModel.isSourceTargeted,
                    onDrop: viewModel.handleSourceDrop,
                    onSelectFolder: viewModel.selectSourceFolder,
                    selectedPath: viewModel.sourceURL?.path
                )
                
                // File Filters Section
                HStack {
                    Text("File Extension:")
                        .font(.headline)
                    TextField("ext", text: $viewModel.extensionFilter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("(leave empty for all files)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                
                // Combined Options Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Rename Options")
                        .font(.headline)

                    // Native `.help` on `Toggle` often never appears on macOS. Show the same text via `Image`+`.help`
                    // (reliable) and mirror it with `accessibilityHint` on the toggle for VoiceOver.
                    HStack(alignment: .center, spacing: 12) {
                        HStack(spacing: 6) {
                            Toggle("Auto Rename", isOn: $viewModel.autoRename)
                                .disabled(viewModel.ingestMode == .photo)
                                .accessibilityHint(RenameTooltip.autoRename)
                            RenameHelpTipIcon(tooltip: RenameTooltip.autoRename)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: 6) {
                            Toggle("Auto Split", isOn: $viewModel.autoSplit)
                                .disabled(!viewModel.autoRename || viewModel.ingestMode == .photo)
                                .accessibilityHint(RenameTooltip.autoSplit)
                            RenameHelpTipIcon(tooltip: RenameTooltip.autoSplit)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Toggle("Add to Existing", isOn: $viewModel.addToExisting)
                        .disabled(viewModel.ingestMode == .photo)

                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Number Padding")
                                .font(.subheadline)
                            Stepper(value: $viewModel.numberPadding, in: 1...10) {
                                Text("\(viewModel.numberPadding) digits")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Start Number")
                                .font(.subheadline)
                            HStack(spacing: 6) {
                                TextField("", value: $viewModel.startNumber, formatter: NumberFormatter())
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 64)
                                Stepper("", value: $viewModel.startNumber, in: 1...999999) { _ in }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .disabled(viewModel.ingestMode == .photo)

                    // Base Name
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Base Name:")
                            TextField("Enter base name", text: $viewModel.basename)
                                .textFieldStyle(.roundedBorder)
                                .disabled(viewModel.autoRename || viewModel.ingestMode == .photo)
                        }
                    }

                    ZStack(alignment: .leading) {
                        Picker("Copy verification", selection: $viewModel.copyVerificationMode) {
                            ForEach(CopyVerificationMode.allCases) { mode in
                                Text(mode.menuTitle).tag(mode)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .help("Defaults to full checks, but select \"Size only\" or no verification for faster copies")
                    Text("Defaults to Full—streaming copy plus byte-for-byte verification (slower on huge batches). Choose Size only or None for faster copies with lighter or no checks. Your choice is saved.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.gray.opacity(0.1))
                )
                
                // Output Directory Section (always shown)
                DirectoryDropZone(
                    title: "Output Directory",
                    subtitle: "Drag a folder here, or click to choose",
                    isTargeted: $viewModel.isOutputTargeted,
                    onDrop: viewModel.handleOutputDrop,
                    onSelectFolder: viewModel.selectOutputFolder,
                    selectedPath: viewModel.outputURL?.path
                )
                .overlay(alignment: .topTrailing) {
                    if viewModel.outputURL != nil {
                        Button(action: {
                            viewModel.outputURL = nil
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                    }
                }
                
                // Progress Section
                if viewModel.isProcessing {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Ingesting")
                                .font(.headline)
                            Spacer(minLength: 8)
                            Text("\(Int(min(1.0, viewModel.progress) * 100))%")
                                .font(.headline.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                        ProgressView(value: min(1.0, viewModel.progress), total: 1.0)
                            .progressViewStyle(.linear)
                        Text(viewModel.progressDetail.isEmpty ? "Starting…" : viewModel.progressDetail)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding()
                    .accessibilityElement(children: .combine)
                }
                
                // Action Buttons
                HStack {
                    Button("Start Ingesting") {
                        viewModel.startRenaming()
                    }
                    .disabled(!viewModel.canStartRenaming)
                    .buttonStyle(.borderedProminent)
                    
                    Button("Cancel") {
                        viewModel.cancelRenaming()
                    }
                    .disabled(!viewModel.isProcessing)
                    .buttonStyle(.bordered)
                }
                .padding()
                
                Spacer(minLength: 20)
            }
            .padding(.horizontal)
        }
        .frame(minWidth: 400, maxWidth: 450, minHeight: 760)
        .background(colorScheme == .dark ? Color.black : Color.white)
        .onAppear {
            // Reset URL on app launch
            viewModel.resetSourceURLIfNeeded()
        }
        .onChange(of: viewModel.shouldResetSourceURL) { _ in
            // Reset URL when flag changes
            viewModel.resetSourceURLIfNeeded()
        }
        .alert("Ingest Complete", isPresented: $viewModel.showCompletionAlert) {
            Button("Open Folder") {
                viewModel.openCompletionFolder()
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.completionMessage)
        }
    }
}

/// SF Symbol + `.help` shows native macOS tooltips reliably (unlike `Toggle` + `.help`).
private struct RenameHelpTipIcon: View {
    let tooltip: String
    
    var body: some View {
        Image(systemName: "info.circle")
            .font(.callout)
            .foregroundStyle(.secondary)
            .help(tooltip)
            .accessibilityHidden(true)
    }
}

private struct IngestModeRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let tooltip: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .imageScale(.large)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    ContentView()
} 