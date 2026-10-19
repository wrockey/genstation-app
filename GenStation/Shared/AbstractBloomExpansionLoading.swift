import SwiftUI
struct AbstractBloomExpansionLoading: View {
    @State private var scale: CGFloat = 0.1
    @State private var opacity: Double = 1.0
    @State private var rotation: Double = 0.0
    @Environment(\.colorScheme) var colorScheme: ColorScheme
    var body: some View {
        ZStack {
            ForEach(0..<5) { index in
                Circle()
                    .fill(LinearGradient(gradient: Gradient(colors: colorScheme == .dark ? [Color.indigo, Color.blue] : [Color.indigo, Color.blue]), startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 50 + CGFloat(index * 25), height: 50 + CGFloat(index * 25))
                    .opacity(opacity - Double(index) * 0.2)
                    .scaleEffect(scale)
                    .rotationEffect(.degrees(rotation))
                    .blendMode(colorScheme == .dark ? .screen : .multiply) // Switch blend mode based on scheme
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                scale = 1.0
                opacity = 0.5
            }
            withAnimation(.linear(duration: 5).repeatForever(autoreverses: false)) {
                rotation = 360.0
            }
        }
    }
}
