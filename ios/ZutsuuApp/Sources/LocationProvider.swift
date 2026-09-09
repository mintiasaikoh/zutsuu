// /Users/mymac/zutsuu/ios/ZutsuuApp/Sources/LocationProvider.swift
// 現在地を 1 回だけ取得して Coordinate にする。
// 位置情報を端末外へ出さない設計（設計書 §9）の入口を 1 箇所にするため。
// 関連: ForecastPipeline.swift
import CoreLocation
import RiskEngine

enum LocationError: Error {
    case denied
    case unavailable
}

struct LocationProvider: Sendable {
    /// 許可を求め、最初に得られた位置を返す。拒否・制限は `LocationError.denied`。
    @MainActor
    func current() async throws -> Coordinate {
        let manager = CLLocationManager()
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        for try await update in CLLocationUpdate.liveUpdates() {
            if update.authorizationDenied || update.authorizationRestricted {
                throw LocationError.denied
            }
            if let location = update.location {
                return Coordinate(latitude: location.coordinate.latitude,
                                  longitude: location.coordinate.longitude)
            }
        }
        throw LocationError.unavailable
    }
}
