import SwiftUI

struct GradientBackground<Content: View>: View {
    @AppStorage("backgroundTheme") private var backgroundTheme: String = "mintBlue"
    
    private let content: Content?
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    init() where Content == EmptyView { self.content = nil }
    
    private var gradientColors: [Color] {
        switch backgroundTheme {
        case "sunset":
            return [Color.orange.opacity(0.6), Color.pink.opacity(0.55)]
        case "forest":
            return [Color.green.opacity(0.55), Color.teal.opacity(0.55)]
        case "midnight":
            return [Color.black.opacity(0.9), Color.blue.opacity(0.7)]
        case "lavender":
            return [Color.purple.opacity(0.45), Color.blue.opacity(0.45)]
        case "ocean":
            return [Color.cyan.opacity(0.55), Color.blue.opacity(0.55)]
        case "rose":
            return [Color.pink.opacity(0.55), Color.purple.opacity(0.45)]
        case "desert":
            return [Color.yellow.opacity(0.45), Color.orange.opacity(0.40)]
        case "berry":
            return [Color.red.opacity(0.45), Color.indigo.opacity(0.55)]
        case "mono":
            return [Color.gray.opacity(0.55), Color.black.opacity(0.55)]

        default:
            return [Color.mint.opacity(0.6), Color.blue.opacity(0.5)]
        }
    }
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            if let content { content }
        }
    }
}

struct GradientBG: ViewModifier {
    func body(content: Content) -> some View {
        ZStack {
            GradientBackground().ignoresSafeArea()
            content
        }
    }
}

extension View {
    func gradientBG() -> some View { modifier(GradientBG()) }
}
