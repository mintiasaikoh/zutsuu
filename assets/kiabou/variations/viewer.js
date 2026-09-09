// /Users/mymac/zutsuu/assets/kiabou/variations/viewer.js
// 3種類の着せ替え素材を同じ条件で表示・再生する。
// アプリ実装と独立して、配布GLBと小物の状態を確認するため。
// 関連: index.html, catalog.json, ASSETS.md, build_variations.py
const families = [['kasumi', 'かすみ'], ['shizuku', 'しずく'], ['komorebi', 'こもれび']];
const style = document.querySelector('#style');
const pose = document.querySelector('#pose');
const motion = document.querySelector('#motion');
let playing = false;

const cards = families.map(([family, label], i) => {
  const card = document.createElement('article');
  card.innerHTML = `<span class="number">0${i + 1}</span><h2>${label}</h2>
    <model-viewer camera-controls interaction-prompt="none" loading="eager" shadow-intensity="0.3" shadow-softness="1" exposure="1" alt="${label}のきあぼうの3D素材"></model-viewer>
    <p class="status" role="status"></p><div class="links"><a class="download glb" download>GLB</a><a class="download usdz" download>iOS用 USDZ</a></div>`;
  document.querySelector('#cards').append(card);
  const viewer = card.querySelector('model-viewer');
  viewer.addEventListener('load', () => {
    card.querySelector('.status').textContent = 'ドラッグで回転';
    camera(viewer);
    updateMotion();
  });
  viewer.addEventListener('error', () => { card.querySelector('.status').textContent = '3Dを読み込めませんでした。ページを開き直してください。'; });
  return { card, viewer, family };
});

function camera(viewer) {
  viewer.cameraOrbit = pose.value === 'swim' ? '-18deg 82deg auto' : '-35deg 42deg auto';
  viewer.cameraTarget = 'auto auto auto';
  if (viewer.loaded) viewer.jumpCameraToGoal();
}

function render() {
  for (const { card, viewer, family } of cards) {
    const accessory = ['pillow', 'blanket'].includes(pose.value);
    const path = `${family}/${accessory ? 'accessories' : style.value}/${pose.value}`;
    if (viewer.getAttribute('src') !== `${path}.glb`) {
      card.querySelector('.status').textContent = '読み込み中…';
      if (!accessory && pose.value !== 'rest-body') viewer.setAttribute('poster', `${path}.png`);
      else viewer.removeAttribute('poster');
      viewer.setAttribute('src', `${path}.glb`);
    }
    card.querySelector('.glb').href = `${path}.glb`;
    card.querySelector('.usdz').href = `${path}.usdz`;
    camera(viewer);
  }
  style.disabled = ['pillow', 'blanket'].includes(pose.value);
  motion.disabled = pose.value !== 'swim';
  updateMotion();
}

function updateMotion() {
  const active = playing && pose.value === 'swim' && !document.hidden;
  for (const { viewer } of cards) {
    if (!viewer.loaded) continue;
    if (active) { viewer.timeScale = .85; viewer.play(); } else viewer.pause();
  }
  motion.textContent = pose.value !== 'swim' ? '静止した素材' : playing ? '泳ぎを止める' : '泳ぎを再生';
}

style.addEventListener('change', render);
pose.addEventListener('change', render);
motion.addEventListener('click', () => { playing = !playing; updateMotion(); });
document.querySelector('#reset').addEventListener('click', () => cards.forEach(({ viewer }) => camera(viewer)));
document.addEventListener('visibilitychange', updateMotion);
matchMedia('(prefers-reduced-motion: reduce)').addEventListener('change', (event) => {
  if (event.matches) { playing = false; updateMotion(); }
});
render();
