import SwiftUI

struct DirectoryDropZone: View {
    let title: String
    let subtitle: String
    @Binding var isTargeted: Bool
    let onDrop: ([NSItemProvider]) -> Bool
    var selectedPath: String?
    
    var body: some View {
        VStack {
            Text(title)
                .font(.headline)
            
            if let path = selectedPath {
                Text(path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(.system(.subheadline, design: .monospaced))
                    .padding(5)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(4)
            } else {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [5]))
                .foregroundColor(isTargeted ? .blue : .gray)
        )
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.1))
        )
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: onDrop)
    }
}

#Preview {
    DirectoryDropZone(
        title: "Test Zone",
        subtitle: "Drop here",
        isTargeted: .constant(false),
        onDrop: { _ in true },
        selectedPath: "/Users/example/Documents"
    )
} 