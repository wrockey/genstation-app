// The one healer (design § 3.7). It replaces four uncoordinated pieces of code that silently
// rewrote the user's model selection:
//
//   1. `AppState.healSelectedAIMLModelIfNeeded()`   — alias heal, launch AND after every /models fetch
//   2. `ConfigurationSection`'s auto-select-first   — fired on every curated/advanced toggle
//   3. the conditional Gemini re-pick on cache load
//   4. the UNCONDITIONAL Gemini re-pick after a fetch — overwrote a deliberate choice every time
//
// The policy is now stated once, here, and tested. It is conservative about *reassigning a usable
// selection*, but "usable" means resolvable AND on offer when there is something to check against:
// a resolvable id absent from a non-empty `offered` list is a genuine mode mismatch (e.g. an image
// model surviving a switch into video mode) and gets replaced like any other unusable selection.
// Leaving it alone was design § 5's bug 5's original fix over-applied — that bug was reassignment on
// every list rebuild nilling `customAIMLPayload` and `customAIMLEndpoint` through
// `SettingsState.selectedAIMLModel`'s `didSet` — but the fix for it must not extend to a selection
// the current `offered` list provably cannot serve, or the next Generate posts a wrong-task request.
//
// This also discharges the Stage 1 lesson: persisting the selection removed the `onChange` edges
// the four sites had been relying on to initialise themselves, so the healing policy had become an
// emergent property of when four observers happened to fire. It is now a function with arguments.

import Foundation

public enum SelectionHealer {

    /// The id the caller should switch to, or `nil` to leave the current selection alone.
    ///
    /// - Parameters:
    ///   - selected: the current selection; may be empty, an alias, or an unregistered API id.
    ///   - offered: the ids the picker is currently showing, in display order. May legitimately be
    ///     empty — at launch the AI/ML healer runs before any picker has been built — and an empty
    ///     list can then only ever produce `nil` or a pure canonicalization, never a reassignment.
    ///     A non-empty list, though, is the authority on what is usable right now: a selection
    ///     resolvable by the catalog but absent from it (e.g. an image model after a switch into
    ///     video mode) is not usable and gets replaced.
    ///   - preferring: ids to reach for first *when a replacement is needed*. Never a reason to
    ///     replace a usable selection — Gemini's ladder is a tie-break, not an override.
    ///   - hasCustomPayload: true when the user has hand-edited JSON for the current model.
    public static func heal(selected: String,
                            offered: [String],
                            preferring preferred: [String] = [],
                            hasCustomPayload: Bool) -> String? {
        // A hand-edited payload outranks every other consideration. Canonicalizing an alias would
        // also trip the `didSet` that nils it, so even that waits until the user leaves custom mode.
        guard !hasCustomPayload else { return nil }

        let current = selected.trimmingCharacters(in: .whitespacesAndNewlines)

        if !current.isEmpty {
            if let canonical = Catalog.canonicalID(for: current) {
                // Resolvable. Usable as-is when there is nothing yet to check it against, or when
                // the offered list actually includes it — in which case just canonicalize the
                // spelling. A non-empty `offered` that does NOT include it means the resolvable
                // model is the wrong task/mode for what's on screen right now, so this falls through
                // to the replacement logic below instead of returning.
                if offered.isEmpty || offered.contains(canonical) {
                    return canonical == current ? nil : canonical
                }
            } else if offered.contains(current) {
                // Unresolvable but on offer: a legitimate advanced-mode pick. Leave it.
                return nil
            }
        }

        // No usable selection. Take the first preference that is on offer, else the first offered.
        if let match = preferred.first(where: { offered.contains($0) }) { return match }
        return offered.first
    }
}
