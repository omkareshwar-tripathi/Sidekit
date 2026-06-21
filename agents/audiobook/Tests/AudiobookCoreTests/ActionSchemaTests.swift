import Testing
import Foundation
@testable import AudiobookCore

struct ActionSchemaTests {
    @Test func hasExactlyTheElevenActions() {
        let names = Set(ActionSchema.actions.map(\.name))
        #expect(names == Set([
            "play", "pause", "skipForward", "skipBackward", "nextChapter",
            "previousChapter", "goToChapter", "setSpeed", "setSleepTimer",
            "cancelSleepTimer", "switchBook",
        ]))
        #expect(ActionSchema.actions.count == 11)
    }

    @Test func everyActionHasAVerifyClause() {
        for spec in ActionSchema.actions { #expect(!spec.verifies.isEmpty) }
    }

    @Test func goToChapterParamIsRequiredInt() {
        let spec = ActionSchema.actions.first { $0.name == "goToChapter" }!
        #expect(spec.parameters == [ActionParameter(name: "chapter", type: "int", required: true)])
    }

    @Test func jsonIsValidAndContainsAllActions() {
        let json = ActionSchema.json()
        let parsed = try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [[String: Any]]
        #expect(parsed.count == 11)
    }
}
