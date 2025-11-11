import SwiftUI

enum BannerType {
    case success, error, info
    
    var background: Color {
        switch self {
        case .success: return Color.green.opacity(0.95)
        case .error:   return Color.red.opacity(0.95)
        case .info:    return Color.blue.opacity(0.95)
        }
    }
    
    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error:   return "xmark.octagon.fill"
        case .info:    return "info.circle.fill"
        }
    }
}

struct Banner: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let type: BannerType
}

private struct BannerView: View {
    let banner: Banner
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: banner.type.icon).imageScale(.large)
            Text(banner.message).font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(banner.type.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .foregroundStyle(.white)
        .shadow(radius: 10, y: 6)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
}

struct BannerPresenter: ViewModifier {
    @Binding var banner: Banner?
    let autoHide: Bool
    let duration: Double
    
    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content
            if let b = banner {
                BannerView(banner: b)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        let gen = UINotificationFeedbackGenerator()
                        gen.notificationOccurred(b.type == .error ? .error : .success)
                        
                        if autoHide {
                            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                                withAnimation(.spring()) { banner = nil }
                            }
                        }
                    }
                    .zIndex(1)
                    .onTapGesture {
                        withAnimation(.spring()) { banner = nil }
                    }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.9), value: banner)
    }
}

extension View {
    func banner(_ banner: Binding<Banner?>, autoHide: Bool = true, duration: Double = 2.5) -> some View {
        modifier(BannerPresenter(banner: banner, autoHide: autoHide, duration: duration))
    }
}

enum BannerAction {
    @MainActor
    static func showSuccess(_ message: String, banner: Binding<Banner?>) {
        banner.wrappedValue = Banner(message: message, type: .success)
    }
    @MainActor
    static func showError(_ message: String, banner: Binding<Banner?>) {
        banner.wrappedValue = Banner(message: message, type: .error)
    }
    @MainActor
    static func showInfo(_ message: String, banner: Binding<Banner?>) {
        banner.wrappedValue = Banner(message: message, type: .info)
    }

    @MainActor
    static func showSuccessAndDismiss(
        _ message: String,
        banner: Binding<Banner?>,
        dismiss: DismissAction,
        delay: Double = 2.0
    ) async {
        banner.wrappedValue = Banner(message: message, type: .success)
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        dismiss()
    }

    @MainActor
    static func showSuccessThen(
        _ message: String,
        banner: Binding<Banner?>,
        delay: Double = 2.0,
        _ action: @escaping () -> Void
    ) async {
        banner.wrappedValue = Banner(message: message, type: .success)
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        action()
    }
}
