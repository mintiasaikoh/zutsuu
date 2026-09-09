// /Users/mymac/zutsuu/assets/kiabou/scenery.js
// 背景と明るさを切り替え、本人が選んだ見え方を保存する。
// 休む状態や1/fゆらぎに干渉せず、無地にもすぐ戻せるようにするため。
// 関連: index.html, scenery.css, rest.js, README.md
const key = 'kiabou-scenery-v1';
const options = { scenery: ['cove', 'plain'], light: ['soft', 'dim'] };
const settings = { scenery: document.documentElement.dataset.scenery, light: document.documentElement.dataset.light };

function render() {
  for (const name of Object.keys(options)) {
    document.documentElement.dataset[name] = settings[name];
    for (const button of document.querySelectorAll(`[data-${name}-choice]`)) {
      button.setAttribute('aria-pressed', String(button.dataset[`${name}Choice`] === settings[name]));
    }
  }
}

for (const name of Object.keys(options)) {
  for (const button of document.querySelectorAll(`[data-${name}-choice]`)) {
    button.addEventListener('click', () => {
      settings[name] = button.dataset[`${name}Choice`];
      render();
      try { localStorage.setItem(key, JSON.stringify(settings)); } catch { /* 画面内で続行。 */ }
    });
  }
}
render();
