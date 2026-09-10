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
    // 以下は描画ループの内部状態。`RealityView` の `update:` 内から書き換えるため、
    // 観測対象にすると「書き換え → 再描画 → update → 書き換え」の無限ループになり
    // メインスレッドが止まる（実測）。画面が見るのは loadedResting と failed だけ。
    @ObservationIgnored private var models: [Bool: Entity] = [:]
    @ObservationIgnored private var animations: [AnimationPlaybackController] = []
    @ObservationIgnored private var subscription: EventSubscription?
    @ObservationIgnored private var motion = PinkMotion()
    @ObservationIgnored private var enabled = false
    @ObservationIgnored private var resting = false
    @ObservationIgnored private var skipNextFrame = true
    // 背面遊泳モード（kiabou-integration.md §3.1）の彷徨状態。
    @ObservationIgnored private var wander = SIMD2<Double>(0, 0)
    @ObservationIgnored private var heading = -0.5
    private let ambient: Bool
    private(set) var loadedResting: Bool?
    private(set) var failed = false

    init(ambient: Bool = false) {
        self.ambient = ambient
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
            if ambient {
                // 正面から少し引いた固定カメラ。モデルを小さくし、画面を横切る余地を作る。
                drift.scale = [0.42, 0.42, 0.42]
                camera.look(at: .zero, from: [0, 0, 0.95], relativeTo: nil)
            } else {
                camera.look(at: .zero,
                            from: resting ? [-0.30, 0.44, 0.43] : [-0.20, 0.09, 0.65],
                            relativeTo: nil)
            }
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
        if ambient { advanceWander(delta: min(delta, 0.1)) }
        // 固定カメラの中で、彷徨（背面モードのみ）＋数mmの揺れだけを動かす。
        drift.position = [Float(wander.x) + x * 0.022 * strength,
                          Float(wander.y) + y * 0.032 * strength, 0]
        drift.orientation = simd_quatf(angle: tilt * 0.157 * strength, axis: [0, 0, 1])
            * simd_quatf(angle: y * 0.070 * strength, axis: [1, 0, 0])
            * simd_quatf(angle: x * 0.087 * strength, axis: [0, 1, 0])
        for animation in animations { animation.speed = 0.85 + 0.6 * x }
    }

    /// 背面遊泳（kiabou-integration.md §3.1）。進行方位が 1/f でゆっくり変わり、
    /// 縦・横・斜めを行き来する。画面端では跳ね返る — 瞬間移動で反対側へ出すと
    /// 位置が飛んで見えるため。境界は縦画面のカメラ視野から取った控えめな値。
    private func advanceWander(delta: Double) {
        heading += motion.tilt.sample(at: motion.time * 0.31) * delta * 0.55
        let speed = 0.013 * (0.75 + 0.25 * motion.vertical.sample(at: motion.time * 0.17))
        wander.x += cos(heading) * speed * delta
        wander.y += sin(heading) * speed * delta
        // 縦画面のカメラ視野（半幅 ≈0.13、半高 ≈0.29）より少し内側。端で切れたままにしない。
        let bounds = SIMD2<Double>(0.10, 0.25)
        if abs(wander.x) > bounds.x {
            wander.x = wander.x.clamped(to: -bounds.x...bounds.x)
            heading = .pi - heading
        }
        if abs(wander.y) > bounds.y {
            wander.y = wander.y.clamped(to: -bounds.y...bounds.y)
            heading = -heading
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
#endif
