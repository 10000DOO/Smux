import SwiftUI

struct PlaceholderSurfaceView: View {
    var title: String
    var systemImage: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
            Text(title)
                .font(.headline)
        }
    }
}
