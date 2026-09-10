// /Users/mymac/zutsuu/ios/ZutsuuApp/Sources/OnboardingView.swift
// 初回起動の 4 画面: 何のアプリか → 位置情報 → 通知 → 体質申告（任意）。
// 権限を理由と一緒に求め、4 画面・1 画面 1 アイデア・常時スキップの規律を守るため（設計原則 §2）。
// 関連: RootView.swift, SensitivityToggles.swift, LocationProvider.swift, NotificationClient.swift
import SwiftUI
import KiabouUI

struct OnboardingView: View {
    let onFinish: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var page = 0

    private let location = LocationProvider()
    private let notifications = NotificationClient()
    private var palette: KiabouPalette { KiabouPalette(dim: colorScheme == .dark) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("スキップ", action: onFinish)
                    .frame(minHeight: 44)
                    .accessibilityHint("あとから設定で変更できます")
            }
            .padding(.horizontal, 24)

            TabView(selection: $page) {
                OnboardingPage(
                    symbol: "cloud.sun",
                    title: "気圧の変化を、先に知らせます",
                    message: "気圧・湿度・気温・雨から、今後 72 時間の体調リスクを計算します。大きな変化の 90 分前に通知が届きます。",
                    action: "つぎへ", palette: palette) { page = 1 }
                    .tag(0)
                OnboardingPage(
                    symbol: "location",
                    title: "現在地の予報を使います",
                    message: "位置情報は端末の外へ送られません。Apple Weather への座標送信だけに使います。",
                    action: "位置情報を許可する", palette: palette) {
                        Task {
                            _ = try? await location.current()
                            page = 2
                        }
                    }
                    .tag(1)
                OnboardingPage(
                    symbol: "bell.badge",
                    title: "変化の前に、通知でお知らせ",
                    message: "鳴らさない時間帯は設定で変えられます。就寝中の変化は起きた時刻に届きます。",
                    action: "通知を許可する", palette: palette) {
                        Task {
                            _ = await notifications.requestAuthorization()
                            page = 3
                        }
                    }
                    .tag(2)
                sensitivityPage
                    .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
        .background(palette.page.ignoresSafeArea())
        .foregroundStyle(palette.ink)
        .tint(palette.primary)
    }

    /// 「わからない」が既定の道。研究上、本人が信じる引き金と実際の引き金は
    /// よくずれる（docs/research/2026-09-10-weather-attribution.md §1.1）。
    /// 申告は任意の心当たりに留め、見つけるのはアプリの仕事だと明示する。
    private var sensitivityPage: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 48)).foregroundStyle(palette.primary)
            Text("心当たりはありますか？")
                .font(.title2.weight(.semibold)).multilineTextAlignment(.center)
            Text("わからなくて大丈夫です。自分の引き金を正確に知っている人は多くありません。記録が増えると、実際の記録からこのアプリが見つけます。")
                .foregroundStyle(palette.muted).multilineTextAlignment(.center)
            VStack(spacing: 8) {
                SensitivityToggles()
            }
            .padding(16)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 16))
            Spacer()
            Button(action: onFinish) {
                Text("はじめる").font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(palette.onPrimary)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        // ページ・ドットはこの下に描かれる。ボタンと重ならないよう余白を空ける。
        .padding(.bottom, 44)
    }
}

private struct OnboardingPage: View {
    let symbol: String
    let title: String
    let message: String
    let action: String
    let palette: KiabouPalette
    let onAction: () -> Void

    init(symbol: String, title: String, message: String, action: String,
         palette: KiabouPalette, onAction: @escaping () -> Void) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.action = action
        self.palette = palette
        self.onAction = onAction
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 56)).foregroundStyle(palette.primary)
            Text(title)
                .font(.title2.weight(.semibold)).multilineTextAlignment(.center)
            Text(message)
                .foregroundStyle(palette.muted).multilineTextAlignment(.center)
            Spacer()
            Button(action: onAction) {
                Text(action).font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(palette.onPrimary)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        // ページ・ドットはこの下に描かれる。ボタンと重ならないよう余白を空ける。
        .padding(.bottom, 44)
    }
}
