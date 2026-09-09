// /Users/mymac/zutsuu/assets/kiabou/scenery-init.js
// 保存された背景と明るさを、最初の描画より先に適用する。
// 薄明かりで開き直す際、一瞬だけ明るい画面が出るのを防ぐため。
// 関連: index.html, scenery.js, scenery.css, README.md
(() => {
  try {
    const saved = JSON.parse(localStorage.getItem('kiabou-scenery-v1'));
    const choices = { scenery: ['cove', 'plain'], light: ['soft', 'dim'] };
    for (const name of Object.keys(choices)) {
      if (choices[name].includes(saved?.[name])) document.documentElement.dataset[name] = saved[name];
    }
  } catch { /* 保存が使えない場合はHTMLの初期値を使う。 */ }
})();
