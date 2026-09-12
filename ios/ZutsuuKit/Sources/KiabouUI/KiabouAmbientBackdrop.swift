// /Users/mymac/zutsuu/ios/ZutsuuKit/Sources/KiabouUI/KiabouAmbientBackdrop.swift
// 画面の最背面で、きあぼうが縦横斜めにゆっくり泳ぐレイヤー。
// UI を半透明にして向こう側に相棒の気配を置くため（kiabou-integration.md §3.1）。
// 関連: KiabouScene.swift, KiabouStage.swift, KiabouQuickCheckIn.swift
#if os(iOS) || os(macOS)
import RealityKit
import SwiftUI

/// 画面全体に敷く背面遊泳レイヤー。触れず、読み上げにも出ない。
/// Reduce Motion 時は呼び出し側でこのレイヤー自体を出さないこと（§3.1）。
public struct KiabouAmbientBackdrop: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("kiabou.outfit") private var outfitID = KiabouOutfit.original.id
    @State private var scene = KiabouScene(ambient: true)
    @State private var visible = false

    public init() {}

    public var body: some View {
        // body で読むことで、読み込み完了（loadedResting）の変化が再描画→update の再実行につながる。
        // update クロージャの中でしか読まないと、読み込みが onAppear より後に終わったとき
        // update が二度と呼ばれず、購読されないまま静止する（2026-09-12 に実測）。
        let running = visible && scenePhase == .active && scene.loadedResting == false
        RealityView { content in
            content.camera = .virtual
            content.renderingEffects.motionBlur = .disabled
            content.renderingEffects.depthOfField = .disabled
            content.renderingEffects.cameraGrain = .disabled
            content.renderingEffects.dynamicRange = .standard
            content.add(scene.root)
        } update: { content in
            if running { scene.subscribe(to: content) } else { scene.stop() }
            scene.setMotion(enabled: running)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: outfitID) {
            await scene.load(outfit: .outfit(id: outfitID), resting: false)
        }
        .onAppear { visible = true }
        .onDisappear { visible = false; scene.stop() }
    }
}
#endif
