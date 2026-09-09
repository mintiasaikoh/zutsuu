// /Users/mymac/zutsuu/assets/kiabou/rest.js
// 自分で休む・休みを終える、の状態を管理する。
// 個人用の相棒として、本人のペースで使う体験を確かめるため。
// 関連: index.html, rest.css, create_rest.py, README.md
import { createFluctuation } from './fluctuation.js';
const $ = (id) => document.getElementById(id);
const viewer = $('kiabou');
const fluctuation = createFluctuation(viewer);
const storageKey = 'kiabou-rest-prototype-v1';
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
let state = { resting: false };
// 端末の設定は初期値に反映し、画面内の明示操作では再生できるようにする。
let motionPaused = reducedMotion.matches;
try {
  const saved = JSON.parse(localStorage.getItem(storageKey));
  if (saved?.resting === true) state = { resting: true };
} catch { /* 保存が禁止されていても、この画面で体験を続けられる。 */ }

function save() {
  try { localStorage.setItem(storageKey, JSON.stringify(state)); } catch { /* セッション内で続行。 */ }
}

function render() {
  $('rest').hidden = state.resting;
  $('finish').hidden = !state.resting;
  $('quiet-message').hidden = !state.resting;
  if (!state.resting) {
    $('eyebrow').textContent = '自分のペースで。';
    $('heading').textContent = '少し、ひと休み。';
    $('description').textContent = '休みたいときは、きあぼうも一緒に。';
    $('hint').textContent = '理由を決めなくても、大丈夫。';
  } else {
    $('eyebrow').textContent = 'ここは、そのままに。';
    $('heading').textContent = 'ゆっくり、休んでね。';
    $('description').textContent = 'きあぼうも、ここで休んでいます。';
    $('quiet-message').textContent = 'このまま、画面を閉じて大丈夫。';
    $('hint').textContent = '戻りたいときに、またここへ。';
  }
  const source = state.resting ? 'covered.glb' : 'kiabou.glb';
  viewer.alt = state.resting ? '青い毛布にくるまり、寝床で静かに休むきあぼう。' : '静かに泳ぐ、マンボウのきあぼう。';
  if (viewer.getAttribute('src') !== source) {
    $('asset-status').textContent = 'きあぼうを準備しています…';
    viewer.setAttribute('poster', state.resting ? source.replace('.glb', '.png') : 'preview.png');
    viewer.setAttribute('camera-orbit', state.resting ? '-35deg 42deg auto' : '-18deg 82deg auto');
    viewer.setAttribute('camera-target', 'auto auto auto');
    viewer.setAttribute('src', source);
  }
  updateMotion();
}

function updateMotion() {
  const enabled = viewer.loaded && !motionPaused && !document.hidden;
  fluctuation.set({ enabled, isResting: state.resting });
  $('motion').textContent = motionPaused ? 'ゆらぎを動かす' : 'ゆらぎを止める';
  if (!viewer.loaded) return;
  if (!state.resting && enabled) viewer.play();
  else viewer.pause();
}

$('motion').addEventListener('click', () => {
  motionPaused = !motionPaused;
  updateMotion();
});
$('rest').addEventListener('click', () => {
  state = { resting: true };
  save(); render(); $('heading').focus();
});
$('finish').addEventListener('click', () => {
  state = { resting: false };
  save(); render(); $('rest').focus();
});
viewer.addEventListener('load', () => {
  $('asset-status').textContent = '';
  viewer.cameraOrbit = state.resting ? '-35deg 42deg 0.56m' : '-18deg 82deg auto';
  viewer.cameraTarget = state.resting ? '0m 0.035m 0m' : 'auto auto auto';
  viewer.jumpCameraToGoal();
  updateMotion();
});
viewer.addEventListener('error', () => {
  fluctuation.set({ enabled: false, isResting: state.resting });
  viewer.showPoster();
  $('asset-status').textContent = '3Dを読み込めませんでした。確認画像で体験を続けられます。';
});
document.addEventListener('visibilitychange', updateMotion);
reducedMotion.addEventListener('change', () => {
  if (reducedMotion.matches) motionPaused = true;
  updateMotion();
});
setTimeout(() => {
  if (!customElements.get('model-viewer')) $('asset-status').textContent = '3Dビューアに接続できませんでした。ネット接続を確認してください。';
}, 15000);
render();
