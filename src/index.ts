const CONFIG = {
  latitude: 35.74,
  longitude: 139.65,
  location: "練馬区",
  hourlyChangeThreshold: 2, // 1時間あたりこの値以上の変化で「急変」と判定
  alertBeforeHours: 1,      // 急変の何時間前に通知するか
};

interface HourlyData {
  time: string[];
  pressure_msl: number[];
}

interface WeatherResponse {
  hourly: HourlyData;
}

interface PressureAlert {
  changeStartTime: Date;
  alertTime: Date;
  hourlyChanges: { time: Date; pressure: number; change: number }[];
  totalChange: number;
  direction: "up" | "down";
}

async function fetchPressureForecast(): Promise<HourlyData> {
  const url = new URL("https://api.open-meteo.com/v1/forecast");
  url.searchParams.set("latitude", CONFIG.latitude.toString());
  url.searchParams.set("longitude", CONFIG.longitude.toString());
  url.searchParams.set("hourly", "pressure_msl");
  url.searchParams.set("timezone", "Asia/Tokyo");
  url.searchParams.set("forecast_days", "2");

  const res = await fetch(url.toString());
  if (!res.ok) {
    throw new Error(`API error: ${res.status}`);
  }

  const data: WeatherResponse = await res.json();
  return data.hourly;
}

function findUpcomingPressureChange(hourly: HourlyData): PressureAlert | null {
  const now = new Date();
  const currentIndex = hourly.time.findIndex((t) => new Date(t) >= now);
  if (currentIndex === -1 || currentIndex + 3 >= hourly.time.length) return null;

  // 今後12時間の毎時変化を計算
  const hourlyChanges: { time: Date; pressure: number; change: number }[] = [];
  for (let i = currentIndex; i < Math.min(currentIndex + 12, hourly.time.length - 1); i++) {
    const time = new Date(hourly.time[i + 1]);
    const pressure = hourly.pressure_msl[i + 1];
    const change = hourly.pressure_msl[i + 1] - hourly.pressure_msl[i];
    hourlyChanges.push({ time, pressure, change });
  }

  // 急変開始ポイントを探す（閾値以上の変化が始まる時点）
  for (let i = 0; i < hourlyChanges.length; i++) {
    const h = hourlyChanges[i];
    const absChange = Math.abs(h.change);

    if (absChange >= CONFIG.hourlyChangeThreshold) {
      const hoursUntilChange = (h.time.getTime() - now.getTime()) / (1000 * 60 * 60);

      // 通知タイミング: 急変の1時間前（0.5〜1.5時間前の範囲でヒット）
      if (hoursUntilChange >= 0.5 && hoursUntilChange <= 1.5) {
        // 連続する変化の合計を計算
        let totalChange = h.change;
        const direction = h.change > 0 ? "up" : "down";
        const relevantChanges = [h];

        for (let j = i + 1; j < hourlyChanges.length; j++) {
          const next = hourlyChanges[j];
          const sameDirection = (direction === "up" && next.change > 0) ||
                                (direction === "down" && next.change < 0);
          if (sameDirection && Math.abs(next.change) >= 1) {
            totalChange += next.change;
            relevantChanges.push(next);
          } else {
            break;
          }
        }

        return {
          changeStartTime: h.time,
          alertTime: now,
          hourlyChanges: relevantChanges,
          totalChange,
          direction,
        };
      }
    }
  }

  return null;
}

function formatMessage(alert: PressureAlert): string {
  const startTime = alert.changeStartTime;
  const startTimeStr = startTime.toLocaleTimeString("ja-JP", { hour: "2-digit", minute: "2-digit" });

  const duration = alert.hourlyChanges.length;
  const endTime = new Date(startTime.getTime() + duration * 60 * 60 * 1000);
  const endTimeStr = endTime.toLocaleTimeString("ja-JP", { hour: "2-digit", minute: "2-digit" });

  const firstPressure = alert.hourlyChanges[0].pressure - alert.hourlyChanges[0].change;
  const lastPressure = alert.hourlyChanges[alert.hourlyChanges.length - 1].pressure;
  const changeNum = alert.totalChange > 0 ? `+${alert.totalChange.toFixed(0)}` : alert.totalChange.toFixed(0);

  if (alert.direction === "down") {
    return `⚠️ 気圧低下アラート

📍 ${CONFIG.location}
🕐 ${startTimeStr}〜${endTimeStr}
📉 ${firstPressure.toFixed(0)} → ${lastPressure.toFixed(0)} hPa（${changeNum}）

💊 今が薬を飲むタイミング`;
  } else {
    return `⚠️ 気圧上昇アラート

📍 ${CONFIG.location}
🕐 ${startTimeStr}〜${endTimeStr}
📈 ${firstPressure.toFixed(0)} → ${lastPressure.toFixed(0)} hPa（${changeNum}）

💊 今が薬を飲むタイミング`;
  }
}

async function sendLineMessage(message: string): Promise<void> {
  const token = process.env.LINE_CHANNEL_TOKEN;
  const userId = process.env.LINE_USER_ID;

  if (!token || !userId) {
    console.log("[テストモード] LINE_CHANNEL_TOKEN または LINE_USER_ID 未設定");
    console.log("送信予定メッセージ:");
    console.log(message);
    return;
  }

  const res = await fetch("https://api.line.me/v2/bot/message/push", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      to: userId,
      messages: [{ type: "text", text: message }],
    }),
  });

  if (!res.ok) {
    const error = await res.text();
    throw new Error(`LINE API error: ${res.status} - ${error}`);
  }

  console.log("LINE通知を送信しました");
}

async function main() {
  console.log(`気圧チェック開始: ${CONFIG.location}`);
  console.log(`急変閾値: 1時間あたり ±${CONFIG.hourlyChangeThreshold}hPa`);
  console.log(`通知タイミング: 急変の${CONFIG.alertBeforeHours}時間前`);
  console.log("");

  const hourly = await fetchPressureForecast();
  const alert = findUpcomingPressureChange(hourly);

  if (alert) {
    const message = formatMessage(alert);
    await sendLineMessage(message);
  } else {
    console.log("直近で通知すべき気圧変化なし");

    // デバッグ: 今後の変化を表示
    const now = new Date();
    const currentIndex = hourly.time.findIndex((t) => new Date(t) >= now);
    console.log("\n今後6時間の気圧変化:");
    for (let i = currentIndex; i < currentIndex + 6 && i < hourly.time.length - 1; i++) {
      const time = new Date(hourly.time[i + 1]);
      const change = hourly.pressure_msl[i + 1] - hourly.pressure_msl[i];
      const timeStr = time.toLocaleTimeString("ja-JP", { hour: "2-digit", minute: "2-digit" });
      console.log(`  ${timeStr}: ${hourly.pressure_msl[i + 1].toFixed(1)} hPa (${change >= 0 ? "+" : ""}${change.toFixed(1)})`);
    }
  }
}

main().catch((err) => {
  console.error("エラー:", err);
  process.exit(1);
});
