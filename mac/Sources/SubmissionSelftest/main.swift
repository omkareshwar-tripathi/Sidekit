import Foundation
import SidekitCore
import SidekitNet

// Sends one signup + one feedback to whatever SIDEKIT_SUPABASE_URL points at and exits
// 0 iff both were accepted. Drives the same SupabaseSubmissionSender the app ships with.
let sender = SupabaseSubmissionSender()
let signup = RemoteSubmission.signup(email: "selftest@example.com", appVersion: "selftest")
let feedback = RemoteSubmission.feedback(kind: .other, message: "selftest message",
                                         email: "selftest@example.com",
                                         appVersion: "selftest", osVersion: "selftest")
let signupResult = await sender.send(signup)
let feedbackResult = await sender.send(feedback)
print("signup: \(signupResult)  feedback: \(feedbackResult)")
exit(signupResult == .sent && feedbackResult == .sent ? 0 : 1)
