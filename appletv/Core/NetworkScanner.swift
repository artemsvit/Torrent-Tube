import Foundation

actor NetworkScanner {
    static let shared = NetworkScanner()
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 1.0
        configuration.timeoutIntervalForResource = 1.2
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: configuration)
    }

    /// Tests a specific host and port for a valid Torrent Tube server.
    func probe(host: String, port: Int = 5058) async -> String? {
        guard let url = URL(string: "http://\(host):\(port)/api/config") else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            let isServer = (json["server"] as? String == "torrenttube")
            let hasCaps = (json["capabilities"] != nil)
            let hasApi = (json["api_version"] != nil)
            if isServer || (hasCaps && hasApi) {
                return "http://\(host):\(port)"
            }
        } catch {
            return nil
        }
        return nil
    }

    /// Scans the local network for an active Torrent Tube server.
    /// Returns the verified base URL string if found, or nil if none found.
    func scan(existingAddress: String = "") async -> String? {
        var hostsToProbe: [String] = []
        var priorityHosts: [String] = []
        var ports = [5058]

        // 1. If an existing address is present, probe its host and port first
        let trimmedExisting = existingAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedExisting.isEmpty {
            let formatted = trimmedExisting.contains("://") ? trimmedExisting : "http://\(trimmedExisting)"
            if let existingURL = URL(string: formatted), let host = existingURL.host {
                priorityHosts.append(host)
                if let port = existingURL.port, !ports.contains(port) {
                    ports.append(port)
                }
            }
        }

        // 2. Discover local IP subnets via BSD getifaddrs
        var subnets: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0, let first = ifaddr {
            defer { freeifaddrs(ifaddr) }
            for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
                let flags = Int32(ptr.pointee.ifa_flags)
                guard (flags & (IFF_UP | IFF_RUNNING)) == (IFF_UP | IFF_RUNNING),
                      (flags & IFF_LOOPBACK) == 0,
                      ptr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }

                var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                var sa = ptr.pointee.ifa_addr.pointee
                if getnameinfo(&sa, socklen_t(sa.sa_len), &hostBuffer, socklen_t(hostBuffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: hostBuffer)
                    let components = ip.split(separator: ".").map(String.init)
                    if components.count == 4 {
                        let prefix = "\(components[0]).\(components[1]).\(components[2])."
                        if !subnets.contains(prefix) {
                            subnets.append(prefix)
                        }
                    }
                }
            }
        }

        if subnets.isEmpty {
            subnets = ["192.168.0.", "192.168.1."]
        }

        let preferredSuffixes = [102, 100, 101, 1, 2, 10, 20, 50, 200, 254]
        for subnet in subnets {
            for suffix in preferredSuffixes {
                let ip = "\(subnet)\(suffix)"
                if !priorityHosts.contains(ip) {
                    priorityHosts.append(ip)
                }
            }
        }

        priorityHosts.append("127.0.0.1")
        priorityHosts.append("localhost")

        for subnet in subnets {
            for suffix in 1...254 {
                let ip = "\(subnet)\(suffix)"
                if !priorityHosts.contains(ip) && !hostsToProbe.contains(ip) {
                    hostsToProbe.append(ip)
                }
            }
        }

        let orderedCandidates = priorityHosts + hostsToProbe
        let candidatePairs = ports.flatMap { port in orderedCandidates.map { ($0, port) } }

        let concurrency = 32
        var queue = candidatePairs

        return await withTaskGroup(of: String?.self) { group in
            var active = 0
            while !queue.isEmpty && active < concurrency {
                let (host, port) = queue.removeFirst()
                active += 1
                group.addTask {
                    await self.probe(host: host, port: port)
                }
            }

            while let result = await group.next() {
                active -= 1
                if let found = result {
                    group.cancelAll()
                    return found
                }
                if !queue.isEmpty {
                    let (host, port) = queue.removeFirst()
                    active += 1
                    group.addTask {
                        await self.probe(host: host, port: port)
                    }
                }
            }
            return nil
        }
    }
}
