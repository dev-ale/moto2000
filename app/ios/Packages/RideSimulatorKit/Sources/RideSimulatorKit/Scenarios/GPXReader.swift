import Foundation

/// Minimal GPX 1.1 track reader.
///
/// Only understands `<trkpt lat=… lon=…>` elements with an optional
/// `<ele>` and `<time>` child. That's all ScramScreen needs — full GPX
/// parsing is out of scope.
///
/// The output is an array of ``LocationSample``. If the GPX has timestamps
/// the `scenarioTime` field is set to the offset from the first point;
/// otherwise samples are spaced by ``defaultSampleSpacing``.
public enum GPXReader {
    public static let defaultSampleSpacing: Double = 1.0  // seconds

    public static func parse(_ data: Data, defaultSpacing: Double = defaultSampleSpacing) throws -> [LocationSample] {
        let parser = GPXParser(defaultSpacing: defaultSpacing)
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        guard xmlParser.parse() else {
            throw ScenarioError.decodeFailure("gpx parse failed: \(xmlParser.parserError?.localizedDescription ?? "unknown")")
        }
        return parser.finish()
    }

    public static func parse(contentsOf url: URL) throws -> [LocationSample] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ScenarioError.fileNotFound(url.path)
        }
        return try parse(data)
    }
}

private final class GPXParser: NSObject, XMLParserDelegate {
    private let defaultSpacing: Double
    private var samples: [LocationSample] = []
    private var currentLat: Double?
    private var currentLon: Double?
    private var currentEle: Double = 0
    private var currentTime: Date?
    private var firstTime: Date?
    private var indexInTrack: Int = 0
    private var currentElement: String = ""
    private var textBuffer: String = ""

    init(defaultSpacing: Double) {
        self.defaultSpacing = defaultSpacing
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        textBuffer = ""
        if elementName == "trkpt" {
            currentLat = Double(attributeDict["lat"] ?? "")
            currentLon = Double(attributeDict["lon"] ?? "")
            currentEle = 0
            currentTime = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer.append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "ele":
            currentEle = Double(textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        case "time":
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            currentTime = iso.date(from: textBuffer)
                ?? ISO8601DateFormatter().date(from: textBuffer)
        case "trkpt":
            guard let lat = currentLat, let lon = currentLon else { return }
            let scenarioTime: Double
            if let current = currentTime {
                if firstTime == nil { firstTime = current }
                scenarioTime = current.timeIntervalSince(firstTime ?? current)
            } else {
                scenarioTime = Double(indexInTrack) * defaultSpacing
            }
            samples.append(
                LocationSample(
                    scenarioTime: scenarioTime,
                    latitude: lat,
                    longitude: lon,
                    altitudeMeters: currentEle
                )
            )
            indexInTrack += 1
        default:
            break
        }
    }

    func finish() -> [LocationSample] { samples }
}
