import Foundation

/// Minimal, fault-tolerant decoder for Claude Code's `--output-format stream-json`
/// NDJSON. We decode only the fields the activity feed consumes; every field is
/// optional and decoded with `try?`, so a malformed or unexpected sub-value never
/// throws out the whole event (one weird line shouldn't kill a run).
struct StreamEvent: Decodable, Sendable {
    let type: String
    let subtype: String?
    let message: StreamMessage?
    let result: String?
    let isError: Bool?
    let sessionId: String?   // present on every envelope; we keep the first one for --resume

    private enum CodingKeys: String, CodingKey {
        case type, subtype, message, result
        case isError = "is_error"
        case sessionId = "session_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? c.decode(String.self, forKey: .type)) ?? "unknown"
        subtype = try? c.decodeIfPresent(String.self, forKey: .subtype)
        message = try? c.decodeIfPresent(StreamMessage.self, forKey: .message)
        result = try? c.decodeIfPresent(String.self, forKey: .result)
        isError = try? c.decodeIfPresent(Bool.self, forKey: .isError)
        sessionId = try? c.decodeIfPresent(String.self, forKey: .sessionId)
    }
}

struct StreamMessage: Decodable, Sendable {
    let content: [ContentBlock]

    private enum CodingKeys: String, CodingKey { case content }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        content = (try? c.decodeIfPresent([ContentBlock].self, forKey: .content)) ?? []
    }
}

struct ContentBlock: Decodable, Sendable {
    let type: String
    let text: String?
    let name: String?      // tool name on tool_use blocks
    let input: ToolInput?

    private enum CodingKeys: String, CodingKey { case type, text, name, input }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? c.decode(String.self, forKey: .type)) ?? "unknown"
        text = try? c.decodeIfPresent(String.self, forKey: .text)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        input = try? c.decodeIfPresent(ToolInput.self, forKey: .input)
    }
}

/// The handful of tool-input fields we surface in the activity line. Anything else
/// (nested objects, arrays) is ignored rather than failing the decode.
struct ToolInput: Decodable, Sendable {
    let filePath: String?
    let path: String?
    let command: String?
    let pattern: String?
    let description: String?

    private enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
        case path, command, pattern, description
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        filePath = try? c.decodeIfPresent(String.self, forKey: .filePath)
        path = try? c.decodeIfPresent(String.self, forKey: .path)
        command = try? c.decodeIfPresent(String.self, forKey: .command)
        pattern = try? c.decodeIfPresent(String.self, forKey: .pattern)
        description = try? c.decodeIfPresent(String.self, forKey: .description)
    }
}

extension StreamEvent {
    /// Decode one NDJSON line; nil if it isn't valid JSON.
    static func decode(line: String) -> StreamEvent? {
        guard let data = line.data(using: .utf8), !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(StreamEvent.self, from: data)
    }
}
