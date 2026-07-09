/// TeX math atom classes, determining inter-element spacing.
///
/// From TeXbook pp. 170-171. Also matches KaTeX's DomEnum.
enum MathClass: Int, Hashable, Sendable, CaseIterable {
    case ord = 0  // ordinary
    case op = 1  // large operator
    case bin = 2  // binary operation
    case rel = 3  // relation
    case open = 4  // opening delimiter
    case close = 5  // closing delimiter
    case punct = 6  // punctuation
    case inner = 7  // inner (fractions, etc.)
}

/// Spacing between adjacent math atoms, in mu (1mu = 1/18 em).
///
/// From TeXbook p. 170, Table 18.
/// 0 = no space, 3 = thin space, 4 = medium space, 5 = thick space.
///
/// Rows = left atom class, Columns = right atom class.
/// Order: Ord, Op, Bin, Rel, Open, Close, Punct, Inner
private let spacingTable: [[Double]] = [
    //       Ord  Op  Bin  Rel Open Close Punct Inner
    /*Ord*/ [0, 3, 4, 5, 0, 0, 0, 3],
    /*Op*/ [3, 4, 0, 5, 0, 0, 0, 3],
    /*Bin*/ [4, 4, 0, 0, 4, 0, 0, 4],
    /*Rel*/ [5, 5, 0, 0, 5, 0, 0, 5],
    /*Open*/ [0, 0, 0, 0, 0, 0, 0, 0],
    /*Close*/ [0, 3, 4, 5, 0, 0, 0, 3],
    /*Punct*/ [3, 3, 0, 5, 3, 3, 3, 3],
    /*Inner*/ [3, 3, 4, 5, 3, 0, 3, 3],
]

/// Same table but for tight (script/scriptscript) styles.
/// In tight mode, only thin spaces (3mu) between Op-Ord and Op-Op are kept.
private let tightSpacingTable: [[Double]] = [
    //       Ord  Op  Bin  Rel Open Close Punct Inner
    /*Ord*/ [0, 3, 0, 0, 0, 0, 0, 0],
    /*Op*/ [3, 3, 0, 0, 0, 0, 0, 0],
    /*Bin*/ [0, 0, 0, 0, 0, 0, 0, 0],
    /*Rel*/ [0, 0, 0, 0, 0, 0, 0, 0],
    /*Open*/ [0, 0, 0, 0, 0, 0, 0, 0],
    /*Close*/ [0, 3, 0, 0, 0, 0, 0, 0],
    /*Punct*/ [0, 0, 0, 0, 0, 0, 0, 0],
    /*Inner*/ [0, 3, 0, 0, 0, 0, 0, 0],
]

/// Get spacing (in mu) between two adjacent math atoms.
///
/// `tight` should be true for script and scriptscript styles.
/// Returns the spacing in mu units (1mu = 1/18 em).
func atomSpacing(_ left: MathClass, _ right: MathClass, tight: Bool) -> Double {
    let table = tight ? tightSpacingTable : spacingTable
    return table[left.rawValue][right.rawValue]
}

/// Convert mu to em. 1mu = 1/18 em (at the current style's quad width).
func muToEm(_ mu: Double, quad: Double) -> Double {
    mu * quad / 18.0
}
