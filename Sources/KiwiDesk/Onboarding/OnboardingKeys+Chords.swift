import Foundation
import KiwiDeskCore

/// Formats keymap combos into structured chords for onboarding (#1016).
@MainActor
extension OnboardingKeys {
    /// Directional arrow reading order.
    private static let directions = [
        "left", "down", "up", "right",
    ]

    /// `⌃⌥ ← ↓ ↑ →` when all four directions share a modifier
    /// set; otherwise each chord in full, which is the honest
    /// rendering of a keymap that has been edited apart.
    static func directional(
        layer: KeyLayer,
        command: String,
        glyph: (UInt32) -> String? = LayoutKeyGlyph.char(for:)
    ) -> OnboardingChord? {
        let combos = directions.compactMap { direction in
            layer.bindings.first {
                $0.lua == "KiwiDesk.\(command)(\"\(direction)\")"
                    && !$0.combo.isEmpty
            }?.combo
        }
        guard combos.count == directions.count else {
            return listed(combos, glyph: glyph)
        }
        return collapsed(combos, glyph: glyph) ?? listed(combos, glyph: glyph)
    }

    /// Formats space digit chords as a range (e.g. `⌃⌥ 1–5`) or
    /// collapsed list.
    static func digits(
        layer: KeyLayer,
        command: String,
        spaces: [SpaceID],
        glyph: (UInt32) -> String? = LayoutKeyGlyph.char(for:)
    ) -> OnboardingChord? {
        let combos = spaces.compactMap { space in
            layer.bindings.first {
                $0.lua
                    == "KiwiDesk.\(command)"
                    + "(\(SpaceLuaArg.quote(space.raw)))"
                    && !$0.combo.isEmpty
            }?.combo
        }
        guard let first = combos.first,
            let parsed = KeyCombo.parse(first),
            let head = keyOnly(combo: first, glyph: glyph)
        else { return nil }
        let modifiers = parsed.modifiers
        guard combos.count > 1 else {
            return .shared(modifiers, keys: head)
        }
        // Require contiguous digits sharing modifiers to format as a range.
        guard sameModifiers(combos),
            let run = contiguousDigits(combos, glyph: glyph)
        else {
            return collapsed(combos, glyph: glyph) ?? listed(
                combos,
                glyph: glyph
            )
                ?? .shared(modifiers, keys: head)
        }
        return .shared(
            modifiers,
            keys: run.first + "–" + run.last
        )
    }

    /// The first and last key glyph, but only when every chord in
    /// between is a single digit stepping up by one.
    static func contiguousDigits(
        _ combos: [String],
        glyph: (UInt32) -> String? = LayoutKeyGlyph.char(for:)
    ) -> (first: String, last: String)? {
        let keys = combos.compactMap { keyOnly(combo: $0, glyph: glyph) }
        guard keys.count == combos.count else { return nil }
        let values = keys.compactMap { key -> Int? in
            guard key.count == 1 else { return nil }
            return Int(key)
        }
        guard values.count == keys.count, let start = values.first
        else { return nil }
        for (offset, value) in values.enumerated()
        where value != start + offset {
            return nil
        }
        guard let firstKey = keys.first, let lastKey = keys.last
        else { return nil }
        return (firstKey, lastKey)
    }

    /// The shared modifiers once, then each chord's key glyph.
    static func collapsed(
        _ combos: [String],
        glyph: (UInt32) -> String? = LayoutKeyGlyph.char(for:)
    ) -> OnboardingChord? {
        guard sameModifiers(combos),
            let first = combos.first,
            let parsed = KeyCombo.parse(first)
        else { return nil }
        let keys = combos.compactMap { keyOnly(combo: $0, glyph: glyph) }
        guard keys.count == combos.count else { return nil }
        return .shared(
            parsed.modifiers,
            keys: keys.joined(separator: " ")
        )
    }

    static func listed(
        _ combos: [String],
        glyph: (UInt32) -> String? = LayoutKeyGlyph.char(for:)
    ) -> OnboardingChord? {
        let each = combos.compactMap { rendered(combo: $0, glyph: glyph) }
        return each.isEmpty
            ? nil : .mixed(each.joined(separator: "  "))
    }

    static func sameModifiers(
        _ combos: [String]
    ) -> Bool {
        let sets = combos.compactMap { KeyCombo.parse($0)?.modifiers }
        guard sets.count == combos.count, let first = sets.first
        else { return false }
        return sets.allSatisfy { $0 == first }
    }

    /// A chord's key glyph alone — the full render minus the
    /// modifier symbols it starts with.
    static func keyOnly(
        combo: String,
        glyph: (UInt32) -> String? = LayoutKeyGlyph.char(for:)
    ) -> String? {
        guard let parsed = KeyCombo.parse(combo),
            let full = rendered(combo: combo, glyph: glyph)
        else { return nil }
        let modifiers = ComboSymbols.modifierSymbols(
            parsed.modifiers
        )
        guard full.hasPrefix(modifiers) else { return full }
        return String(full.dropFirst(modifiers.count))
    }

    /// Splits a single chord into shared modifiers and key glyph.
    static func single(
        combo: String?,
        glyph: (UInt32) -> String? = LayoutKeyGlyph.char(for:)
    ) -> OnboardingChord? {
        guard let combo,
            let parsed = KeyCombo.parse(combo),
            let key = keyOnly(combo: combo, glyph: glyph)
        else {
            guard let full = rendered(combo: combo, glyph: glyph) else {
                return nil
            }
            return .mixed(full)
        }
        return .shared(parsed.modifiers, keys: key)
    }

    /// Renders combo string with layout glyphs via `ComboSymbols`.
    static func rendered(
        combo: String?,
        glyph: (UInt32) -> String? = LayoutKeyGlyph.char(for:)
    ) -> String? {
        guard let combo, !combo.isEmpty else { return nil }
        guard let parsed = KeyCombo.parse(combo) else {
            return combo
        }
        return ComboSymbols.render(
            parsed,
            layoutChar: glyph
        )
    }
}
