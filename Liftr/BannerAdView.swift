import SwiftUI
import GoogleMobileAds
import os

private let bannerAdLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Liftr", category: "BannerAd")

struct BannerAdView: UIViewRepresentable {
    let adUnitID: String

    func makeCoordinator() -> Coordinator {
        Coordinator(adUnitID: adUnitID)
    }

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = adUnitID
        banner.delegate = context.coordinator
        context.coordinator.banner = banner
        banner.backgroundColor = .clear
        Self.syncRootViewControllerAndLoadIfNeeded(for: banner)
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {
        context.coordinator.banner = uiView
        Self.syncRootViewControllerAndLoadIfNeeded(for: uiView)
    }

    static func dismantleUIView(_ uiView: BannerView, coordinator: Coordinator) {
        coordinator.banner = nil
        uiView.delegate = nil
    }

    private static func syncRootViewControllerAndLoadIfNeeded(for banner: BannerView) {
        guard let root = bestRootViewController(for: banner) else {
            bannerAdLogger.warning("No rootViewController resolved; skip load")
            return
        }
        if banner.rootViewController !== root {
            bannerAdLogger.debug("Updating banner rootViewController → \(String(describing: type(of: root)), privacy: .public)")
            banner.rootViewController = root
            banner.load(Request())
        }
    }

    private static func bestRootViewController(for banner: UIView) -> UIViewController? {
        if let vc = banner.liftrNearestViewController() {
            return vc
        }
        return liftrKeyWindowRootViewController()
    }

    private static func liftrKeyWindowRootViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let key = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
        if let root = key?.rootViewController { return root }
        return scenes.first?.windows.first(where: { $0.rootViewController != nil })?.rootViewController
    }

    final class Coordinator: NSObject, BannerViewDelegate {
        let adUnitID: String
        weak var banner: BannerView?

        init(adUnitID: String) {
            self.adUnitID = adUnitID
        }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            bannerView.isHidden = false
            bannerAdLogger.info("didReceiveAd adUnit=\(self.adUnitID, privacy: .public)")
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            bannerAdLogger.error("didFailToReceiveAd adUnit=\(self.adUnitID, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
        }

        func bannerViewDidRecordImpression(_ bannerView: BannerView) {
            bannerAdLogger.debug("didRecordImpression adUnit=\(self.adUnitID, privacy: .public)")
        }
    }
}

private extension UIView {
    func liftrNearestViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let vc = current as? UIViewController {
                return vc
            }
            responder = current.next
        }
        return nil
    }
}
