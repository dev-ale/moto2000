import Foundation

/// Generates GPX XML from route points and optional trip metadata.
public enum GPXExporter {

    /// Creates a GPX 1.1 XML string from route points and optional trip summary.
    ///
    /// - Parameters:
    ///   - points: The route coordinates to export.
    ///   - trip: Optional trip metadata used for the `<metadata>` element.
    /// - Returns: A UTF-8 GPX XML string.
    public static func export(points: [RoutePoint], trip: TripSummary? = nil) -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<gpx version=\"1.1\" creator=\"ScramScreen\">\n"

        // Metadata
        let rideName: String
        let rideTime: String
        if let trip {
            rideName = "Ride - \(Self.metadataDateFormatter.string(from: trip.date))"
            rideTime = Self.iso8601Formatter.string(from: trip.date)
        } else {
            rideName = "Ride"
            rideTime = Self.iso8601Formatter.string(from: Date())
        }
        xml += "  <metadata>\n"
        xml += "    <name>\(escapeXML(rideName))</name>\n"
        xml += "    <time>\(rideTime)</time>\n"
        xml += "  </metadata>\n"

        // Track
        xml += "  <trk>\n"
        xml += "    <name>Ride</name>\n"
        xml += "    <trkseg>\n"
        for point in points {
            let latStr = String(format: "%.6f", point.latitude)
            let lonStr = String(format: "%.6f", point.longitude)
            if let altitude = point.altitude {
                let eleStr = String(format: "%.1f", altitude)
                xml += "      <trkpt lat=\"\(latStr)\" lon=\"\(lonStr)\">"
                xml += "<ele>\(eleStr)</ele>"
                xml += "</trkpt>\n"
            } else {
                xml += "      <trkpt lat=\"\(latStr)\" lon=\"\(lonStr)\"/>\n"
            }
        }
        xml += "    </trkseg>\n"
        xml += "  </trk>\n"
        xml += "</gpx>\n"

        return xml
    }

    /// Writes the GPX string to a temporary file and returns its URL.
    ///
    /// - Parameters:
    ///   - points: The route coordinates to export.
    ///   - trip: Optional trip metadata.
    /// - Returns: A file URL for the temporary `.gpx` file, or nil on failure.
    public static func exportToFile(points: [RoutePoint], trip: TripSummary? = nil) -> URL? {
        let gpx = export(points: points, trip: trip)
        let dateStr: String
        if let trip {
            dateStr = Self.fileDateFormatter.string(from: trip.date)
        } else {
            dateStr = Self.fileDateFormatter.string(from: Date())
        }
        let fileName = "ScramScreen-\(dateStr).gpx"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        guard let data = gpx.data(using: .utf8) else { return nil }
        do {
            try data.write(to: tempURL, options: .atomic)
            return tempURL
        } catch {
            return nil
        }
    }

    // MARK: - Private

    private static func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static let metadataDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMMM d, yyyy"
        return f
    }()

    private static let fileDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // nonisolated(unsafe) because ISO8601DateFormatter is not Sendable but our
    // usage is safe — the formatter is created once and never mutated afterward.
    nonisolated(unsafe) private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
