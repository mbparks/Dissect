import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String), number(Int), bool(Bool), object([String: JSONValue]), array([JSONValue]), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}
public struct EngineRequest: Encodable {
    public let id: String
    public let method: String
    public let params: [String: JSONValue]
    public init(id: String, method: String, params: [String: JSONValue]) { self.id=id; self.method=method; self.params=params }
}
public struct EngineResponse: Decodable {
    public let id: String?
    public let event: String?
    public let message: String?
    public let result: JSONValue?
    public let error: String?
    public let cancelled: Bool?
}
public struct FrameDecoder {
    private var buffer = Data()
    public init() {}
    public mutating func append(_ data: Data) throws -> [EngineResponse] {
        buffer.append(data)
        guard buffer.count <= 8 * 1024 * 1024 else { throw ProtocolError.tooLarge }
        var messages: [EngineResponse] = []
        while let end = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<end])
            buffer.removeSubrange(...end)
            let prefix = Data("@DISSECT@".utf8)
            if line.starts(with: prefix) {
                messages.append(try JSONDecoder().decode(EngineResponse.self, from: line.dropFirst(prefix.count)))
            }
        }
        return messages
    }
    public enum ProtocolError: Error { case tooLarge }
}
public struct RuntimeConfig: Codable, Equatable {
    public var python: String
    public var ghidra: String
    public var javaHome: String
    public init(python: String = "", ghidra: String = "", javaHome: String = "") { self.python=python; self.ghidra=ghidra; self.javaHome=javaHome }
    public static var location: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Dissect/runtime.json")
    }
    public static func bundled(resources: URL? = Bundle.main.resourceURL) -> RuntimeConfig? {
        guard let root = resources?.appendingPathComponent("Runtime") else { return nil }
        let config = Self(python: root.appendingPathComponent("python/bin/python3").path,
                          ghidra: root.appendingPathComponent("ghidra").path,
                          javaHome: root.appendingPathComponent("java.jdk/Contents/Home").path)
        guard FileManager.default.isExecutableFile(atPath: config.python),
              FileManager.default.isExecutableFile(atPath: config.javaHome + "/bin/java"),
              FileManager.default.fileExists(atPath: config.ghidra + "/Ghidra/application.properties") else { return nil }
        return config
    }
    public static func load() -> RuntimeConfig {
        if let data = try? Data(contentsOf: location), let config = try? JSONDecoder().decode(Self.self, from: data),
           FileManager.default.isExecutableFile(atPath: config.python) { return config }
        return bundled() ?? Self()
    }
    public func save() throws {
        if self == Self.bundled() {
            if FileManager.default.fileExists(atPath: Self.location.path) { try FileManager.default.removeItem(at: Self.location) }
            return
        }
        try FileManager.default.createDirectory(at: Self.location.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: Self.location, options: .atomic)
    }
}
public struct WorkspaceInfo: Decodable, Sendable {
    public let opened: Bool
    public let name: String?
    public let path: String?
    public let sha256: String?
    public let size: Int?
    public let language: String?
    public let formatName: String?
    public let functions: Int?
    public let imageBase: String?
    public let analysis: String?
    public let canUndo: Bool?
    public let canRedo: Bool?
}
public struct AnalysisRow: Decodable, Identifiable, Hashable, Sendable {
    public let address: String
    public let name: String
    public let detail: String
    public let kind: String
    public var id: String { address }
}
public struct IndexPage: Decodable, Sendable {
    public let items: [AnalysisRow]
    public let total: Int
    public let offset: Int
    public let hasMore: Bool
}
public struct ReferencePage: Decodable, Sendable {
    public let items: [AnalysisRow]
    public let truncated: Bool
}
public struct FunctionDetail: Decodable, Sendable {
    public let address: String
    public let name: String
    public let signature: String
    public let note: String
    public let code: String
    public let assembly: String
    public let warning: String
}
public struct ByteResult: Decodable, Sendable { public let text: String }
public struct DoctorResult: Decodable, Sendable {
    public let ghidra: String
    public let java: String
    public let architecture: String
    public let python: String
}
public struct Language: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let compilers: [String]
}
public struct LanguageResult: Decodable, Sendable { public let languages: [Language] }
