/// TeX math styles, controlling sizes of sub-expressions.
///
/// In TeX, the four main styles are D (display), T (text), S (script),
/// SS (scriptscript). Each has a "cramped" variant where superscripts
/// are set lower.
public enum MathStyle: Hashable, Sendable, Codable, CaseIterable {
    case display
    case displayCramped
    case text
    case textCramped
    case script
    case scriptCramped
    case scriptScript
    case scriptScriptCramped

    // KaTeX Style.ts lookup tables (indexed by style ID 0..7):
    //   fracNum = [T, Tc, S, Sc, SS, SSc, SS, SSc]
    //   fracDen = [Tc, Tc, Sc, Sc, SSc, SSc, SSc, SSc]
    //   sup     = [S, Sc, S, Sc, SS, SSc, SS, SSc]
    //   sub     = [Sc, Sc, Sc, Sc, SSc, SSc, SSc, SSc]
    //   cramp   = [Dc, Dc, Tc, Tc, Sc, Sc, SSc, SSc]
    //   text    = [D, Dc, T, Tc, T, Tc, T, Tc]

    /// Style for the numerator of a fraction (preserves crampedness).
    public var numerator: MathStyle {
        switch self {
        case .display: .text
        case .displayCramped: .textCramped
        case .text: .script
        case .textCramped: .scriptCramped
        case .script, .scriptScript: .scriptScript
        case .scriptCramped, .scriptScriptCramped: .scriptScriptCramped
        }
    }

    /// Style for the denominator of a fraction (always cramped).
    public var denominator: MathStyle {
        switch self {
        case .display, .displayCramped: .textCramped
        case .text, .textCramped: .scriptCramped
        case .script, .scriptCramped, .scriptScript, .scriptScriptCramped: .scriptScriptCramped
        }
    }

    /// Style for superscripts (preserves crampedness).
    public var superscript: MathStyle {
        switch self {
        case .display, .text: .script
        case .displayCramped, .textCramped: .scriptCramped
        case .script, .scriptScript: .scriptScript
        case .scriptCramped, .scriptScriptCramped: .scriptScriptCramped
        }
    }

    /// Style for subscripts (always cramped).
    public var subscript_: MathStyle {
        switch self {
        case .display, .displayCramped, .text, .textCramped: .scriptCramped
        case .script, .scriptCramped, .scriptScript, .scriptScriptCramped: .scriptScriptCramped
        }
    }

    /// The cramped version of this style.
    public var cramped: MathStyle {
        switch self {
        case .display: .displayCramped
        case .text: .textCramped
        case .script: .scriptCramped
        case .scriptScript: .scriptScriptCramped
        default: self
        }
    }

    /// Convert to the text-size equivalent (Script/ScriptScript → Text).
    /// Used inside `\text{}` blocks.
    public var textEquivalent: MathStyle {
        switch self {
        case .display, .displayCramped, .text, .textCramped: self
        case .script, .scriptScript: .text
        case .scriptCramped, .scriptScriptCramped: .textCramped
        }
    }

    public var isDisplay: Bool {
        self == .display || self == .displayCramped
    }

    public var isCramped: Bool {
        switch self {
        case .displayCramped, .textCramped, .scriptCramped, .scriptScriptCramped: true
        default: false
        }
    }

    /// True for Script/ScriptScript sizes — affects inter-atom spacing.
    public var isTight: Bool {
        switch self {
        case .script, .scriptCramped, .scriptScript, .scriptScriptCramped: true
        default: false
        }
    }

    /// Size index for looking up font metrics (0=text, 1=script, 2=scriptscript).
    public var sizeIndex: Int {
        switch self {
        case .display, .displayCramped, .text, .textCramped: 0
        case .script, .scriptCramped: 1
        case .scriptScript, .scriptScriptCramped: 2
        }
    }

    /// Size multiplier relative to base font size (TeX rule).
    public var sizeMultiplier: Double {
        switch self {
        case .display, .displayCramped, .text, .textCramped: 1.0
        case .script, .scriptCramped: 0.7
        case .scriptScript, .scriptScriptCramped: 0.5
        }
    }
}
