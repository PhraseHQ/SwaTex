// Differential-testing CLI: reads LaTeX formulas from stdin (one per line) and
// prints layout metrics as JSON — the exact counterpart of RaTeX's
// `cargo run --bin layout`, used to diff the two engines.

import Foundation
import SwaTex

func round5(_ v: Double) -> Double {
    (v * 100000).rounded() / 100000
}

func jsonString(_ s: String) -> String {
    var out = "\""
    for ch in s.unicodeScalars {
        switch ch {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        default:
            if ch.value < 0x20 {
                out += String(format: "\\u%04x", ch.value)
            } else {
                out.unicodeScalars.append(ch)
            }
        }
    }
    return out + "\""
}

while let line = readLine(strippingNewline: true) {
    let expr = line.trimmingCharacters(in: .whitespaces)
    if expr.isEmpty { continue }

    do {
        let ast = try parseLaTeX(expr)
        let options = LayoutOptions()
        let lbox = layout(ast, options: options)
        let displayList = toDisplayList(lbox)

        print(
            "{\"input\":\(jsonString(expr)),"
                + "\"box\":{\"width\":\(round5(lbox.width)),\"height\":\(round5(lbox.height)),\"depth\":\(round5(lbox.depth))},"
                + "\"displayList\":{\"width\":\(round5(displayList.width)),\"height\":\(round5(displayList.height)),\"depth\":\(round5(displayList.depth)),\"itemCount\":\(displayList.items.count)}}"
        )
    } catch {
        print(
            "{\"error\":true,\"message\":\(jsonString("\(error)")),\"input\":\(jsonString(expr))}")
    }
}
