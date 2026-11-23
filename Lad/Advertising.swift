import SwiftUI
import GoogleMobileAds
import UserMessagingPlatform

@MainActor final class AdvertisingService: ObservableObject {
    static let shared = AdvertisingService()
    @Published private(set) var canShowBanner = false
    @Published private(set) var privacyOptionsRequired = false
    private var started = false

    var bannerID: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "LadAdMobBannerID") as? String,
              value.hasPrefix("ca-app-pub-"), value.contains("/") else { return nil }
        #if !DEBUG
        if value.contains("3940256099942544") { return nil }
        #endif
        return value
    }

    func prepare() async {
        guard !started, AppPurchases.shared.shouldShowAds, bannerID != nil,
              let appID = Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String,
              appID.hasPrefix("ca-app-pub-"), appID.contains("~"),
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              !ProcessInfo.processInfo.arguments.contains("--screenshots") else { return }
        #if !DEBUG
        guard !appID.contains("3940256099942544") else { return }
        #endif
        started = true
        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters())
            try await ConsentForm.loadAndPresentIfRequired(from: nil)
            privacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
            guard ConsentInformation.shared.canRequestAds, AppPurchases.shared.shouldShowAds else { return }
            MobileAds.shared.requestConfiguration.maxAdContentRating = .general
            _ = await MobileAds.shared.start()
            canShowBanner = true
        } catch { started = false }
    }

    func privacyOptions() async {
        try? await ConsentForm.presentPrivacyOptionsForm(from: nil)
        canShowBanner = ConsentInformation.shared.canRequestAds
    }
}

struct CatalogAdvertisement: View {
    @ObservedObject private var purchases = AppPurchases.shared
    @ObservedObject private var ads = AdvertisingService.shared
    @State private var loaded = false
    @State private var bannerHeight: CGFloat = 60
    var body: some View {
        Group {
            if purchases.shouldShowAds, ads.canShowBanner, let id = ads.bannerID {
                GeometryReader { proxy in
                    AdMobBanner(id: id, width: proxy.size.width, loaded: $loaded, height: $bannerHeight)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }.frame(height: loaded ? bannerHeight : 0)
                    .background(Palette.canvas)
                    .accessibilityLabel(L10n.text("Реклама"))
            }
        }.task(id: purchases.shouldShowAds) {
            if purchases.shouldShowAds { await ads.prepare() }
        }
    }
}

private struct AdMobBanner: UIViewRepresentable {
    let id: String
    let width: CGFloat
    @Binding var loaded: Bool
    @Binding var height: CGFloat
    func makeCoordinator() -> Coordinator { Coordinator(loaded: $loaded, height: $height) }
    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: largeAnchoredAdaptiveBanner(width: max(1, width)))
        banner.adUnitID = id
        banner.rootViewController = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController
        banner.delegate = context.coordinator
        let request = Request()
        let extras = Extras()
        extras.additionalParameters = ["npa": "1"]
        request.register(extras)
        // No profile, weight, food diary, dietary goals or recipe names are
        // provided to the advertising SDK. Requests are non-personalized.
        banner.load(request)
        return banner
    }
    func updateUIView(_ view: BannerView, context: Context) { }
    static func dismantleUIView(_ view: BannerView, coordinator: Coordinator) { view.delegate = nil }
    final class Coordinator: NSObject, BannerViewDelegate {
        @Binding var loaded: Bool
        @Binding var height: CGFloat
        init(loaded: Binding<Bool>, height: Binding<CGFloat>) { _loaded = loaded; _height = height }
        func bannerViewDidReceiveAd(_ bannerView: BannerView) { height = bannerView.adSize.size.height; loaded = true }
        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) { loaded = false }
    }
}
