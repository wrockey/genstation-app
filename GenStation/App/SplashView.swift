import SwiftUI

struct SplashView: View {
    @State private var scale: CGFloat = 0.3
    @State private var opacity: Double = 1.0
    @State private var rotation: Double = 0.0
    @State private var textGlow: CGFloat = 0.0
    @State private var particleOffset: CGFloat = 0.0
    @Environment(\.colorScheme) var colorScheme: ColorScheme
    @Environment(\.horizontalSizeClass) var sizeClass: UserInterfaceSizeClass?

    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color(white: 0.05)
    }

    private var neonGradient: LinearGradient {
        LinearGradient(gradient: Gradient(colors: [Color.cyan.opacity(0.7), Color.blue.opacity(0.9)]), startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var softGradient: LinearGradient {
        LinearGradient(gradient: Gradient(colors: [Color.blue.opacity(0.5), Color.purple.opacity(0.6)]), startPoint: .top, endPoint: .bottom)
    }

    private var fontSize: CGFloat {
        sizeClass == .compact ? 32 : 68
    }

    var body: some View {
        ZStack {
            // Background with subtle grid lines
            backgroundColor
                .overlay(
                    GridBackgroundView(particleOffset: particleOffset)
                )
                .ignoresSafeArea()

            // Expanding circles with orbiting particles
            ZStack {
                // Core blooming circles
                CircleLayerView(scale: scale, opacity: opacity, rotation: rotation, neonGradient: neonGradient, softGradient: softGradient)
                
                // Orbiting particles
//                ParticleLayerView(scale: scale, rotation: rotation)
            }
            .blur(radius: 8)

            // Holographic app name
            HolographicTextView(text: "GenStation", fontSize: fontSize, scale: scale, opacity: opacity, textGlow: textGlow)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8)) {
                scale = 1.0
                opacity = 0.5
            }
            withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) {
                rotation = 360.0
            }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                textGlow = 8.0
            }
            withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
                particleOffset = 20.0
            }
        }
    }
}

// Extracted grid background
struct GridBackgroundView: View {
    let particleOffset: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Grid lines
                Path { path in
                    let width = geometry.size.width
                    let height = geometry.size.height
                    for i in stride(from: 0, to: width, by: 50) {
                        path.move(to: CGPoint(x: i, y: 0))
                        path.addLine(to: CGPoint(x: i, y: height))
                    }
                    for i in stride(from: 0, to: height, by: 50) {
                        path.move(to: CGPoint(x: 0, y: i))
                        path.addLine(to: CGPoint(x: width, y: i))
                    }
                }
                .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
                .offset(x: particleOffset, y: 0)
                
                // Copyright — tiny, elegant, bottom-right
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("© 2025–2026 William Rockey")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.35))
                            .padding(.trailing, 16)
                            .padding(.bottom, 12)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

// Extracted circle layer
struct CircleLayerView: View {
    let scale: CGFloat
    let opacity: Double
    let rotation: Double
    let neonGradient: LinearGradient
    let softGradient: LinearGradient

    var body: some View {
        ForEach(0..<5) { index in
            Circle()
                .fill(index % 2 == 0 ? neonGradient : softGradient)
                .frame(width: 100 + CGFloat(index * 50), height: 100 + CGFloat(index * 50))
                .opacity(opacity - Double(index) * 0.1)
                .scaleEffect(scale)
                .rotationEffect(.degrees(rotation + Double(index * 45)))
                .blendMode(.plusLighter)
        }
    }
}

// Extracted holographic text
struct HolographicTextView: View {
    let text: String
    let fontSize: CGFloat
    let scale: CGFloat
    let opacity: Double
    let textGlow: CGFloat

    private var textGradient: LinearGradient {
        LinearGradient(gradient: Gradient(colors: [Color.cyan, Color.white, Color.blue]), startPoint: .leading, endPoint: .trailing)
    }

    var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .semibold, design: .rounded))
            .foregroundStyle(textGradient)
            .shadow(color: Color.cyan.opacity(0.6), radius: textGlow, x: 0, y: 0)
            .shadow(color: Color.blue.opacity(0.4), radius: textGlow * 1.5, x: 0, y: 0)
            .scaleEffect(scale * 1.1)
            .opacity(opacity)
            .padding(24)
    }
}

struct SplashView_Previews: PreviewProvider {
    static var previews: some View {
        SplashView()
            .preferredColorScheme(.dark)
    }
}
