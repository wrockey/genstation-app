import Foundation

public enum PromptSafetyPolicy {
    // Existing text policy, preserved without rule changes.
    // This heuristic is not visual moderation or a compliance guarantee.
    // Targets: CSAM, explicit sexual content, extreme violence, hate speech, illegal activities
    // Allows: Legitimate artistic, educational, culinary, and historical contexts

    public static func isPromptSafe(_ prompt: String) -> (isSafe: Bool, offendingPhrases: [String]) {
        let normalized = normalizeText(prompt)
        var offending = Set<String>()

        // CRITICAL: Check for CSAM-related content first (zero tolerance)
        if containsCSAMIndicators(normalized) {
            offending.insert("child safety violation")
        }

        // Check forbidden patterns
        for pattern in forbiddenPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let range = NSRange(location: 0, length: normalized.utf16.count)
            regex.enumerateMatches(in: normalized, options: [], range: range) { result, _, _ in
                if let matchRange = result?.range, let swiftRange = Range(matchRange, in: normalized) {
                    let matchedString = String(normalized[swiftRange])
                    // Check if this match has a legitimate context exception
                    if !hasLegitimateContext(match: matchedString, in: normalized) {
                        offending.insert(matchedString)
                    }
                }
            }
        }

        return (offending.isEmpty, Array(offending).sorted())
    }

    /// Version identifies the existing heuristic rules, independently of app releases.
    public static let policyVersion = "text-2026-09-14"

    public struct FilterReason: Codable, Equatable, Sendable {
        public let rule: String
        public let category: String
        public let policyVersion: String
        public let matchKind: String
        public let phrase: String

        public var json: [String: Any] {
            ["rule": rule, "category": category, "policy_version": policyVersion,
             "match_kind": matchKind, "phrase": phrase]
        }
    }

    /// Only matched normalized phrases are exposed, never surrounding prompt text or offsets.
    /// Child-safety combinations expose a category label instead of the matched context.
    public struct Blocked: Error {
        public let reasons: [FilterReason]
    }

    public static func requireSafe(_ prompt: String) throws {
        let reasons = filterReasons(prompt)
        if !reasons.isEmpty { throw Blocked(reasons: reasons) }
    }

    public static func filterReasons(_ prompt: String) -> [FilterReason] {
        reasons(for: isPromptSafe(prompt).offendingPhrases)
    }

    public static func reasons(for offendingPhrases: [String]) -> [FilterReason] {
        Array(Set(offendingPhrases)).sorted().prefix(16).map { phrase in
            let childSafety = phrase == "child safety violation"
            return FilterReason(rule: childSafety ? "child_safety_context" : "forbidden_text_pattern",
                category: childSafety ? "child_safety" : "prohibited_text", policyVersion: policyVersion,
                matchKind: childSafety ? "category_label" : "normalized_phrase",
                phrase: String(phrase.prefix(80)))
        }
    }

    // MARK: - Text Normalization

    private static func normalizeText(_ text: String) -> String {
        var normalized = text.lowercased()

        // Replace leetspeak and common substitutions
        let leetMap: [Character: Character] = [
            "0": "o", "1": "i", "3": "e", "4": "a", "5": "s",
            "@": "a", "$": "s", "!": "i", "7": "t", "8": "b"
        ]
        normalized = String(normalized.map { leetMap[$0] ?? $0 })

        // Normalize Unicode homoglyphs (Cyrillic/Greek lookalikes)
        let homoglyphs: [Character: Character] = [
            "а": "a", "е": "e", "о": "o", "р": "p", "с": "c", "у": "y", "х": "x",  // Cyrillic
            "α": "a", "ε": "e", "ο": "o", "ρ": "p", "τ": "t",  // Greek
            "і": "i", "ї": "i", "ј": "j",  // Other
        ]
        normalized = String(normalized.map { homoglyphs[$0] ?? $0 })

        // Remove zero-width characters and other invisibles
        normalized = normalized.replacingOccurrences(of: "\u{200B}", with: "")  // zero-width space
            .replacingOccurrences(of: "\u{200C}", with: "")  // zero-width non-joiner
            .replacingOccurrences(of: "\u{200D}", with: "")  // zero-width joiner
            .replacingOccurrences(of: "\u{FEFF}", with: "")  // BOM

        // Collapse repeated characters (nuuude -> nude)
        var collapsed = ""
        var lastChar: Character?
        var repeatCount = 0
        for char in normalized {
            if char == lastChar {
                repeatCount += 1
                if repeatCount < 2 {  // Allow max 2 of same char
                    collapsed.append(char)
                }
            } else {
                collapsed.append(char)
                repeatCount = 0
            }
            lastChar = char
        }
        normalized = collapsed

        // Replace non-alphanumeric with spaces (preserves word boundaries)
        var cleaned = ""
        for char in normalized {
            guard let scalar = char.unicodeScalars.first else { continue }
            if CharacterSet.alphanumerics.contains(scalar) {
                cleaned += String(char)
            } else {
                cleaned += " "
            }
        }

        // Collapse multiple spaces
        while cleaned.contains("  ") {
            cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
        }

        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - CSAM Detection (Critical - Zero Tolerance)

    private static func containsCSAMIndicators(_ text: String) -> Bool {
        // Age indicators that become problematic in sexual contexts
        let ageTerms = ["child", "children", "kid", "kids", "minor", "minors", "underage",
                        "preteen", "toddler", "infant", "baby", "young boy", "young girl",
                        "little boy", "little girl", "schoolgirl", "schoolboy", "loli", "shota",
                        "jailbait", "pedo", "paedo"]

        // Sexual context indicators
        let sexualTerms = ["nude", "naked", "sex", "porn", "erotic", "nsfw", "xxx",
                          "explicit", "lewd", "hentai", "fetish", "seduc"]

        let words = Set(text.split(separator: " ").map { String($0) })
        let hasAgeIndicator = ageTerms.contains { term in
            text.contains(term)
        }
        let hasSexualContext = sexualTerms.contains { term in
            words.contains(term) || text.contains(term)
        }

        return hasAgeIndicator && hasSexualContext
    }

    // MARK: - Forbidden Patterns
    // Focused on App Store requirements - explicit content that would cause rejection

    private static let forbiddenPatterns: [String] = [
        // Explicit sexual content (App Store Guidelines 1.1.4)
        "\\b(?:nsfw|porn|pornograph|hentai|xxx|erotic|orgasm|masturbat|blowjob|handjob|creampie|gangbang|bukk|cumshot|deepthroat|fellatio|cunnilingus|sodomy|incest|beastiality|bestiality|zoophil)\\b",
        "\\bnudes?\\b",  // "nude" but not "nuance"
        "\\bnaked(?!\\s+eye)\\b",  // "naked" but allow "naked eye"
        "\\b(?:fuck|fucking|fucker|fucked)\\b",
        "\\b(?:pussy|cunt|cock|dick|penis|vagina|genital|clit|scrotum|testicle)s?\\b",

        // Sexual violence (zero tolerance)
        "\\b(?:rape|raping|rapist|molest|grope|groping)\\b",

        // Extreme violence/gore (App Store Guidelines 1.1.3)
        "\\b(?:gore|gory|disembowel|decapitat|dismember|eviscerat|mutilat)\\b",
        "\\b(?:torture|torturing|tortured)\\b",
        "\\bsnuff\\b",

        // Hate speech and slurs (App Store Guidelines 1.1.1)
        "\\b(?:nigger|nigga|faggot|fag|dyke|tranny|kike|spic|chink|gook|wetback|redskin|raghead|towelhead|coon)s?\\b",
        "\\b(?:nazi|neonazi|white\\s*suprem|aryan\\s*nation|kkk|ku\\s*klux)\\b",

        // Self-harm promotion (App Store Guidelines 1.1.5)
        "\\b(?:suicide|suicidal|selfharm|self\\s*harm|cut\\s*myself|kill\\s*myself|hang\\s*myself)\\b",
        "\\b(?:anorexia|bulimia|pro\\s*ana|proana|thinspo)\\b",

        // Illegal drugs (glorification/promotion)
        "\\b(?:heroin|cocaine|crack\\s*cocaine|methamphetamine|crystal\\s*meth|fentanyl|mdma|ecstasy)\\b",

        // Terrorism/extremism
        "\\b(?:terrorist|terrorism|isis|al\\s*qaeda|jihadi|bomb\\s*making|mass\\s*shoot)\\b",

        // Human trafficking
        "\\b(?:sex\\s*slave|sex\\s*traffic|human\\s*traffic|child\\s*traffic)\\b"
    ]

    // MARK: - Legitimate Context Exceptions
    // Allows terms that have common non-offensive uses

    private static func hasLegitimateContext(match: String, in text: String) -> Bool {
        let contextExceptions: [String: [String]] = [
            // "breast" is OK in food/medical context
            "breast": ["chicken", "turkey", "duck", "poultry", "cancer", "exam", "feeding", "milk", "stroke"],
            // "cock" is OK for animals
            "cock": ["rooster", "weather", "shuttle", "pit", "pea", "game"],
            // "dick" is OK as a name
            "dick": ["moby", "tracy", "van dyke", "cheney", "nixon", "detective"],
            // "ass" is OK for donkey
            "ass": ["donkey", "burro", "mule", "wild ass", "grass", "class", "pass", "mass", "bass", "brass"],
        ]

        if let exceptions = contextExceptions[match] {
            return exceptions.contains { text.contains($0) }
        }

        return false
    }

    // MARK: - Content-Filter Blocked Alert (polished)
}
