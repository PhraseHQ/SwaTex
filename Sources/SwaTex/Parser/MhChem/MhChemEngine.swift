/// `mhchemParser.go` state machine driver + parser buffer.
///
/// Port of RaTeX `mhchem/engine.rs` and `mhchem/buffer.rs`.

/// Parser buffer (mirrors KaTeX mhchem `buffer` object).
final class MhChemBuffer {
    var parenthesisLevel = 0
    var beginsWithBond = false
    var sb = false
    var a: String?
    var b: String?
    var p: String?
    var o: String?
    var q: String?
    var d: String?
    var dType: String?
    var r: String?
    var rdt: String?
    var rd: String?
    var rqt: String?
    var rq: String?
    var text: String?
    var rm: String?

    /// Clear all fields except `parenthesisLevel` and `beginsWithBond`.
    func clearSoft() {
        sb = false
        a = nil
        b = nil
        p = nil
        o = nil
        q = nil
        d = nil
        dType = nil
        r = nil
        rdt = nil
        rd = nil
        rqt = nil
        rq = nil
        text = nil
        rm = nil
    }

    func clearAll() {
        clearSoft()
        parenthesisLevel = 0
        beginsWithBond = false
    }

    /// True if the slot is nil or contains an empty string.
    static func isSlotEmpty(_ slot: String?) -> Bool {
        slot?.isEmpty ?? true
    }
}

enum MhChemEngine {
    private static func normalizeInput(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for c in s {
            switch c {
            case "\n":
                out.append(" ")
            case "\u{2212}", "\u{2013}", "\u{2014}", "\u{2010}":
                out.append("-")
            case "\u{2026}":
                out.append("...")
            default:
                out.append(c)
            }
        }
        return out
    }

    static func goMachine(
        _ data: MhChemData,
        input rawInput: String,
        machine: String
    ) throws(MhChemError) -> [MhChemValue] {
        // The tokenizer threads the unconsumed input as a Substring of this
        // one normalized String — every transition used to copy the tail
        // (O(n²) allocations over a formula, P-018).
        let normalized = normalizeInput(rawInput)
        var input = normalized[...]
        if input.isEmpty {
            return []
        }

        guard let mdef = data.machines[machine] else {
            throw MhChemError.msg("unknown state machine \(machine)")
        }
        // P-023: states are pre-interned indices into `stateTable`; the
        // loop below performs no string hashing, no dictionary probes, and
        // no whole-transition struct copies (index-based access borrows).
        // `stateIndex == nil` means the current state name has no table
        // entry — diagnosed at the top of the iteration, exactly where the
        // dictionary miss used to throw.
        var stateIndex = mdef.stateIndexByName["0"]
        var stateName = "0"
        let buffer = MhChemBuffer()
        var output: [MhChemValue] = []
        // KaTeX resets the watchdog whenever the input value changes. All
        // remainders are suffixes of one normalized string, so start-index
        // identity is exact value identity — and O(1), where content
        // comparison walked the tail bytes.
        var lastInputStart: String.Index? = nil
        var watchdog = 10

        while true {
            if lastInputStart != input.startIndex {
                watchdog = 10
                lastInputStart = input.startIndex
            } else {
                watchdog -= 1
            }
            if watchdog <= 0 {
                throw MhChemError.msg("mhchem bug U")
            }

            guard let si = stateIndex ?? mdef.starStateIndex else {
                throw MhChemError.msg("no transitions for state \(stateName)")
            }

            var consumedTransition = false
            iter: for ti in mdef.stateTable[si].indices {
                guard let hit = try MhChemPatterns.match(mdef.stateTable[si][ti].kind, input)
                else {
                    continue
                }
                consumedTransition = true
                let emptyAtMatch = input.isEmpty
                for spec in mdef.stateTable[si][ti].task.actions {
                    let piece = try MhChemActions.apply(
                        data, machine: machine, buffer: buffer, m: hit.token, spec: spec)
                    output.append(contentsOf: piece)
                }
                if let ns = mdef.stateTable[si][ti].task.nextState {
                    stateIndex = mdef.stateTable[si][ti].nextStateIndex
                    stateName = ns
                }

                if emptyAtMatch {
                    return output
                }
                if !mdef.stateTable[si][ti].task.revisit {
                    input = hit.remainder
                }
                if !mdef.stateTable[si][ti].task.toContinue {
                    break iter
                }
            }

            if !consumedTransition {
                throw MhChemError.msg("mhchem bug U")
            }
        }
    }
}
