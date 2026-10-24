import Foundation

// Publish state only after an atomic disk write succeeds. A corrupt existing file is never
// silently replaced with an empty catalog. Callers own actor/queue confinement.
final class DurableJSON<Value: Codable> {
    private(set) var value: Value
    private let url: URL
    private let writer: (Data, URL) throws -> Void

    init(url: URL, defaultValue: Value, writer: ((Data, URL) throws -> Void)? = nil) throws {
        self.url = url
        self.writer = writer ?? { data, url in
            #if os(iOS)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: url, options: .atomic)
            #endif
        }
        if FileManager.default.fileExists(atPath: url.path) {
            value = try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
        } else {
            value = defaultValue
        }
    }

    func commit(_ candidate: Value) throws {
        let bytes = try JSONEncoder().encode(candidate)
        try writer(bytes, url)
        value = candidate
    }
}
