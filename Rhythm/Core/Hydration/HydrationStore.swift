import Foundation

actor HydrationStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL = HydrationStore.defaultFileURL()) {
        self.fileURL = fileURL

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    func loadState() throws -> HydrationState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .defaultState
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(HydrationState.self, from: data)
    }

    func saveState(_ state: HydrationState) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: [.atomic])
    }

    static func defaultFileURL() -> URL {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]

        return applicationSupportURL
            .appendingPathComponent("HydrationCore", isDirectory: true)
            .appendingPathComponent("hydration.json", isDirectory: false)
    }
}
