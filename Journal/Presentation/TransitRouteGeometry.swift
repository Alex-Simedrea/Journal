import CoreLocation
import MapKit

nonisolated enum TransitRouteGeometry {
    static func coordinates(
        recordedRoute: [RecordedRoutePoint],
        origin: CLLocationCoordinate2D?,
        destination: CLLocationCoordinate2D?,
        bendPositive: Bool
    ) -> [CLLocationCoordinate2D] {
        let recordedCoordinates = recordedRoute.compactMap { point in
            let coordinate = CLLocationCoordinate2D(
                latitude: point.latitude,
                longitude: point.longitude
            )
            return CLLocationCoordinate2DIsValid(coordinate)
                ? coordinate
                : nil
        }
        if recordedCoordinates.count > 1 {
            return recordedCoordinates
        }
        guard let origin,
              let destination,
              CLLocationCoordinate2DIsValid(origin),
              CLLocationCoordinate2DIsValid(destination) else { return [] }
        return curvedCoordinates(
            from: origin,
            to: destination,
            bendPositive: bendPositive
        )
    }

    static func curvedCoordinates(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        bendPositive: Bool
    ) -> [CLLocationCoordinate2D] {
        let start = MKMapPoint(origin)
        let end = MKMapPoint(destination)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(hypot(dx, dy), 1)
        let direction = bendPositive ? 1.0 : -1.0
        let control = MKMapPoint(
            x: (start.x + end.x) / 2
                - dy / length * length * 0.18 * direction,
            y: (start.y + end.y) / 2
                + dx / length * length * 0.18 * direction
        )

        return (0...32).map { index in
            let t = Double(index) / 32
            let inverse = 1 - t
            return MKMapPoint(
                x: inverse * inverse * start.x
                    + 2 * inverse * t * control.x
                    + t * t * end.x,
                y: inverse * inverse * start.y
                    + 2 * inverse * t * control.y
                    + t * t * end.y
            ).coordinate
        }
    }
}
