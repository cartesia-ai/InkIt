import Foundation

enum WorkspaceURI: Equatable {
    case local(URL)
    case remoteSSH(host: String, path: String, raw: String)
    case unsupported(raw: String)

    static func parse(_ raw: String) -> WorkspaceURI {
        guard let url = URL(string: raw), let scheme = url.scheme else {
            return .unsupported(raw: raw)
        }

        if scheme == "file" {
            return .local(url)
        }

        guard scheme == "vscode-remote" else {
            return .unsupported(raw: raw)
        }

        let authority = URLComponents(string: raw)?.percentEncodedHost ?? url.host ?? ""
        guard authority.hasPrefix("ssh-remote%2B") || authority.hasPrefix("ssh-remote+") else {
            return .unsupported(raw: raw)
        }

        let encodedHost = authority
            .replacingOccurrences(of: "ssh-remote%2B", with: "")
            .replacingOccurrences(of: "ssh-remote+", with: "")
        let decodedHost = encodedHost.removingPercentEncoding ?? encodedHost
        let host = decodeSSHHost(decodedHost)
        return .remoteSSH(host: host, path: url.path, raw: raw)
    }

    var pathLeaf: String? {
        switch self {
        case .local(let url):
            return url.lastPathComponent
        case .remoteSSH(_, let path, _):
            return URL(fileURLWithPath: path).lastPathComponent
        case .unsupported:
            return nil
        }
    }

    var evidenceDescription: String {
        switch self {
        case .local(let url):
            return "file://\(url.path)"
        case .remoteSSH(let host, let path, _):
            return "vscode-remote://ssh-remote+\(host)\(path)"
        case .unsupported(let raw):
            return raw
        }
    }

    private static func decodeSSHHost(_ raw: String) -> String {
        let candidate = decodeHexString(raw) ?? raw
        guard candidate.hasPrefix("{"), let data = candidate.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let host = object["hostName"] as? String,
              !host.isEmpty else {
            return raw
        }
        return host
    }

    private static func decodeHexString(_ raw: String) -> String? {
        guard raw.count.isMultiple(of: 2), raw.allSatisfy({ $0.isHexDigit }) else { return nil }
        var bytes: [UInt8] = []
        var index = raw.startIndex
        while index < raw.endIndex {
            let next = raw.index(index, offsetBy: 2)
            guard let byte = UInt8(raw[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return String(bytes: bytes, encoding: .utf8)
    }
}
