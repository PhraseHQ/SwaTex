/// Map surd `innerHeight` from `layoutRadical` (1.0 … 3.0) to the KaTeX font
/// for U+221A.
func surdFont(forInnerHeight h: Double) -> FontId {
    // Matches `selectSurdHeight` in the layout engine: 1.0, 1.2, 1.8, 2.4, 3.0+
    if h < 1.1 {
        .mainRegular
    } else if h < 1.5 {
        .size1Regular
    } else if h < 2.1 {
        .size2Regular
    } else if h < 2.7 {
        .size3Regular
    } else {
        .size4Regular
    }
}
