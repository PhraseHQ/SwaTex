/// Lay out boxes horizontally: x accumulates, take max height/depth.
///
/// This corresponds to TeX's \hbox operation: children are placed
/// side by side from left to right. The resulting box's height is
/// the maximum child height, and its depth is the maximum child depth.
func makeHBox(_ children: [LayoutBox]) -> LayoutBox {
    var width = 0.0
    var height = 0.0
    var depth = 0.0

    for child in children {
        width += child.width
        height = max(height, child.height)
        depth = max(depth, child.depth)
    }

    return LayoutBox(width: width, height: height, depth: depth, content: .hbox(children))
}
