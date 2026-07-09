/// Lay out boxes vertically: stack top-to-bottom.
///
/// The first child sits at the top. The baseline of the resulting
/// vbox is at `depth` below the top of the first child.
///
/// Default: baseline at the bottom of the last element.
func makeVBox(_ children: [VBoxChild]) -> LayoutBox {
    if children.isEmpty {
        return .empty
    }

    var width = 0.0
    var totalHeight = 0.0

    for child in children {
        switch child.kind {
        case .box(let b):
            width = max(width, b.width)
            totalHeight += b.height + b.depth
        case .kern(let k):
            totalHeight += k
        }
    }

    return LayoutBox(width: width, height: totalHeight, depth: 0, content: .vbox(children))
}

/// Create a VBox with the baseline positioned so that a specific
/// vertical position is at the baseline.
///
/// `depthBelowBaseline`: how much of the vbox extends below the baseline.
func makeVBox(_ children: [VBoxChild], depthBelowBaseline: Double) -> LayoutBox {
    var vbox = makeVBox(children)
    let total = vbox.height + vbox.depth
    vbox.depth = depthBelowBaseline
    vbox.height = total - depthBelowBaseline
    return vbox
}
