// /Users/mymac/zutsuu/ios/ZutsuuKit/Sources/KiabouUI/KiabouScene.swift
// 同梱USDZの読み込み、カメラ、泳ぎと1/fゆらぎを制御する。
// 通信やARカメラを使わず、休憩画面に3Dの相棒を置くため。
// 関連: KiabouStage.swift, PinkMotion.swift, KiabouRestView.swift
#if os(iOS) || os(macOS)
import RealityKit
import SwiftUI

@MainActor @Observable
final class KiabouScene {
    let root = Entity()
    let camera = PerspectiveCamera()
    private let drift = Entity()
    private var models: [Bool: Entity] = [:]
    private var animations: [AnimationPlaybackController] = []
    private var subscription: EventSubscription?
    private var motion = PinkMotion()
    private var enabled = false
    private var resting = false
    private var skipNextFrame = true
    private(set) var loadedResting: Bool?
    private(set) var failed = false

    init() {
        root.addChild(drift)
        root.addChild(camera)
        camera.camera.fieldOfViewInDegrees = 34
        let light = DirectionalLight()
        light.light.intensity = 1_300
        light.look(at: .zero, from: [-1, 2, 3], relativeTo: nil)
        root.addChild(light)
    }

    func subscribe(to content: RealityViewCameraContent) {
        subscription?.cancel()
        subscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.tick(delta: event.deltaTime)
        }
    }

    func load(resting: Bool) async {
        self.resting = resting
        failed = false
        setMotion(enabled: false)
        loadedResting = nil
        do {
            let model: Entity
            if let cached = models[resting] {
                model = cached
            } else {
                model = try await Entity(named: resting ? "covered.usdz" : "kiabou.usdz", in: .module)
                try Task.checkCancellation()
                // 素材の中心だけを合わせ、骨格のローカル変換は保持する。
                let centered = Entity()
                centered.addChild(model)
                model.position -= model.visualBounds(relativeTo: centered).center
                models[resting] = centered
            }
            try Task.checkCancellation()
            animations.forEach { $0.stop() }
            animations = []
            drift.children.removeAll()
            drift.addChild(models[resting] ?? model)
            camera.look(at: .zero,
                        from: resting ? [-0.30, 0.44, 0.43] : [-0.20, 0.09, 0.65],
                        relativeTo: nil)
            if !resting { playAnimations(in: models[resting] ?? model) }
            loadedResting = resting
        } catch is CancellationError {
            // 休む/戻るの連打で古い読み込みが終わっても画面を上書きしない。
        } catch {
            failed = true
        }
    }

    private func playAnimations(in entity: Entity) {
        // USDZではアニメーションがルート以外の骨格に付くこともある。
        for animation in entity.availableAnimations {
            let controller = entity.playAnimation(animation.repeat(), startsPaused: true)
            animations.append(controller)
        }
        for child in entity.children { playAnimations(in: child) }
    }

    func setMotion(enabled: Bool) {
        if self.enabled != enabled { skipNextFrame = true }
        self.enabled = enabled
        for animation in animations {
            if enabled && !resting { animation.resume() } else { animation.pause() }
        }
    }

    func stop() {
        setMotion(enabled: false)
        subscription?.cancel()
        subscription = nil
    }

    private func tick(delta: Double) {
        guard enabled else { return }
        if skipNextFrame { skipNextFrame = false; return }
        motion.advance(delta: delta, enabled: true, resting: resting)
        let x = Float(motion.horizontal.sample(at: motion.time))
        let y = Float(motion.vertical.sample(at: motion.time))
        let tilt = Float(motion.tilt.sample(at: motion.time))
        let strength = Float(motion.strength)
        // 固定カメラ・固定背景の中で、モデルだけを数mm動かす。
        drift.position = [x * 0.022 * strength, y * 0.032 * strength, 0]
        drift.orientation = simd_quatf(angle: tilt * 0.157 * strength, axis: [0, 0, 1])
            * simd_quatf(angle: y * 0.070 * strength, axis: [1, 0, 0])
            * simd_quatf(angle: x * 0.087 * strength, axis: [0, 1, 0])
        for animation in animations { animation.speed = 0.85 + 0.6 * x }
    }
}
#endif
