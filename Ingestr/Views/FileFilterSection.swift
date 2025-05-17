import SwiftUI

// This file is kept to prevent build errors but is no longer used - replaced with the text field in ContentView
struct FileFilterSection: View {
    @Binding var filters: [String]
    
    var body: some View {
        EmptyView()
    }
}

#Preview {
    FileFilterSection(filters: .constant([]))
} 