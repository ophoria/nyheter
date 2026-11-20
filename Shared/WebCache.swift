import Foundation

/// Small disk cache for the card slides' data (weather, prices, Wikipedia). The screen saver starts
/// many times a day; this keeps it from asking the same services again and again, and gives
/// something to show when a service doesn't answer. Each process keeps its own copy.
enum WebCache {
    private static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Nyheter/cache", isDirectory: true)
    }

    private static func file(_ url: URL) -> URL {
        // FNV-1a hash of the address: short, stable file names.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in url.absoluteString.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return folder.appendingPathComponent(String(hash, radix: 16) + ".data")
    }

    static let userAgent = "Nyheter/1.0 (macOS screen saver)"

    /// The response for `url`, from the cache when it is younger than `maxAge`, else from the network.
    /// A failed request falls back to an older copy. Calls back on the main queue.
    static func get(_ url: URL, maxAge: TimeInterval, completion: @escaping (Data?) -> Void) {
        let path = file(url)
        let saved = try? Data(contentsOf: path)
        let modified = (try? FileManager.default.attributesOfItem(atPath: path.path))?[.modificationDate] as? Date
        if let saved, let modified, Date().timeIntervalSince(modified) < maxAge {
            DispatchQueue.main.async { completion(saved) }
            return
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let ok = ((response as? HTTPURLResponse)?.statusCode).map { (200..<300).contains($0) } ?? false
            if ok, let data, !data.isEmpty {
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try? data.write(to: path, options: .atomic)
            }
            DispatchQueue.main.async { completion(ok && data?.isEmpty == false ? data : saved) }
        }.resume()
    }
}
