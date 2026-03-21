const CONFIG = {
  latitude: process.env.LATITUDE ? Number(process.env.LATITUDE) : 35.74,
  longitude: process.env.LONGITUDE ? Number(process.env.LONGITUDE) : 139.65,
  location: process.env.LOCATION || "練馬区",
  quietHours: {
    start: process.env.QUIET_START ? Number(process.env.QUIET_START) : 22,
    end: process.env.QUIET_END ? Number(process.env.QUIET_END) : 8.5,
  },
  morningBriefing: { start: 8.5, end: 9.5 }, // 8:30〜9:30
  retryCount: 3,
  retryDelay: 2000,
};

type RiskLevel = 1 | 2 | 3 | 4 | 5;

const RISK: Record<RiskLevel, { label: string; emoji: string; bar: string }> = {
  1: { label: "安心",     emoji: "🟢", bar: "●○○○○" },
  2: { label: "やや注意", emoji: "🟡", bar: "●●○○○" },
  3: { label: "注意",     emoji: "🟠", bar: "●●●○○" },
  4: { label: "警戒",     emoji: "🔴", bar: "●●●●○" },
  5: { label: "危険",     emoji: "🆘", bar: "●●●●●" },
};

interface WeatherHourly {
  time: string[];
  pressure_msl: number[];
  temperature_2m: number[];
}

interface HourRisk {
  time: Date;
  pressure: number;
  temperature: number;
  change1h: number;
  change3h: number;
  change6h: number;
  riskLevel: RiskLevel;
}

class AppError extends Error {
  constructor(message: string, public code: string, public details?: unknown) {
    super(message);
    this.name = "AppError";
  }
}

function log(level: "info" | "warn" | "error", message: string, data?: unknown): void {
  const timestamp = new Date().toISOString();
  console.log(JSON.stringify({ timestamp, level, message, ...(data && { data }) }));
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
  url.searchParams.set("hourly", "pressure_msl,temperature_2m");
  url.searchParams.set("timezone", "Asia/Tokyo");
  url.searchParams.set("forecast_days", "3");

  const res = await fetchWithRetry(url.toString());
  const data = await res.json();
  if (!data.hourly?.time?.length) throw new AppError("APIレスポンス不正", "INVALID_RESPONSE", data);
  log("info", "天気データ取得完了", { dataPoints: data.hourly.time.length });
  return data.hourly;
}

// 頭痛ーると同様の多要素リスクスコアリング
function computeRiskLevel(change1h: number, change3h: number, change6h: number, pressure: number): RiskLevel {
  let score = 0;

  // 1時間変化スコア（最大3点）
  const abs1h = Math.abs(change1h);
  if (abs1h >= 4) score += 3;
  else if (abs1h >= 3) score += 2;
  else if (abs1h >= 2) score += 1;

  // 3時間累積変化スコア（最大3点）
  const abs3h = Math.abs(change3h);
  if (abs3h >= 8) score += 3;
  else if (abs3h >= 6) score += 2;
  else if (abs3h >= 4) score += 1;

  // 6時間累積変化スコア（最大2点）
  const abs6h = Math.abs(change6h);
  if (abs6h >= 10) score += 2;
  else if (abs6h >= 6) score += 1;

  // 絶対気圧スコア（低気圧ペナルティ、最大3点）
  if (pressure <= 995) score += 3;
  else if (pressure <= 1000) score += 2;
  else if (pressure <= 1005) score += 1;

  if (score >= 7) return 5;
  if (score >= 5) return 4;
  if (score >= 3) return 3;
  if (score >= 1) return 2;
  return 1;
}

function analyzeRisk(hourly: WeatherHourly): HourRisk[] {
  const now = new Date();
  const startIdx = hourly.time.findIndex(t => new Date(t) >= now);
  if (startIdx === -1) return [];

  const p = hourly.pressure_msl;
  const t = hourly.temperature_2m;
  const n = p.length;
  const risks: HourRisk[] = [];

  for (let i = startIdx; i < Math.min(startIdx + 24, n); i++) {
    const change1h = i + 1 < n ? p[i + 1] - p[i] : 0;
    const change3h = i + 3 < n ? p[i + 3] - p[i] : change1h * 3;
    const change6h = i + 6 < n ? p[i + 6] - p[i] : change1h * 6;
    risks.push({
      time: new Date(hourly.time[i]),
      pressure: p[i],
      temperature: t[i],
      change1h,
      change3h,
      change6h,
      riskLevel: computeRiskLevel(change1h, change3h, change6h, p[i]),
    });
  }
  return risks;
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

function formatMorningBriefing(risks: HourRisk[]): string {
  const today = new Date().toLocaleDateString("ja-JP", {
    month: "numeric", day: "numeric", weekday: "short",
  });

  // 今後12時間の最大リスク
  const dayRisks = risks.slice(0, 12);
  const maxRisk = Math.max(...dayRisks.map(r => r.riskLevel)) as RiskLevel;
  const riskInfo = RISK[maxRisk];

  // 3時間ブロックで表示
  const blocks: string[] = [];
  for (let i = 0; i < Math.min(dayRisks.length, 12); i += 3) {
    const block = risks[i];
    if (!block) break;
    const startHour = block.time.getHours();
    const endHour = startHour + 3;
    const blockMax = Math.max(...risks.slice(i, i + 3).map(r => r.riskLevel)) as RiskLevel;
    const bi = RISK[blockMax];
    const temp = Math.round(block.temperature);
    blocks.push(`${String(startHour).padStart(2)}〜${endHour}時  ${block.pressure.toFixed(0)}hPa  ${temp}°C  ${bi.emoji} ${bi.label}`);
  }

  // ピーク時間帯
  const peak = dayRisks.reduce((a, b) => a.riskLevel >= b.riskLevel ? a : b);
  const peakHour = peak.time.getHours();

  let advice: string;
  if (maxRisk >= 4) {
    advice = `\n⚠️ ${peakHour}時台が最も危険です\n💊 外出前に薬を飲んでおくことをおすすめします`;
  } else if (maxRisk === 3) {
    advice = `\n⚠️ ${peakHour}時台に注意が必要です\n💊 薬を持ち歩くと安心です`;
  } else {
    advice = `\n✅ 今日は気象病リスクが低めです`;
  }

  return `☀️ 今日の気象病予報（${CONFIG.location}）
${today}

${riskInfo.emoji} ${riskInfo.bar} ${riskInfo.label}（${maxRisk}/5）

━━━ 時間帯別リスク ━━━
${blocks.join("\n")}
${advice}`;
}

function formatAlertMessage(risks: HourRisk[], alertIdx: number): string {
  const alert = risks[alertIdx];
  const riskInfo = RISK[alert.riskLevel];

  // 前後の気圧推移（最大6時間分）
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
  const direction = totalChange < 0 ? "急降下📉" : "急上昇📈";
  const alertHour = alert.time.getHours();

  return `⚠️ 気象病アラート（${CONFIG.location}）

${riskInfo.emoji} ${riskInfo.bar} ${riskInfo.label}（${alert.riskLevel}/5）

気圧${direction}  ${changeStr}hPa

━━━ 気圧の推移 ━━━
${trendLines.join("\n")}

⏰ ${alertHour}時台から症状が出やすくなります
💊 今が薬を飲む目安です
🫁 深呼吸・耳周りマッサージも効果的`;
}

// 現在がリスク未満で1〜2時間後にリスク3以上になる場合にアラート
function shouldSendAlert(risks: HourRisk[]): number | null {
  const currentRisk = risks[0]?.riskLevel ?? 1;
  if (currentRisk >= 3) return null; // 既に危険域なので再通知しない

  for (let i = 1; i <= 2 && i < risks.length; i++) {
    if (risks[i].riskLevel >= 3) {
      log("info", "アラート条件成立", {
        hoursAhead: i,
        currentRisk,
        upcomingRisk: risks[i].riskLevel,
        time: risks[i].time.toISOString(),
      });
      return i;
    }
  }
  return null;
}

async function sendLineMessage(message: string): Promise<void> {
  const token = process.env.LINE_CHANNEL_TOKEN;
  const userId = process.env.LINE_USER_ID;

  if (!token || !userId) {
    log("info", "[テストモード] 送信予定メッセージ");
    console.log("---");
    console.log(message);
    console.log("---");
    return;
  }

  const res = await fetch("https://api.line.me/v2/bot/message/push", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ to: userId, messages: [{ type: "text", text: message }] }),
  });

  if (!res.ok) {
    const errorText = await res.text();
    throw new AppError(`LINE API ${res.status}`, "LINE_API_ERROR", { status: res.status, response: errorText });
  }

  log("info", "LINE通知送信完了");
}

async function main() {
  try {
    log("info", "気圧チェック開始", { location: CONFIG.location });

    if (isQuietHours()) {
      log("info", "通知オフ時間帯のためスキップ");
      return;
    }

    const hourly = await fetchWeatherForecast();
    const risks = analyzeRisk(hourly);

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
      isMorning: isMorningBriefingTime(),
    });

    // 朝の予報（8:30〜9:30）
    if (isMorningBriefingTime()) {
      const message = formatMorningBriefing(risks);
      await sendLineMessage(message);
      log("info", "朝の予報を送信", { maxRisk12h });
      return;
    }

    // 直前アラート
    const alertIdx = shouldSendAlert(risks);
    if (alertIdx !== null) {
      const message = formatAlertMessage(risks, alertIdx);
      await sendLineMessage(message);
      log("info", "気象病アラートを送信", { riskLevel: risks[alertIdx]?.riskLevel });
    } else {
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
