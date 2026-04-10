import Foundation
import ScramCore

/// Seeds a sample trip into the history on first launch so the user
/// can see the Fahrten tab with a realistic entry and map.
enum SampleTripSeeder {
    private static let seededKey = "scramscreen.sampleTripSeeded"

    static func seedIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: seededKey) else { return }
        defaults.set(true, forKey: seededKey)

        let tripId = UUID()

        // A realistic 10-minute ride through Basel:
        // Barfüsserplatz → Mittlere Brücke → Wettsteinbrücke →
        // Riehenstrasse → retour via St. Alban
        let summary = TripSummary(
            id: tripId,
            date: Date().addingTimeInterval(-3600), // 1 hour ago
            duration: 612, // 10m 12s
            distanceKm: 5.8,
            avgSpeedKmh: 34.1,
            maxSpeedKmh: 52.0,
            elevationGainM: 42,
            hasRoute: true
        )

        TripHistoryStore().save(summary)
        RouteStorage().save(tripId: tripId, coordinates: baselRoute)
    }

    // MARK: - Basel route coordinates

    private static let baselRoute: [RoutePoint] = {
        // Barfüsserplatz → Mittlere Brücke → Kleinbasel →
        // Wettsteinbrücke → Grossbasel → St. Alban → back
        let raw: [(Double, Double)] = [
            // Start: Barfüsserplatz
            (47.55410, 7.58890),
            (47.55430, 7.58920),
            (47.55460, 7.58960),
            // Steinenberg heading east
            (47.55490, 7.59020),
            (47.55510, 7.59080),
            (47.55530, 7.59150),
            (47.55540, 7.59220),
            // Approach Mittlere Brücke
            (47.55560, 7.59280),
            (47.55590, 7.59310),
            (47.55630, 7.59320),
            (47.55680, 7.59310),
            // On Mittlere Brücke (crossing Rhine north)
            (47.55730, 7.59300),
            (47.55790, 7.59290),
            (47.55850, 7.59280),
            (47.55910, 7.59270),
            (47.55970, 7.59260),
            (47.56030, 7.59250),
            // Kleinbasel - Greifengasse
            (47.56090, 7.59250),
            (47.56150, 7.59260),
            (47.56210, 7.59280),
            (47.56270, 7.59310),
            // Turn east on Clarastrasse
            (47.56300, 7.59380),
            (47.56310, 7.59460),
            (47.56320, 7.59540),
            (47.56330, 7.59630),
            (47.56340, 7.59720),
            (47.56350, 7.59810),
            // Riehenstrasse heading northeast
            (47.56380, 7.59900),
            (47.56420, 7.59990),
            (47.56470, 7.60070),
            (47.56520, 7.60150),
            (47.56570, 7.60230),
            (47.56620, 7.60300),
            (47.56670, 7.60370),
            // Turn south toward Wettsteinbrücke
            (47.56650, 7.60320),
            (47.56610, 7.60250),
            (47.56560, 7.60170),
            (47.56510, 7.60080),
            (47.56450, 7.59990),
            (47.56390, 7.59910),
            // Wettsteinplatz
            (47.56330, 7.59830),
            (47.56270, 7.59750),
            (47.56220, 7.59660),
            // Wettsteinbrücke (crossing Rhine south)
            (47.56160, 7.59600),
            (47.56100, 7.59560),
            (47.56030, 7.59530),
            (47.55960, 7.59510),
            (47.55890, 7.59490),
            (47.55820, 7.59480),
            // Grossbasel - St. Alban
            (47.55760, 7.59470),
            (47.55700, 7.59490),
            (47.55640, 7.59530),
            (47.55580, 7.59580),
            (47.55520, 7.59640),
            // St. Alban-Graben heading south
            (47.55460, 7.59700),
            (47.55400, 7.59750),
            (47.55340, 7.59790),
            (47.55280, 7.59810),
            (47.55220, 7.59800),
            // Turn west back toward Barfüsserplatz
            (47.55200, 7.59740),
            (47.55210, 7.59660),
            (47.55230, 7.59580),
            (47.55260, 7.59500),
            (47.55290, 7.59420),
            (47.55320, 7.59340),
            (47.55350, 7.59260),
            (47.55370, 7.59180),
            (47.55380, 7.59100),
            (47.55390, 7.59020),
            // Return to Barfüsserplatz
            (47.55400, 7.58940),
            (47.55410, 7.58890),
        ]
        return raw.map { RoutePoint(latitude: $0.0, longitude: $0.1) }
    }()
}
