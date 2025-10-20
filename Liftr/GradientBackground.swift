import SwiftUI

struct GradientBackground<Content: View>: View {
  private let content: Content?
  init(@ViewBuilder content: () -> Content) { self.content = content() }
  init() where Content == EmptyView { self.content = nil }

  var body: some View {
    ZStack {
      LinearGradient(colors: [.mint.opacity(0.6), .blue.opacity(0.5)],
                     startPoint: .topLeading, endPoint: .bottomTrailing)
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
