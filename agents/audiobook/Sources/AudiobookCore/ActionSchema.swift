import Foundation

public struct ActionParameter: Equatable, Sendable {
    public let name: String
    public let type: String        // "int" | "double" | "string" | "bool"
    public let required: Bool
    public init(name: String, type: String, required: Bool) {
        self.name = name; self.type = type; self.required = required
    }
}

public struct ActionSpec: Equatable, Sendable {
    public let name: String
    public let parameters: [ActionParameter]
    public let verifies: String    // human-readable state assertion the harness checks
    public init(name: String, parameters: [ActionParameter], verifies: String) {
        self.name = name; self.parameters = parameters; self.verifies = verifies
    }
}

/// The machine-readable contract the decide-model (Sub-project B) targets and the
/// harness verifies against. Mirrors PlayerStore exactly (see ActionSchemaTests).
public enum ActionSchema {
    public static let actions: [ActionSpec] = [
        ActionSpec(name: "play", parameters: [], verifies: "isPlaying == true"),
        ActionSpec(name: "pause", parameters: [], verifies: "isPlaying == false"),
        ActionSpec(name: "skipForward",
                   parameters: [ActionParameter(name: "seconds", type: "double", required: false)],
                   verifies: "position increased by ~seconds"),
        ActionSpec(name: "skipBackward",
                   parameters: [ActionParameter(name: "seconds", type: "double", required: false)],
                   verifies: "position decreased by ~seconds"),
        ActionSpec(name: "nextChapter", parameters: [], verifies: "currentChapter + 1"),
        ActionSpec(name: "previousChapter", parameters: [], verifies: "currentChapter - 1"),
        ActionSpec(name: "goToChapter",
                   parameters: [ActionParameter(name: "chapter", type: "int", required: true)],
                   verifies: "currentChapter == chapter (1-based)"),
        ActionSpec(name: "setSpeed",
                   parameters: [ActionParameter(name: "rate", type: "double", required: true)],
                   verifies: "speed == rate"),
        ActionSpec(name: "setSleepTimer",
                   parameters: [ActionParameter(name: "minutes", type: "int", required: false),
                                ActionParameter(name: "endOfChapter", type: "bool", required: false)],
                   verifies: "sleepTimer active with target"),
        ActionSpec(name: "cancelSleepTimer", parameters: [], verifies: "sleepTimer == nil"),
        ActionSpec(name: "switchBook",
                   parameters: [ActionParameter(name: "title", type: "string", required: true)],
                   verifies: "currentBook == matched book"),
    ]

    public static func json() -> String {
        let objs: [[String: Any]] = actions.map { spec in
            [
                "name": spec.name,
                "verifies": spec.verifies,
                "parameters": spec.parameters.map {
                    ["name": $0.name, "type": $0.type, "required": $0.required] as [String: Any]
                },
            ]
        }
        let data = try! JSONSerialization.data(withJSONObject: objs,
                                               options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8)!
    }
}
