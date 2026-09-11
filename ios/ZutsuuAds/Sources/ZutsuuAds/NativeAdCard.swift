// /Users/mymac/zutsuu/ios/ZutsuuAds/Sources/ZutsuuAds/NativeAdCard.swift
// インフィードのネイティブ広告（設計書 §8.2 Tier 1）。可視域に入ってからロードし、レイアウトは自前で組む。
// バナーより単価が高く、行の高さを固定できるのでリストがガタつかないため。
// 関連: AdProvider.swift, AdMobProvider.swift
#if canImport(GoogleMobileAds)
import GoogleMobileAds
import SwiftUI
import UIKit

/// リストに 1 枠差し込むネイティブ広告。表示されるまでロードしない。
public struct NativeAdCard: View {
    @State private var loader = NativeAdLoaderBox()
    let isEnabled: Bool

    public init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    public var body: some View {
        Group {
            if let ad = loader.ad {
                NativeAdViewRepresentable(ad: ad)
                    .frame(height: 96)
                    .accessibilityLabel(Text("広告", bundle: .module))
            } else {
                Color.clear.frame(height: 0)
            }
        }
        .onAppear { if isEnabled { loader.loadIfNeeded() } }
    }
}

@MainActor @Observable
final class NativeAdLoaderBox: NSObject, NativeAdLoaderDelegate {
    private(set) var ad: NativeAd?
    @ObservationIgnored private var adLoader: AdLoader?

    func loadIfNeeded() {
        guard ad == nil, adLoader == nil else { return }
        let loader = AdLoader(adUnitID: AdUnitIDs.native, rootViewController: AdMobProvider.rootViewController,
                              adTypes: [.native], options: nil)
        loader.delegate = self
        adLoader = loader
        loader.load(Request())
    }

    nonisolated func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        Task { @MainActor in self.ad = nativeAd }
    }

    nonisolated func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        Task { @MainActor in self.adLoader = nil }
    }
}

struct NativeAdViewRepresentable: UIViewRepresentable {
    let ad: NativeAd

    func makeUIView(context: Context) -> NativeAdView {
        let view = NativeAdView()
        let headline = UILabel()
        headline.font = .preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
        headline.numberOfLines = 1
        let body = UILabel()
        body.font = .preferredFont(forTextStyle: .footnote)
        body.textColor = .secondaryLabel
        body.numberOfLines = 2
        let badge = UILabel()
        badge.text = String(localized: "広告", bundle: .module)
        badge.font = .preferredFont(forTextStyle: .caption2)
        badge.textColor = .secondaryLabel
        let icon = UIImageView()
        icon.contentMode = .scaleAspectFill
        icon.clipsToBounds = true
        icon.layer.cornerRadius = 8
        let cta = UIButton(type: .system)
        cta.titleLabel?.font = .preferredFont(forTextStyle: .footnote).withWeight(.semibold)
        cta.isUserInteractionEnabled = false

        let text = UIStackView(arrangedSubviews: [headline, body, badge])
        text.axis = .vertical
        text.spacing = 2
        let row = UIStackView(arrangedSubviews: [icon, text, cta])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(row)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 48),
            icon.heightAnchor.constraint(equalToConstant: 48),
            row.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            row.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            row.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
        ])
        view.headlineView = headline
        view.bodyView = body
        view.iconView = icon
        view.callToActionView = cta
        return view
    }

    func updateUIView(_ view: NativeAdView, context: Context) {
        (view.headlineView as? UILabel)?.text = ad.headline
        (view.bodyView as? UILabel)?.text = ad.body
        (view.iconView as? UIImageView)?.image = ad.icon?.image
        (view.callToActionView as? UIButton)?.setTitle(ad.callToAction, for: .normal)
        view.nativeAd = ad
    }
}

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        UIFont.systemFont(ofSize: pointSize, weight: weight)
    }
}
#endif
