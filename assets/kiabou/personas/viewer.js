// /Users/mymac/zutsuu/assets/kiabou/personas/viewer.js
// 衣装あり・色だけ・休む姿を切り替えて、配布素材を比較する。
// 実装用モデルの見た目と泳ぐ動きを、アプリと独立して確認するため。
// 関連: index.html, catalog.json, README.md, build_personas.py
const personas = [
  ['gyaru','ぎゃる','おでこのサングラスと、ハートのバッグ。'],
  ['rapper','らっぱー','斜めのキャップと、レコードのチャーム。'],
  ['punk','ぱんく','星のピンと、チェックのポーチ。'],
  ['cafe','喫茶店員','モカ色のベレー帽と、小さなエプロン。'],
  ['mage','魔法使い','とんがり帽子と、短い夜色のケープ。'],
];
const look = document.querySelector('#look');
const motion = document.querySelector('#motion');
let playing = false;
const cards = personas.map(([id,label,description], index) => {
  const card = document.createElement('article');
  card.innerHTML = `<span class="number">0${index+1}</span><h2>${label}</h2><p class="description">${description}</p>
    <model-viewer camera-controls interaction-prompt="none" loading="eager" shadow-intensity="0.3" shadow-softness="1" exposure="1" alt="${label}きあぼうの3D素材"></model-viewer>
    <p class="status" role="status"></p><div class="links"><a class="download glb" download>GLB</a><a class="download usdz" download>iOS用 USDZ</a></div>`;
  document.querySelector('#cards').append(card);
  const viewer = card.querySelector('model-viewer');
  viewer.addEventListener('load', () => {
    card.querySelector('.status').textContent = 'ドラッグで回転';
    camera(viewer); updateMotion();
  });
  viewer.addEventListener('error', () => { card.querySelector('.status').textContent = '3Dを読み込めませんでした。ページを開き直してください。'; });
  return {card,viewer,id};
});

function camera(viewer) {
  viewer.cameraOrbit = look.value === 'covered' ? '-35deg 42deg auto' : '-18deg 82deg auto';
  viewer.cameraTarget = 'auto auto auto';
  if (viewer.loaded) viewer.jumpCameraToGoal();
}

function render() {
  for (const {card,viewer,id} of cards) {
    const path = `${id}/${look.value}`;
    viewer.setAttribute('poster', `${path}.png`);
    viewer.setAttribute('src', `${path}.glb`);
    card.querySelector('.status').textContent = '読み込み中…';
    card.querySelector('.glb').href = `${path}.glb`;
    card.querySelector('.usdz').href = `${path}.usdz`;
    camera(viewer);
  }
  motion.disabled = look.value === 'covered';
  updateMotion();
}

function updateMotion() {
  for (const {viewer} of cards) {
    if (!viewer.loaded) continue;
    if (playing && look.value !== 'covered' && !document.hidden) { viewer.timeScale = .85; viewer.play(); }
    else viewer.pause();
  }
  motion.textContent = look.value === 'covered' ? '静止した素材' : playing ? '泳ぎを止める' : '泳ぎを再生';
}
look.addEventListener('change',render);
motion.addEventListener('click', () => { playing = !playing; updateMotion(); });
document.querySelector('#reset').addEventListener('click', () => cards.forEach(({viewer}) => camera(viewer)));
document.addEventListener('visibilitychange',updateMotion);
matchMedia('(prefers-reduced-motion: reduce)').addEventListener('change', event => {
  if (event.matches) { playing = false; updateMotion(); }
});
setTimeout(() => {
  if (!customElements.get('model-viewer')) {
    cards.forEach(({card}) => { card.querySelector('.status').textContent = 'ビューアに接続できませんでした。画像とダウンロードを利用できます。'; });
  }
},15000);
render();
