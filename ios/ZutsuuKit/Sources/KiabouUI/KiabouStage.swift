// /Users/mymac/zutsuu/ios/ZutsuuKit/Sources/KiabouUI/KiabouStage.swift
// 静止した背景の前に、ネイティブ3Dのきあぼうを表示する。
// 読み込み中も画像を保ち、非表示時にはゆらぎを停止するため。
// 関連: KiabouScene.swift, KiabouPalette.swift, KiabouCheckInView.swift
#if os(iOS) || os(macOS)
import RealityKit
import SwiftUI

/// きあぼうの舞台（背景 + 3D）。記録ビューときあぼうタブが共用する。
public struct KiabouStage: View {
    let resting: Bool
    let cove: Bool
    let dim: Bool
    let moving: Bool
    var outfit: KiabouOutfit = .original
    @State private var scene = KiabouScene()
    @State private var visible = false

    public init(resting: Bool, cove: Bool, dim: Bool, moving: Bool,
                outfit: KiabouOutfit = .original) {
        self.resting = resting
        self.cove = cove
        self.dim = dim
        self.moving = moving
        self.outfit = outfit
    }

    private var ready: Bool { scene.loadedResting == resting }
    private var running: Bool { moving && visible && ready }

    public var body: some View {
        ZStack {
            if cove, let coveImage = Self.bundledImage("cove") {
                GeometryReader { geometry in
                    coveImage
                        .resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .saturation(dim ? 0.7 : 1)
                        .overlay(.black.opacity(dim ? 0.57 : 0))
                        .mask(LinearGradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.18),
                            .init(color: .black, location: 0.78),
                            .init(color: .clear, location: 1)
                        ], startPoint: .top, endPoint: .bottom))
                }
            }
            RealityView { content in
                content.camera = .virtual
                content.renderingEffects.motionBlur = .disabled
                content.renderingEffects.depthOfField = .disabled
                content.renderingEffects.cameraGrain = .disabled
                content.renderingEffects.dynamicRange = .standard
                content.add(scene.root)
            } update: { content in
                if running { scene.subscribe(to: content) }
                else { scene.stop() }
                scene.setMotion(enabled: running)
            }
            .opacity(ready ? 1 : 0)
            .brightness(dim ? -0.18 : 0)
            .allowsHitTesting(false)

            if !ready, let placeholder = Self.bundledImage(resting ? "covered" : "preview") {
                placeholder
                    .resizable().scaledToFit().padding(28)
                    .brightness(dim ? -0.18 : 0)
            }
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(resting ? "毛布にくるまり休むきあぼう" : "ゆっくり泳ぐきあぼう")
        .overlay(alignment: .bottom) {
            if scene.failed {
                Text("きあぼうを画像で表示しています")
                    .font(.caption).foregroundStyle(KiabouPalette(dim: dim).muted)
            }
        }
        .task(id: "\(outfit.id)#\(resting)") { await scene.load(outfit: outfit, resting: resting) }
        .onAppear { visible = true }
        .onDisappear { visible = false; scene.stop() }
    }

    /// SwiftUI の `Image(_:bundle:)` は SPM リソースバンドル直下の PNG を
    /// 見つけられない（アセットカタログしか探さず、静かに空を描く。実測）。
    /// UIKit / AppKit 経由で読む。
    static func bundledImage(_ name: String) -> Image? {
        #if os(iOS)
        UIImage(named: name, in: .module, with: nil).map(Image.init(uiImage:))
        #else
        Bundle.module.image(forResource: name).map(Image.init(nsImage:))
        #endif
    }
}
#endif
