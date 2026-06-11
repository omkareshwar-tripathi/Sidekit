import Testing
import Foundation
@testable import SidekitCore

struct RemoteSubmissionTests {

    @Test func signupTargetsSignupsTableWithExpectedBody() throws {
        let s = RemoteSubmission.signup(email: "a@b.co", appVersion: "1.0 (12)")
        #expect(s.table == "signups")
        let object = try #require(JSONSerialization.jsonObject(with: s.jsonBody()) as? [String: String])
        #expect(object == ["email": "a@b.co", "app_version": "1.0 (12)", "platform": "mac"])
    }

    @Test func feedbackTargetsFeedbackTableWithExpectedBody() throws {
        let s = RemoteSubmission.feedback(kind: .bug, message: "it broke", email: "a@b.co",
                                          appVersion: "1.0 (12)", osVersion: "macOS 15.5.0")
        #expect(s.table == "feedback")
        let object = try #require(JSONSerialization.jsonObject(with: s.jsonBody()) as? [String: String])
        #expect(object == ["type": "bug", "message": "it broke", "email": "a@b.co",
                           "app_version": "1.0 (12)", "os_version": "macOS 15.5.0"])
    }

    @Test func anonymousFeedbackOmitsEmailKey() throws {
        let s = RemoteSubmission.feedback(kind: .other, message: "hi", email: nil,
                                          appVersion: "1.0", osVersion: "macOS 15.5.0")
        let object = try #require(JSONSerialization.jsonObject(with: s.jsonBody()) as? [String: String])
        #expect(object["email"] == nil)
        #expect(object["type"] == "other")
    }

    @Test func feedbackMessageValidationTrimsAndBounds() {
        #expect(RemoteSubmission.validateFeedbackMessage("  hello \n") == "hello")
        #expect(RemoteSubmission.validateFeedbackMessage("   \n ") == nil)        // blank
        #expect(RemoteSubmission.validateFeedbackMessage("") == nil)
        let max = String(repeating: "x", count: RemoteSubmission.feedbackMessageLimit)
        #expect(RemoteSubmission.validateFeedbackMessage(max) == max)             // exactly at cap
        #expect(RemoteSubmission.validateFeedbackMessage(max + "x") == nil)       // over cap
    }

    @Test func submissionsAreCodableForTheSpool() throws {
        let all: [RemoteSubmission] = [
            .signup(email: "a@b.co", appVersion: "1"),
            .feedback(kind: .feature, message: "m", email: nil, appVersion: "1", osVersion: "15"),
        ]
        let data = try JSONEncoder().encode(all)
        #expect(try JSONDecoder().decode([RemoteSubmission].self, from: data) == all)
    }
}
