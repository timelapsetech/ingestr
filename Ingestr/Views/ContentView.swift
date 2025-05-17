import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = RenameViewModel()
    @Environment(\.colorScheme) var colorScheme
    
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
                
                // Source Directory Section
                DirectoryDropZone(
                    title: "Source Directory",
                    subtitle: "Drag and drop a folder here",
                    isTargeted: $viewModel.isSourceTargeted,
                    onDrop: viewModel.handleSourceDrop,
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

                    // Auto Rename Toggle
                    Toggle("Auto Rename", isOn: $viewModel.autoRename)
                        .padding(.bottom, 5)

                    // Auto Split Toggle
                    Toggle("Auto Split Sequences", isOn: $viewModel.autoSplit)
                        .padding(.bottom, 5)
                        .disabled(!viewModel.autoRename)

                    // Base Name
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Base Name:")
                            TextField("Enter base name", text: $viewModel.basename)
                                .textFieldStyle(.roundedBorder)
                                .disabled(viewModel.autoRename)
                        }
                    }

                    // Number Padding
                    HStack {
                        Text("Number Padding:")
                        Stepper(value: $viewModel.numberPadding, in: 1...10) {
                            Text("\(viewModel.numberPadding) digits")
                        }
                    }

                    // Start Number
                    HStack {
                        Text("Start Number:")
                        TextField("", value: $viewModel.startNumber, formatter: NumberFormatter())
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Stepper("", value: $viewModel.startNumber, in: 1...999999) { _ in }
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.gray.opacity(0.1))
                )
                
                // Output Directory Section (always shown)
                DirectoryDropZone(
                    title: "Output Directory",
                    subtitle: "Drag and drop output folder here",
                    isTargeted: $viewModel.isOutputTargeted,
                    onDrop: viewModel.handleOutputDrop,
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
                    ProgressView(value: viewModel.progress, total: 1.0) {
                        Text("Processing files... \(Int(viewModel.progress * 100))%")
                    }
                    .padding()
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
        .frame(minWidth: 400, maxWidth: 450, minHeight: 640)
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

#Preview {
    ContentView()
} 