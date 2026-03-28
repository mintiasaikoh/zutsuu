const CONFIG = {
  latitude: process.env.LATITUDE ? Number(process.env.LATITUDE) : 35.74,
  longitude: process.env.LONGITUDE ? Number(process.env.LONGITUDE) : 139.65,
  location: process.env.LOCATION || "練馬区",
  quietHours: {
    start: process.env.QUIET_START ? Number(process.env.QUIET_START) : 22,
    end: process.env.QUIET_END ? Number(process.env.QUIET_END) : 8.5,
  },
  morningBriefing: { start: 8.5, end: 10.0 }, // 08:30〜10:00 JST（MORNING_MODEが優先）
  retryCount: 3,
  retryDelay: 2000,
};

type RiskLevel = 1 | 2 | 3 | 4;

const RISK: Record<RiskLevel, { label: string; emoji: string; bar: string }> = {
  1: { label: "安心",     emoji: "🟢", bar: "○○○○" },
  2: { label: "やや注意", emoji: "🟢", bar: "●○○○" },
  3: { label: "注意",     emoji: "🟠", bar: "●●●○" },
  4: { label: "危険",     emoji: "🔴", bar: "●●●●" },
};

interface WeatherHourly {
  time: string[];
  pressure_msl: number[];
  temperature_2m: number[];
  relative_humidity_2m: number[];
  precipitation_probability: number[];
  precipitation: number[];
}

interface RiskFactors {
  pressureScore: number;
  humidityScore: number;
  precipScore: number;
  tempScore: number;
}

interface HourRisk {
  time: Date;
  pressure: number;
  temperature: number;
  humidity: number;
  precipProb: number;
  precip: number;
  change1h: number;
  change3h: number;
  change6h: number;
  riskLevel: RiskLevel;
  riskScore: number;
  riskFactors: RiskFactors;
}

interface TemperatureSwing {
  diff: number;
  hasAlert: boolean;
  todayMax: number;
  yesterdayMax: number;
}

class AppError extends Error {
  constructor(message: string, public code: string, public details?: unknown) {
    super(message);
    this.name = "AppError";
  }
}

function log(level: "info" | "warn" | "error", message: string, data?: unknown): void {
  const timestamp = new Date().toISOString();
  console.log(JSON.stringify({ timestamp, level, message, ...(data !== undefined ? { data } : {}) }));
}

function validateConfig(): void {
  const { latitude, longitude } = CONFIG;
  if (latitude < -90 || latitude > 90) throw new AppError("緯度が無効", "INVALID_LATITUDE");
  if (longitude < -180 || longitude > 180) throw new AppError("経度が無効", "INVALID_LONGITUDE");
}

function isQuietHours(): boolean {
  const now = new Date();
  const hour = now.getHours() + now.getMinutes() / 60;
  const { start, end } = CONFIG.quietHours;
  return start > end ? hour >= start || hour < end : hour >= start && hour < end;
}

function isMorningBriefingTime(): boolean {
  const now = new Date();
  const hour = now.getHours() + now.getMinutes() / 60;
  return hour >= CONFIG.morningBriefing.start && hour < CONFIG.morningBriefing.end;
}

async function fetchWithRetry(url: string): Promise<Response> {
  let lastError: Error = new Error("Unknown");
  for (let i = 0; i < CONFIG.retryCount; i++) {
    try {
      const res = await fetch(url);
      if (res.ok) return res;
      const body = await res.text();
      lastError = new AppError(`API ${res.status}`, "API_ERROR", body);
      log("warn", `API試行 ${i + 1}/${CONFIG.retryCount} 失敗`, { status: res.status });
    } catch (err) {
      lastError = err instanceof Error ? err : new Error(String(err));
      log("warn", `API試行 ${i + 1}/${CONFIG.retryCount} 失敗`, { error: lastError.message });
    }
    if (i < CONFIG.retryCount - 1) await new Promise(r => setTimeout(r, CONFIG.retryDelay));
  }
  throw new AppError("APIリトライ上限", "API_RETRY_EXHAUSTED", lastError);
}

async function fetchWeatherForecast(): Promise<WeatherHourly> {
  validateConfig();
  const url = new URL("https://api.open-meteo.com/v1/forecast");
  url.searchParams.set("latitude", CONFIG.latitude.toString());
  url.searchParams.set("longitude", CONFIG.longitude.toString());
  url.searchParams.set(
    "hourly",
    "pressure_msl,temperature_2m,relative_humidity_2m,precipitation_probability,precipitation"
  );
  url.searchParams.set("timezone", "Asia/Tokyo");
  url.searchParams.set("forecast_days", "3");
  url.searchParams.set("past_days", "1");

  const res = await fetchWithRetry(url.toString());
  const data = await res.json();
  if (!data.hourly?.time?.length) throw new AppError("APIレスポンス不正", "INVALID_RESPONSE", data);
  log("info", "天気データ取得完了", { dataPoints: data.hourly.time.length });
  return data.hourly;
}

// 複合リスクスコアリング
// 気圧（最大11pt）+ 湿度（最大3pt）+ 降水（最大2pt）+ 気温変動（最大2pt）= 最大18pt
function computeCompositeRisk(
  change1h: number, change3h: number, change6h: number, pressure: number,
  humidity: number, precipProb: number, precip: number, tempChange3h: number
): { level: RiskLevel; score: number; factors: RiskFactors } {
  // 気圧スコア（最大11pt）
  let pressureScore = 0;
  const abs1h = Math.abs(change1h);
  if (abs1h >= 4) pressureScore += 3;
  else if (abs1h >= 3) pressureScore += 2;
  else if (abs1h >= 2) pressureScore += 1;

  const abs3h = Math.abs(change3h);
  if (abs3h >= 8) pressureScore += 3;
  else if (abs3h >= 6) pressureScore += 2;
  else if (abs3h >= 4) pressureScore += 1;

  const abs6h = Math.abs(change6h);
  if (abs6h >= 10) pressureScore += 2;
  else if (abs6h >= 6) pressureScore += 1;

  if (pressure <= 995) pressureScore += 3;
  else if (pressure <= 1000) pressureScore += 2;
  else if (pressure <= 1005) pressureScore += 1;

  // 湿度スコア（最大3pt）：高湿度＋気圧低下の複合リスクにボーナス
  let humidityScore = 0;
  if (humidity >= 85) humidityScore += 2;
  else if (humidity >= 75) humidityScore += 1;
  if (humidity >= 75 && change3h <= -4) humidityScore += 1;

  // 降水スコア（最大2pt）
  let precipScore = 0;
  if (precipProb >= 80) precipScore += 2;
  else if (precipProb >= 60) precipScore += 1;
  if (precip > 2 && precipScore < 2) precipScore += 1;

  // 気温変動スコア（最大2pt）：3時間以内の急激な気温変化
  let tempScore = 0;
  const absTempChange = Math.abs(tempChange3h);
  if (absTempChange >= 8) tempScore += 2;
  else if (absTempChange >= 5) tempScore += 1;

  const score = pressureScore + humidityScore + precipScore + tempScore;

  let level: RiskLevel;
  if (score >= 7) level = 4;
  else if (score >= 4) level = 3;
  else if (score >= 1) level = 2;
  else level = 1;

  return { level, score, factors: { pressureScore, humidityScore, precipScore, tempScore } };
}

function analyzeRisk(hourly: WeatherHourly): HourRisk[] {
  const now = new Date();
  const startIdx = hourly.time.findIndex(t => new Date(t) >= now);
  if (startIdx === -1) return [];

  const p = hourly.pressure_msl;
  const t = hourly.temperature_2m;
  const h = hourly.relative_humidity_2m;
  const pp = hourly.precipitation_probability;
  const pr = hourly.precipitation;
  const n = p.length;
  const risks: HourRisk[] = [];

  for (let i = startIdx; i < Math.min(startIdx + 24, n); i++) {
    const change1h = i + 1 < n ? p[i + 1] - p[i] : 0;
    const change3h = i + 3 < n ? p[i + 3] - p[i] : change1h * 3;
    const change6h = i + 6 < n ? p[i + 6] - p[i] : change1h * 6;
    const tempChange3h = i + 3 < n ? t[i + 3] - t[i] : 0;
    const humidity = h[i] ?? 0;
    const precipProb = pp[i] ?? 0;
    const precip = pr[i] ?? 0;

    const { level, score, factors } = computeCompositeRisk(
      change1h, change3h, change6h, p[i],
      humidity, precipProb, precip, tempChange3h
    );

    risks.push({
      time: new Date(hourly.time[i]),
      pressure: p[i],
      temperature: t[i],
      humidity,
      precipProb,
      precip,
      change1h,
      change3h,
      change6h,
      riskLevel: level,
      riskScore: score,
      riskFactors: factors,
    });
  }
  return risks;
}

// 前日比の気温差を検出（頭痛ーるにはない差別化機能）
function detectTemperatureSwing(hourly: WeatherHourly): TemperatureSwing {
  const now = new Date();
  const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const todayEnd = new Date(todayStart.getTime() + 24 * 60 * 60 * 1000);
  const yesterdayStart = new Date(todayStart.getTime() - 24 * 60 * 60 * 1000);

  const todayTemps: number[] = [];
  const yesterdayTemps: number[] = [];

  for (let i = 0; i < hourly.time.length; i++) {
    const t = new Date(hourly.time[i]);
    if (t >= todayStart && t < todayEnd) todayTemps.push(hourly.temperature_2m[i]);
    else if (t >= yesterdayStart && t < todayStart) yesterdayTemps.push(hourly.temperature_2m[i]);
  }

  if (todayTemps.length === 0 || yesterdayTemps.length === 0) {
    return { diff: 0, hasAlert: false, todayMax: 0, yesterdayMax: 0 };
  }

  const todayMax = Math.max(...todayTemps);
  const yesterdayMax = Math.max(...yesterdayTemps);
  const diff = Math.abs(todayMax - yesterdayMax);
  return { diff, hasAlert: diff >= 5, todayMax, yesterdayMax };
}

function trendArrow(change: number): string {
  if (change <= -3) return "▼▼▼";
  if (change <= -1.5) return "▼▼";
  if (change <= -0.5) return "▼";
  if (change >= 3) return "▲▲▲";
  if (change >= 1.5) return "▲▲";
  if (change >= 0.5) return "▲";
  return "─";
}

function buildAdvice(risk: HourRisk, swing: TemperatureSwing): string[] {
  const advice: string[] = [];
  const { pressureScore, precipScore } = risk.riskFactors;

  if (pressureScore >= 4) {
    const dir = risk.change3h < 0 ? "下降" : "上昇";
    advice.push(`気圧${dir}が主因。💊 早めの服薬を推奨（五苓散等）`);
  }
  if (swing.hasAlert) {
    const dir = swing.todayMax > swing.yesterdayMax ? "上昇" : "低下";
    advice.push(`🌡️ 気温${dir}(差${Math.round(swing.diff)}°C)。服装調整を`);
  }
  if (precipScore >= 1) {
    advice.push(`☂️ 降水の可能性(${Math.round(risk.precipProb)}%)。傘を持参して`);
  }
  advice.push("🫁 深呼吸・耳周りマッサージも効果的");
  return advice;
}

function buildRainForecast(risks: HourRisk[]): string {
  const RAIN_THRESHOLD = 40;
  const rainHours = risks.slice(0, 24).filter(r => r.precipProb >= RAIN_THRESHOLD);
  if (rainHours.length === 0) return "☀️ 雨の心配なし";

  const maxProb = Math.max(...rainHours.map(r => r.precipProb));

  // 連続した時間帯をまとめる
  const ranges: string[] = [];
  let rangeStart = rainHours[0];
  let prev = rainHours[0];
  for (let i = 1; i < rainHours.length; i++) {
    const curr = rainHours[i];
    const gap = curr.time.getHours() - prev.time.getHours();
    if (gap > 1) {
      ranges.push(`${rangeStart.time.getHours()}〜${prev.time.getHours() + 1}時`);
      rangeStart = curr;
    }
    prev = curr;
  }
  ranges.push(`${rangeStart.time.getHours()}〜${prev.time.getHours() + 1}時`);

  return `🌧️ 雨の可能性あり（最大${Math.round(maxProb)}%）\n☂️ ${ranges.join("、")}頃`;
}

function formatMorningBriefing(risks: HourRisk[], swing: TemperatureSwing): string {
  const today = new Date().toLocaleDateString("ja-JP", {
    month: "numeric", day: "numeric", weekday: "short",
  });

  const dayRisks = risks.slice(0, 12);
  const maxRisk = Math.max(...dayRisks.map(r => r.riskLevel)) as RiskLevel;
  const riskInfo = RISK[maxRisk];

  const blocks: string[] = [];
  for (let i = 0; i < Math.min(dayRisks.length, 12); i += 3) {
    const block = risks[i];
    if (!block) break;
    const startHour = block.time.getHours();
    const endHour = (startHour + 3) % 24;
    const blockMax = Math.max(...risks.slice(i, i + 3).map(r => r.riskLevel)) as RiskLevel;
    const bi = RISK[blockMax];
    const temp = Math.round(block.temperature);
    blocks.push(`${String(startHour).padStart(2)}〜${endHour}時  ${block.pressure.toFixed(0)}hPa  ${temp}°C  ${bi.emoji} ${bi.label}`);
  }

  const peak = dayRisks.reduce((a, b) => a.riskLevel >= b.riskLevel ? a : b);
  const peakHour = peak.time.getHours();

  let mainAdvice: string;
  if (maxRisk >= 4) {
    mainAdvice = `⚠️ ${peakHour}時台が最も危険です\n💊 外出前に薬を飲んでおくことをおすすめします`;
  } else if (maxRisk === 3) {
    mainAdvice = `⚠️ ${peakHour}時台に注意が必要です\n💊 薬を持ち歩くと安心です`;
  } else {
    mainAdvice = "✅ 今日は気象病リスクが低めです";
  }

  const swingLine = swing.hasAlert
    ? `\n🌡️ 寒暖差注意：昨日${Math.round(swing.yesterdayMax)}°C→今日${Math.round(swing.todayMax)}°C（差${Math.round(swing.diff)}°C）`
    : "";

  const rainForecast = buildRainForecast(risks);

  const adviceLines = buildAdvice(peak, swing).slice(0, -1);
  const adviceSection = adviceLines.length > 0
    ? `\n━━━ 今日の注意点 ━━━\n${adviceLines.map(a => `• ${a}`).join("\n")}`
    : "";

  return `☀️ 今日の気象病予報（${CONFIG.location}）
${today}

${riskInfo.emoji} ${riskInfo.bar} ${riskInfo.label}（${maxRisk}/4）

━━━ 時間帯別リスク ━━━
${blocks.join("\n")}

━━━ 雨予報 ━━━
${rainForecast}

${mainAdvice}${swingLine}${adviceSection}`;
}

function formatAlertMessage(risks: HourRisk[], alertIdx: number, swing: TemperatureSwing): string {
  const alert = risks[alertIdx];
  const riskInfo = RISK[alert.riskLevel];

  const window = risks.slice(Math.max(0, alertIdx - 1), alertIdx + 5);
  const trendLines = window.map(r => {
    const h = String(r.time.getHours()).padStart(2);
    const pr = r.pressure.toFixed(0).padStart(6);
    return `${h}時 ${pr}hPa ${trendArrow(r.change1h)}`;
  });

  const currentPressure = risks[0]?.pressure ?? alert.pressure;
  const endPressure = risks[Math.min(alertIdx + 3, risks.length - 1)]?.pressure ?? alert.pressure;
  const totalChange = endPressure - currentPressure;
  const changeStr = totalChange >= 0 ? `+${totalChange.toFixed(0)}` : totalChange.toFixed(0);
  const direction = totalChange < -0.5 ? "急降下📉" : totalChange > 0.5 ? "急上昇📈" : "変動📊";
  const alertHour = alert.time.getHours();

  // リスク要因内訳
  const { pressureScore, precipScore, tempScore } = alert.riskFactors;
  const factorParts: string[] = [];
  if (pressureScore > 0) factorParts.push(`気圧${pressureScore}pt`);
  if (precipScore > 0) factorParts.push(`降水${precipScore}pt`);
  if (tempScore > 0) factorParts.push(`気温変動${tempScore}pt`);
  const factorLine = factorParts.length > 0
    ? `\n📊 要因内訳: ${factorParts.join(" / ")}（合計${alert.riskScore}pt）\n`
    : "";

  const adviceLines = buildAdvice(alert, swing);
  const adviceSection = adviceLines.map(a => `• ${a}`).join("\n");

  return `⚠️ 気象病アラート（${CONFIG.location}）

${riskInfo.emoji} ${riskInfo.bar} ${riskInfo.label}（${alert.riskLevel}/4）

気圧${direction}  ${changeStr}hPa
${factorLine}
━━━ 気圧の推移 ━━━
${trendLines.join("\n")}

⏰ ${alertHour}時台から症状が出やすくなります
${adviceSection}`;
}

// QuickChart.ioで気圧グラフ画像のURLを生成（リスクレベルを背景色で表示）
async function generateChartUrl(risks: HourRisk[]): Promise<string | null> {
  const hours = risks.slice(0, 12);
  const labels = hours.map(r => `${r.time.getHours()}時`);
  const pressures = hours.map(r => Math.round(r.pressure));

  const riskBgColor: Record<RiskLevel, string> = {
    1: "transparent",
    2: "rgba(76,175,80,0.40)",
    3: "rgba(255,152,0,0.50)",
    4: "rgba(244,67,54,0.55)",
  };

  const pMin = Math.min(...pressures) - 5;
  const pMax = Math.max(...pressures) + 5;

  const chart = {
    type: "bar",
    data: {
      labels,
      datasets: [
        {
          // リスクレベルを背景色として表示（棒グラフでチャートエリアを塗りつぶし）
          type: "bar",
          label: "リスク",
          data: hours.map(() => pMax),
          backgroundColor: hours.map(r => riskBgColor[r.riskLevel]),
          borderWidth: 0,
          yAxisID: "pressure",
          datalabels: { display: false },
        },
        {
          // 気圧折れ線
          type: "line",
          label: "気圧 (hPa)",
          data: pressures,
          yAxisID: "pressure",
          borderColor: "#1565C0",
          backgroundColor: "transparent",
          borderWidth: 2.5,
          tension: 0.35,
          pointBackgroundColor: "#1565C0",
          pointRadius: 4,
          pointBorderColor: "#fff",
          pointBorderWidth: 1.5,
          datalabels: {
            anchor: "end",
            align: "top",
            color: "#1565C0",
            font: { size: 9 },
          },
        },
      ],
    },
    options: {
      plugins: {
        title: { display: true, text: "今後12時間の気圧予報", font: { size: 14 } },
        legend: { display: false },
      },
      scales: {
        pressure: {
          position: "left",
          min: pMin,
          max: pMax,
          title: { display: true, text: "気圧 (hPa)" },
        },
      },
    },
  };

  try {
    const res = await fetch("https://quickchart.io/chart/create", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ chart, width: 600, height: 350, backgroundColor: "white", version: "3" }),
    });
    if (!res.ok) return null;
    const data = await res.json();
    return typeof data.url === "string" ? data.url : null;
  } catch {
    return null;
  }
}

// 現在がリスク未満かつ次の1時間後にリスク3以上になる場合にアラート
// i=1のみチェック（i=2まで見ると連続実行で重複アラートが発火するため）
function shouldSendAlert(risks: HourRisk[]): number | null {
  const currentRisk = risks[0]?.riskLevel ?? 1;
  if (currentRisk >= 3) return null;

  if (risks.length > 1 && risks[1].riskLevel >= 3) {
    log("info", "アラート条件成立", {
      currentRisk,
      upcomingRisk: risks[1].riskLevel,
      time: risks[1].time.toISOString(),
    });
    return 1;
  }
  return null;
}

// 現在は雨でないが、1時間後に降水確率60%以上になる場合に雨アラート
const RAIN_ALERT_THRESHOLD = 60;
function shouldSendRainAlert(risks: HourRisk[]): number | null {
  const currentPrecipProb = risks[0]?.precipProb ?? 0;
  if (currentPrecipProb >= RAIN_ALERT_THRESHOLD) return null;

  if (risks.length > 1 && risks[1].precipProb >= RAIN_ALERT_THRESHOLD) {
    log("info", "雨アラート条件成立", {
      currentPrecipProb,
      upcomingPrecipProb: risks[1].precipProb,
      time: risks[1].time.toISOString(),
    });
    return 1;
  }
  return null;
}

function formatRainAlertMessage(risks: HourRisk[]): string {
  const alertHour = risks[1].time.getHours();
  const prob = Math.round(risks[1].precipProb);

  // 雨が続く時間帯を算出
  const rainHours = risks.slice(1).filter(r => r.precipProb >= RAIN_ALERT_THRESHOLD);
  const endHour = rainHours.length > 0
    ? rainHours[rainHours.length - 1].time.getHours() + 1
    : alertHour + 1;

  const change3h = risks[1].change3h.toFixed(1);
  const changeStr = Number(change3h) >= 0 ? `+${change3h}` : change3h;
  const pressureDir = Number(change3h) < -0.5 ? "下降中📉" : Number(change3h) > 0.5 ? "上昇中📈" : "ほぼ変化なし";

  return `☂️ まもなく雨の可能性（${CONFIG.location}）

⏰ ${alertHour}〜${endHour}時頃に雨の見込み（降水確率${prob}%）

🌡️ 気圧は${pressureDir}（3時間で${changeStr}hPa）

• 傘の準備をおすすめします
• 気圧変化で頭痛が出やすい時間帯です
• 🫁 深呼吸・耳周りマッサージも効果的`;
}

async function sendLineMessage(message: string, imageUrl?: string): Promise<void> {
  const token = process.env.LINE_CHANNEL_TOKEN;
  const userId = process.env.LINE_USER_ID;

  if (!token || !userId) {
    log("info", "[テストモード] 送信予定メッセージ");
    console.log("---");
    console.log(message);
    if (imageUrl) console.log(`[グラフ] ${imageUrl}`);
    console.log("---");
    return;
  }

  const messages: object[] = [{ type: "text", text: message }];
  if (imageUrl) {
    messages.push({ type: "image", originalContentUrl: imageUrl, previewImageUrl: imageUrl });
  }

  const res = await fetch("https://api.line.me/v2/bot/message/push", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ to: userId, messages }),
  });

  if (!res.ok) {
    const errorText = await res.text();
    throw new AppError(`LINE API ${res.status}`, "LINE_API_ERROR", { status: res.status, response: errorText });
  }

  log("info", "LINE通知送信完了", { hasChart: !!imageUrl });
}

async function main() {
  try {
    log("info", "気圧チェック開始", { location: CONFIG.location });

    const morningMode = process.env.MORNING_MODE === "true";

    if (isQuietHours() && !morningMode) {
      log("info", "通知オフ時間帯のためスキップ");
      return;
    }

    const hourly = await fetchWeatherForecast();
    const risks = analyzeRisk(hourly);
    const swing = detectTemperatureSwing(hourly);

    if (risks.length === 0) {
      log("warn", "リスク分析データ不足");
      return;
    }

    const currentRisk = risks[0].riskLevel;
    const maxRisk12h = Math.max(...risks.slice(0, 12).map(r => r.riskLevel));

    log("info", "リスク分析完了", {
      currentRisk,
      maxRisk12h,
      currentPressure: risks[0].pressure.toFixed(1),
      currentHumidity: risks[0].humidity,
      tempSwingAlert: swing.hasAlert,
      tempSwingDiff: swing.diff.toFixed(1),
      isMorning: isMorningBriefingTime(),
    });

    if (morningMode || isMorningBriefingTime()) {
      const [message, chartUrl] = await Promise.all([
        Promise.resolve(formatMorningBriefing(risks, swing)),
        generateChartUrl(risks),
      ]);
      if (chartUrl) log("info", "グラフURL生成完了");
      await sendLineMessage(message, chartUrl ?? undefined);
      log("info", "朝の予報を送信", { maxRisk12h, swingAlert: swing.hasAlert });
      return;
    }

    const alertIdx = shouldSendAlert(risks);
    const rainAlertIdx = shouldSendRainAlert(risks);
    let sent = false;

    if (alertIdx !== null) {
      const [message, chartUrl] = await Promise.all([
        Promise.resolve(formatAlertMessage(risks, alertIdx, swing)),
        generateChartUrl(risks),
      ]);
      if (chartUrl) log("info", "グラフURL生成完了");
      await sendLineMessage(message, chartUrl ?? undefined);
      log("info", "気象病アラートを送信", { riskLevel: risks[alertIdx]?.riskLevel });
      sent = true;
    }

    if (rainAlertIdx !== null) {
      const message = formatRainAlertMessage(risks);
      await sendLineMessage(message);
      log("info", "雨アラートを送信", { precipProb: risks[rainAlertIdx]?.precipProb });
      sent = true;
    }

    if (!sent) {
      log("info", "通知なし", {
        currentRisk,
        next3hRisks: risks.slice(1, 4).map(r => r.riskLevel),
      });
    }
  } catch (err) {
    if (err instanceof AppError) {
      log("error", err.message, { code: err.code, details: err.details });
    } else {
      log("error", "予期しないエラー", { error: String(err) });
    }
    throw err;
  }
}

main().catch(err => {
  log("error", "アプリケーション終了", { error: err instanceof Error ? err.message : String(err) });
  process.exit(1);
});
