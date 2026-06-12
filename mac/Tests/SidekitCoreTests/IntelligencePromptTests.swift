import Foundation
import Testing
@testable import SidekitCore

struct IntelligencePromptTests {
    // MARK: chips & tones

    @Test func chipAndToneLabels() {
        #expect(IntelligenceChip.allCases.map(\.label) ==
                ["Draft email", "Draft message", "Polish", "Summarize"])
        #expect(IntelligenceTone.allCases.map(\.label) ==
                ["Keep tone", "Professional", "Friendly", "Concise"])
    }

    @Test func chipRolesSplitPolishFromDrafting() {
        #expect(IntelligenceChip.polish.role == .polish)
        for chip in [IntelligenceChip.draftEmail, .draftMessage, .summarize] {
            #expect(chip.role == .draft)
        }
    }

    // MARK: polish paths

    /// The faithful polish prompt is the lab-tuned p7 verbatim (spec §4) — guard it against
    /// hand-trimming. If the disposable lab/ folder is ever deleted, delete this one test
    /// (the constant stays; it IS the product copy).
    @Test func polishKeepToneIsLabP7Verbatim() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)              // …/mac/Tests/SidekitCoreTests/x.swift
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent() // → repo root
        let labFile = repoRoot.appendingPathComponent("lab/whisper-compare/prompts/p7_faithful.txt")
        let lab = try String(contentsOf: labFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let built = IntelligencePrompt.build(chip: .polish, tone: .keepTone)
        #expect(built.system == lab)
    }

    @Test func polishWithToneUsesRewritePromptNotP7() {
        let built = IntelligencePrompt.build(chip: .polish, tone: .professional)
        #expect(built.system == "Rewrite the text in a professional, courteous tone. Keep every fact, name, number, date, and the meaning unchanged. Output only the rewritten text.")
        #expect(!built.system.contains("GOLDEN RULE"))
    }

    @Test func polishConciseRewrite() {
        let built = IntelligencePrompt.build(chip: .polish, tone: .concise)
        #expect(built.system == "Rewrite the text to be as brief as possible. Keep every fact, name, number, date, and the meaning unchanged. Output only the rewritten text.")
    }

    // MARK: drafting chips

    @Test func draftEmailProfessionalExactComposition() {
        let built = IntelligencePrompt.build(chip: .draftEmail, tone: .professional)
        #expect(built.system == """
        You write text from the user's rough notes. Keep every fact, name, number, and date \
        exactly as given; invent nothing. If a result needs computed math, show the formula \
        and tell the user to verify — never state a guessed number. Output only the requested \
        text — no preamble, no quotes.
        Write an email from these notes. Subject line first, then the body.
        Tone: professional and courteous.
        """)
    }

    @Test func keepToneAppendsNoToneLine() {
        for chip in [IntelligenceChip.draftEmail, .draftMessage, .summarize] {
            #expect(!IntelligencePrompt.build(chip: chip, tone: .keepTone).system.contains("Tone:"))
        }
    }

    @Test func allDraftChipsCarryTheArithmeticGuardrail() {
        for chip in [IntelligenceChip.draftEmail, .draftMessage, .summarize] {
            #expect(IntelligencePrompt.build(chip: chip, tone: .friendly).system
                .contains("never state a guessed number"))
        }
    }

    @Test func temperaturesPerSpec() {
        #expect(IntelligencePrompt.build(chip: .polish, tone: .keepTone).temperature == 0.0)
        #expect(IntelligencePrompt.build(chip: .polish, tone: .friendly).temperature == 0.0)
        #expect(IntelligencePrompt.build(chip: .draftEmail, tone: .keepTone).temperature == 0.0)
        #expect(IntelligencePrompt.build(chip: .summarize, tone: .concise).temperature == 0.0)
    }

    // MARK: input check

    @Test func inputCheckTrimsAndRejectsEmpty() {
        #expect(IntelligencePrompt.check("  hi  ") == .ok("hi"))
        #expect(IntelligencePrompt.check("   \n ") == .empty)
        #expect(IntelligencePrompt.check("") == .empty)
    }

    @Test func inputCheckEnforcesTheCapWithoutTruncating() {
        let atCap = String(repeating: "a", count: 6000)
        #expect(IntelligencePrompt.check(atCap) == .ok(atCap))
        #expect(IntelligencePrompt.check(atCap + "a") == .tooLong)
    }

    // MARK: sanitation

    @Test func sanitizeStripsThinkBlocksFencesQuotesAndWhitespace() {
        #expect(IntelligencePrompt.sanitize("<think>hmm</think>\nHello.") == "Hello.")
        #expect(IntelligencePrompt.sanitize("```\nHello.\n```") == "Hello.")
        #expect(IntelligencePrompt.sanitize("```text\nHello.\n```") == "Hello.")
        #expect(IntelligencePrompt.sanitize("\"Hello.\"") == "Hello.")
        #expect(IntelligencePrompt.sanitize("  Hello.  \n") == "Hello.")
    }

    @Test func sanitizeLeavesInteriorQuotesAndFencesAlone() {
        #expect(IntelligencePrompt.sanitize("She said \"hi\" twice.") == "She said \"hi\" twice.")
        #expect(IntelligencePrompt.sanitize("Run ```ls``` now.") == "Run ```ls``` now.")
    }

    // MARK: user payload framing

    @Test func faithfulPolishFramesTheUserTurnLikeTheLab() {
        #expect(IntelligencePrompt.userPayload(chip: .polish, tone: .keepTone, input: "hi there")
                == "---\nTranscript:\nhi there")
    }

    @Test func everyOtherPathSendsTheInputBare() {
        #expect(IntelligencePrompt.userPayload(chip: .polish, tone: .professional, input: "x") == "x")
        for chip in [IntelligenceChip.draftEmail, .draftMessage, .summarize] {
            #expect(IntelligencePrompt.userPayload(chip: chip, tone: .keepTone, input: "x") == "x")
        }
    }
}
