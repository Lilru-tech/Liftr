import SwiftUI

struct GradientBackground<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    ZStack {
      // 👇 Tu degradado base
      LinearGradient(
        colors: [.mint.opacity(0.15), .blue.opacity(0.1)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .ignoresSafeArea()

      content
    }
  }
}
