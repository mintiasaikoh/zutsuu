// /Users/mymac/zutsuu/ios/ZutsuuApp/Sources/LocationProvider.swift
// 現在地を 1 回だけ取得して Coordinate にする。
// 位置情報を端末外へ出さない設計（設計書 §9）の入口を 1 箇所にするため。
// 位置が来ないまま待ち続けると「取得中」のまま再取得も塞がるので、時間制限を設ける。
// 関連: ForecastPipeline.swift
import CoreLocation
import RiskEngine

enum LocationError: Error {
    case denied
    case unavailable
}

/// 位置の取得口。テストでは差し替える。
protocol LocationProviding: Sendable {
    @MainActor func current() async throws -> Coordinate
}

struct LocationProvider: LocationProviding, Sendable {
    /// 位置が得られないまま待つ上限。超えたら `LocationError.unavailable`。
    var timeout: Duration = .seconds(10)

    /// 許可を求め、最初に得られた位置を返す。拒否・制限は `LocationError.denied`。
    @MainActor
    func current() async throws -> Coordinate {
        let manager = CLLocationManager()
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        let timeout = timeout
        return try await withThrowingTaskGroup(of: Coordinate.self) { group in
            group.addTask { try await Self.firstLocation() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw LocationError.unavailable
            }
            defer { group.cancelAll() }
            guard let coordinate = try await group.next() else { throw LocationError.unavailable }
            return coordinate
        }
    }

    private static func firstLocation() async throws -> Coordinate {
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
