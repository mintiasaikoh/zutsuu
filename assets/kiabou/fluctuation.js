// /Users/mymac/zutsuu/assets/kiabou/fluctuation.js
// 帯域を限った1/fゆらぎを生成し、きあぼうの姿勢と浮遊へ反映する。
// 短い固定ループに頼らず、滑らかで小さな揺れを続けるため。
// 関連: rest.js, index.html, rest.css, README.md

export function pinkWave(seed) {
  let randomState = seed >>> 0;
  const random = () => {
    randomState = (Math.imul(randomState, 1664525) + 1013904223) >>> 0;
    return randomState / 4294967296;
  };
  // 対数周波数ごとに同じパワーを配ると、単位HzあたりのPSDは約1/f。
  // 0.025–0.4 Hz（2.5–40秒）のみを使い、速い震えを含めない。
  const count = 96;
  const waves = Array.from({ length: count }, (_, i) => ({
    frequency: .025 * 16 ** ((i + random()) / count),
    phase: random() * Math.PI * 2,
  }));
  // 総和で正規化し、どの位相の組合せでも出力を[-1, 1]に収める。
  return (time) => waves.reduce((sum, wave) =>
    sum + Math.sin(2 * Math.PI * wave.frequency * time + wave.phase), 0) / count;
}

export function createFluctuation(viewer) {
  const seed = new Uint32Array(3);
  crypto.getRandomValues(seed);
  const [horizontal, vertical, tilt] = Array.from(seed, pinkWave);
  let frame = null;
  let last = null;
  let time = 0;
  let strength = 0;
  let resting = false;

  function tick(now) {
    const dt = last === null ? 0 : Math.min((now - last) / 1000, .1);
    last = now;
    time += dt;
    // 開始時と休む切替時の振幅を滑らかに変え、急な跳びを避ける。
    strength += ((resting ? .3 : 1) - strength) * (1 - Math.exp(-dt / 1.5));
    const x = horizontal(time), y = vertical(time), angle = tilt(time);
    viewer.style.transform = `translate3d(${(x * 22 * strength).toFixed(3)}px, ${(y * 32 * strength).toFixed(3)}px, 0)`;
    viewer.orientation = `${(angle * 9 * strength).toFixed(4)}deg ${(y * 4 * strength).toFixed(4)}deg ${(x * 5 * strength).toFixed(4)}deg`;
    // 元のヒレのアニメーションにも時間のゆらぎを加える。
    viewer.timeScale = .85 + .6 * x;
    frame = requestAnimationFrame(tick);
  }

  return {
    set({ enabled, isResting }) {
      resting = isResting;
      if (enabled) {
        if (frame === null) { last = null; frame = requestAnimationFrame(tick); }
      } else {
        if (frame !== null) cancelAnimationFrame(frame);
        frame = null;
        last = null;
        // 現在の姿勢で止める。再開時も同じ時点から動く。
      }
    },
  };
}
