const CONFIG = {
  latitude: process.env.LATITUDE ? Number(process.env.LATITUDE) : 35.74,
  longitude: process.env.LONGITUDE ? Number(process.env.LONGITUDE) : 139.65,
  location: process.env.LOCATION || "練馬区",
  // 従来の1時間単位の急変検知（後方互換性のため残す）
  hourlyChangeThreshold: process.env.HOURLY_CHANGE_THRESHOLD ? Number(process.env.HOURLY_CHANGE_THRESHOLD) : 2,
  // 新しい長期間累積変化の設定
  cumulativeChangeThreshold: process.env.CUMULATIVE_CHANGE_THRESHOLD ? Number(process.env.CUMULATIVE_CHANGE_THRESHOLD) : 5, // 12時間で±5hPa
  cumulativeHours: process.env.CUMULATIVE_HOURS ? Number(process.env.CUMULATIVE_HOURS) : 12, // 累積計算の時間幅
  alertBeforeHours: process.env.ALERT_BEFORE_HOURS ? Number(process.env.ALERT_BEFORE_HOURS) : 1, // 変化開始の何時間前まで通知するか
  quietHours: {
    start: process.env.QUIET_START ? Number(process.env.QUIET_START) : 22,
    end: process.env.QUIET_END ? Number(process.env.QUIET_END) : 8.5
  },
  retryCount: process.env.RETRY_COUNT ? Number(process.env.RETRY_COUNT) : 3,
  retryDelay: process.env.RETRY_DELAY ? Number(process.env.RETRY_DELAY) : 2000,
};

interface HourlyData {
  time: string[];
  pressure_msl: number[];
}

interface ApiError {
  message: string;
  status?: number;
  details?: string;
}

class AppError extends Error {
  constructor(
    message: string,
    public code: string,
    public details?: any
  ) {
    super(message);
    this.name = 'AppError';
  }
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
  alertType: "sudden" | "cumulative"; // 急変 or 累積変化
  duration?: number; // 累積変化の場合の期間（時間）
}

function log(level: 'info' | 'warn' | 'error', message: string, data?: any): void {
  const timestamp = new Date().toISOString();
  const entry = { timestamp, level, message, ...(data && { data }) };
  console.log(JSON.stringify(entry));
}

function validateConfig(): void {
  const { latitude, longitude, hourlyChangeThreshold, alertBeforeHours } = CONFIG;
  
  if (latitude < -90 || latitude > 90) {
    throw new AppError('緯度が無効', 'INVALID_LATITUDE', { latitude });
  }
  if (longitude < -180 || longitude > 180) {
    throw new AppError('経度が無効', 'INVALID_LONGITUDE', { longitude });
  }
  if (hourlyChangeThreshold <= 0 || hourlyChangeThreshold > 50) {
    throw new AppError('気圧変化閾値が無効', 'INVALID_THRESHOLD', { hourlyChangeThreshold });
  }
  if (alertBeforeHours < 0.1 || alertBeforeHours > 24) {
    throw new AppError('通知タイミングが無効', 'INVALID_ALERT_BEFORE', { alertBeforeHours });
  }
}

function isQuietHours(): boolean {
  const now = new Date();
  const hour = now.getHours() + now.getMinutes() / 60;
  const { start, end } = CONFIG.quietHours;

  // 22:00〜23:59 または 0:00〜8:30
  if (start > end) {
    return hour >= start || hour < end;
  }
  return hour >= start && hour < end;
}

async function fetchWithRetry(url: string): Promise<Response> {
  const { retryCount, retryDelay } = CONFIG;
  let lastError: Error;

  for (let i = 0; i < retryCount; i++) {
    try {
      log('info', `API呼び出し試行 ${i + 1}/${retryCount}`, { url });
      const res = await fetch(url);
      
      if (res.ok) {
        log('info', 'API呼び出し成功', { status: res.status });
        return res;
      }
      
      const errorText = await res.text();
      lastError = new AppError(
        `API呼び出しエラー: ${res.status}`,
        'API_ERROR',
        { status: res.status, response: errorText }
      );
      
    } catch (err) {
      lastError = err instanceof Error ? err : new Error(String(err));
      log('warn', 'API呼び出し失敗', { 
        attempt: i + 1, 
        error: lastError.message,
        willRetry: i < retryCount - 1
      });
    }
    
    if (i < retryCount - 1) {
      await new Promise(r => setTimeout(r, retryDelay));
    }
  }
  
  throw new AppError(
    `${retryCount}回のリトライ後もAPI呼び出しに失敗`,
    'API_RETRY_EXHAUSTED',
    lastError
  );
}

async function fetchPressureForecast(): Promise<HourlyData> {
  try {
    validateConfig();
    
    const url = new URL("https://api.open-meteo.com/v1/forecast");
    url.searchParams.set("latitude", CONFIG.latitude.toString());
    url.searchParams.set("longitude", CONFIG.longitude.toString());
    url.searchParams.set("hourly", "pressure_msl");
    url.searchParams.set("timezone", "Asia/Tokyo");
    url.searchParams.set("forecast_days", "2");

    log('info', '天気予報API呼び出し開始', {
      latitude: CONFIG.latitude,
      longitude: CONFIG.longitude,
      location: CONFIG.location
    });

    const res = await fetchWithRetry(url.toString());
    const data: WeatherResponse = await res.json();
    
    if (!data.hourly?.time?.length || !data.hourly?.pressure_msl?.length) {
      throw new AppError('APIレスポンスが不正', 'INVALID_RESPONSE', data);
    }
    
    log('info', '天気予報API呼び出し完了', {
      dataPoints: data.hourly.time.length
    });
    
    return data.hourly;
  } catch (err) {
    if (err instanceof AppError) throw err;
    throw new AppError('天気予報取得エラー', 'FETCH_FORECAST_ERROR', err);
  }
}

function findCumulativePressureChange(hourly: HourlyData): PressureAlert | null {
  try {
    const now = new Date();
    const currentIndex = hourly.time.findIndex((t) => new Date(t) >= now);

    if (currentIndex === -1 || currentIndex + CONFIG.cumulativeHours >= hourly.time.length) {
      log('info', '累積変化分析データ不足', { currentIndex, totalLength: hourly.time.length });
      return null;
    }

    // 現在時刻以降のみ検索（直近の変化のみ検出）
    const startSearchIdx = currentIndex;
    const endSearchIdx = Math.min(currentIndex + 6, hourly.time.length - CONFIG.cumulativeHours);
    
    for (let startIdx = startSearchIdx; startIdx < endSearchIdx; startIdx++) {
      // JSTに変換（Open-MeteoはUTCで返すため）
      const startTime = new Date(hourly.time[startIdx]);
      const endIdx = Math.min(startIdx + CONFIG.cumulativeHours, hourly.time.length - 1);
      const endTime = new Date(hourly.time[endIdx]);
      
      const startPressure = hourly.pressure_msl[startIdx];
      const endPressure = hourly.pressure_msl[endIdx];
      const totalChange = endPressure - startPressure;

      if (Math.abs(totalChange) >= CONFIG.cumulativeChangeThreshold) {
        const hoursFromNow = (startTime.getTime() - now.getTime()) / (1000 * 60 * 60);

        // 変化開始の0〜alertBeforeHours時間前のみ（事前通知、変化開始後は通知しない）
        const shouldAlert = hoursFromNow >= 0 && hoursFromNow <= CONFIG.alertBeforeHours;

        log('info', '通知タイミング判定', {
          hoursFromNow: hoursFromNow.toFixed(1),
          alertBeforeHours: CONFIG.alertBeforeHours,
          shouldAlert
        });
        
        if (shouldAlert) {
          // 詳細な時系列データを構築
          const hourlyChanges: { time: Date; pressure: number; change: number }[] = [];
          for (let i = startIdx; i < endIdx; i++) {
            const time = new Date(hourly.time[i + 1]);
            const pressure = hourly.pressure_msl[i + 1];
            const change = hourly.pressure_msl[i + 1] - hourly.pressure_msl[i];
            hourlyChanges.push({ time, pressure, change });
          }
          
          log('info', '累積気圧変化を検出', {
            startTime: startTime.toISOString(),
            endTime: endTime.toISOString(),
            totalChange,
            duration: CONFIG.cumulativeHours,
            hoursFromNow: hoursFromNow.toFixed(1)
          });

          return {
            changeStartTime: startTime,
            alertTime: now,
            hourlyChanges,
            totalChange,
            direction: totalChange > 0 ? "up" : "down",
            alertType: "cumulative",
            duration: CONFIG.cumulativeHours
          };
        }
      }
    }

    return null;
  } catch (err) {
    throw new AppError('累積気圧変化分析エラー', 'CUMULATIVE_ANALYSIS_ERROR', err);
  }
}

function findUpcomingPressureChange(hourly: HourlyData): PressureAlert | null {
  try {
    const now = new Date();
    const currentIndex = hourly.time.findIndex((t) => new Date(t) >= now);
    
    if (currentIndex === -1 || currentIndex + 3 >= hourly.time.length) {
      log('info', '分析データ不足', { currentIndex, totalLength: hourly.time.length });
      return null;
    }

    // 今後12時間の毎時変化を計算
    const hourlyChanges: { time: Date; pressure: number; change: number }[] = [];
    for (let i = currentIndex; i < Math.min(currentIndex + 12, hourly.time.length - 1); i++) {
      const time = new Date(hourly.time[i + 1]);
      const pressure = hourly.pressure_msl[i + 1];
      const change = hourly.pressure_msl[i + 1] - hourly.pressure_msl[i];
      
      if (isNaN(pressure) || isNaN(change)) {
        log('warn', '気圧データに異常値', { index: i, pressure, change });
        continue;
      }
      
      hourlyChanges.push({ time, pressure, change });
    }

    log('info', '気圧変化分析完了', { analysisHours: hourlyChanges.length });

    // 急変開始ポイントを探す（閾値以上の変化が始まる時点）
    for (let i = 0; i < hourlyChanges.length; i++) {
      const h = hourlyChanges[i];
      const absChange = Math.abs(h.change);

      if (absChange >= CONFIG.hourlyChangeThreshold) {
        const hoursUntilChange = (h.time.getTime() - now.getTime()) / (1000 * 60 * 60);

        // デバッグ: 気圧変化検出ログ
        const alertWindow = CONFIG.alertBeforeHours;
        const willAlert = hoursUntilChange >= alertWindow - 0.5 && hoursUntilChange <= alertWindow + 0.5;
        log('info', '気圧変化検出', {
          time: h.time.toISOString(),
          change: h.change,
          hoursUntilChange: hoursUntilChange.toFixed(2),
          alertWindow: `${alertWindow - 0.5}-${alertWindow + 0.5}h`,
          willAlert
        });

        // 通知タイミング: 急変のalertBeforeHours時間前（±0.5時間の範囲でヒット）
        if (willAlert) {
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

          log('info', '通知対象の気圧変化を検出', {
            changeStartTime: h.time.toISOString(),
            direction,
            totalChange,
            hoursUntilChange: hoursUntilChange.toFixed(1)
          });

          return {
            changeStartTime: h.time,
            alertTime: now,
            hourlyChanges: relevantChanges,
            totalChange,
            direction,
            alertType: "sudden"
          };
        }
      }
    }

    return null;
  } catch (err) {
    throw new AppError('気圧変化分析エラー', 'PRESSURE_ANALYSIS_ERROR', err);
  }
}

function formatMessage(alert: PressureAlert): string {
  const now = new Date();
  const currentDate = now.toLocaleDateString("ja-JP", { 
    month: "numeric", 
    day: "numeric", 
    weekday: "short" 
  });
  const currentTime = now.toLocaleTimeString("ja-JP", { 
    hour: "2-digit", 
    minute: "2-digit" 
  });

  const startTime = alert.changeStartTime;
  const startTimeStr = startTime.toLocaleTimeString("ja-JP", { hour: "2-digit", minute: "2-digit" });

  const duration = alert.duration || alert.hourlyChanges.length;
  const endTime = new Date(startTime.getTime() + duration * 60 * 60 * 1000);
  const endTimeStr = endTime.toLocaleTimeString("ja-JP", { hour: "2-digit", minute: "2-digit" });

  // 日をまたぐ場合の表記
  const isNextDay = endTime.getDate() !== startTime.getDate();
  const endTimeDisplay = isNextDay ? `翌${endTimeStr}` : endTimeStr;

  const changeNum = alert.totalChange > 0 ? `+${alert.totalChange.toFixed(0)}` : alert.totalChange.toFixed(0);

  const directionIcon = alert.direction === "down" ? "🌧️" : "🌤️";
  const directionText = alert.direction === "down" ? "下がります" : "上がります";

  return `${directionIcon} もうすぐ気圧が${directionText}
${startTimeStr}〜${endTimeDisplay}で${changeNum}hPa（${CONFIG.location}）

薬を飲むなら今ごろが目安です`;
}

async function sendLineMessage(message: string): Promise<void> {
  const token = process.env.LINE_CHANNEL_TOKEN;
  const userId = process.env.LINE_USER_ID;

  if (!token || !userId) {
    log('info', '[テストモード] LINE認証情報未設定');
    log('info', '送信予定メッセージ:', { message });
    return;
  }

  try {
    log('info', 'LINE通知送信開始');
    
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
      const errorText = await res.text();
      throw new AppError(
        `LINE API エラー: ${res.status}`,
        'LINE_API_ERROR',
        { status: res.status, response: errorText }
      );
    }

    log('info', 'LINE通知送信完了');
  } catch (err) {
    if (err instanceof AppError) throw err;
    throw new AppError('LINE通知送信エラー', 'LINE_SEND_ERROR', err);
  }
}

async function main() {
  try {
    log('info', '気圧チェック開始', {
      location: CONFIG.location,
      threshold: CONFIG.hourlyChangeThreshold,
      alertBefore: CONFIG.alertBeforeHours,
      quietHours: CONFIG.quietHours
    });

    // 夜間は通知しない
    if (isQuietHours()) {
      log('info', '通知オフ時間帯のためスキップ');
      return;
    }

    const hourly = await fetchPressureForecast();
    
    // 新しい累積変化検知を優先
    let alert = findCumulativePressureChange(hourly);
    
    // 累積変化がない場合は従来の急変検知
    if (!alert) {
      alert = findUpcomingPressureChange(hourly);
    }

    if (alert) {
      const message = formatMessage(alert);
      await sendLineMessage(message);
      log('info', '気圧アラート送信完了', { alertType: alert.alertType });
    } else {
      log('info', '直近で通知すべき気圧変化なし');

      // デバッグ: 今後の変化を表示
      const now = new Date();
      const currentIndex = hourly.time.findIndex((t) => new Date(t) >= now);
      const upcomingChanges = [];
      
      for (let i = currentIndex; i < currentIndex + 6 && i < hourly.time.length - 1; i++) {
        const time = new Date(hourly.time[i + 1]);
        const change = hourly.pressure_msl[i + 1] - hourly.pressure_msl[i];
        upcomingChanges.push({
          time: time.toLocaleTimeString("ja-JP", { hour: "2-digit", minute: "2-digit" }),
          pressure: hourly.pressure_msl[i + 1].toFixed(1),
          change: change.toFixed(1)
        });
      }
      
      log('info', '今後6時間の気圧変化', { changes: upcomingChanges });
    }
  } catch (err) {
    if (err instanceof AppError) {
      log('error', err.message, { code: err.code, details: err.details });
    } else {
      log('error', '予期しないエラー', { error: String(err) });
    }
    throw err;
  }
}

main().catch((err) => {
  log('error', 'アプリケーション終了', { error: err instanceof Error ? err.message : String(err) });
  process.exit(1);
});
