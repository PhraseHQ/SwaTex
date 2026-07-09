/// `texify.go` — turn parser output into TeX (KaTeX mhchem 3.3).
///
/// Port of RaTeX `mhchem/texify.rs`.

import Foundation

enum MhChemTexify {
    static func go(_ input: [MhChemValue], isInner: Bool) throws(MhChemError) -> String {
        var res = ""
        var cee = false
        for inputi in input {
            switch inputi {
            case .string(let s):
                res += s
            default:
                if typeStr(inputi) == "1st-level escape" {
                    cee = true
                }
                res += try go2(inputi)
            }
        }
        if !isInner && !cee && !res.isEmpty {
            res = "{\(res)}"
        }
        return res
    }

    private static func arrInner(_ v: MhChemValue, _ key: String) throws(MhChemError) -> String {
        let sl = v[key]?.asArray ?? []
        return try go(sl, isInner: true)
    }

    private static func typeStr(_ v: MhChemValue) -> String? {
        v["type_"]?.asString
    }

    private static func str(_ buf: MhChemValue, _ key: String) -> String {
        buf[key]?.asString ?? ""
    }

    private static func go2(_ buf: MhChemValue) throws(MhChemError) -> String {
        guard let typ = typeStr(buf) else {
            throw MhChemError.msg("texify: missing type_")
        }
        switch typ {
        case "chemfive":
            let b5a = try arrInner(buf, "a")
            let b5b = try arrInner(buf, "b")
            let b5p = try arrInner(buf, "p")
            let b5o = try arrInner(buf, "o")
            let b5q = try arrInner(buf, "q")
            let b5d = try arrInner(buf, "d")
            var res = ""
            if !b5a.isEmpty {
                let a = (b5a.hasPrefix("+") || b5a.hasPrefix("-")) ? "{\(b5a)}" : b5a
                res += a
                res += "\\,"
            }
            if !b5b.isEmpty || !b5p.isEmpty {
                res += "{\\vphantom{X}}"
                res += "^{\\hphantom{\(b5b)}}_{\\hphantom{\(b5p)}}"
                res += "{\\vphantom{X}}"
                res += "^{\\smash[t]{\\vphantom{2}}\\mathllap{\(b5b)}}"
                res += "_{\\vphantom{2}\\mathllap{\\smash[t]{\(b5p)}}}"
            }
            if !b5o.isEmpty {
                let o = (b5o.hasPrefix("+") || b5o.hasPrefix("-")) ? "{\(b5o)}" : b5o
                res += o
            }
            let dTy = str(buf, "dType")
            if dTy == "kv" {
                if !b5d.isEmpty || !b5q.isEmpty {
                    res += "{\\vphantom{X}}"
                }
                if !b5d.isEmpty {
                    res += "^{\(b5d)}"
                }
                if !b5q.isEmpty {
                    res += "_{\\smash[t]{\(b5q)}}"
                }
            } else if dTy == "oxidation" {
                if !b5d.isEmpty {
                    res += "{\\vphantom{X}}"
                    res += "^{\(b5d)}"
                }
                if !b5q.isEmpty {
                    res += "{\\vphantom{X}}"
                    res += "_{\\smash[t]{\(b5q)}}"
                }
            } else {
                if !b5q.isEmpty {
                    res += "{\\vphantom{X}}"
                    res += "_{\\smash[t]{\(b5q)}}"
                }
                if !b5d.isEmpty {
                    res += "{\\vphantom{X}}"
                    res += "^{\(b5d)}"
                }
            }
            return res
        case "rm":
            return "\\mathrm{\(str(buf, "p1"))}"
        case "text":
            var p1 = str(buf, "p1")
            if p1.contains("^") || p1.contains("_") {
                p1 = p1
                    .replacingOccurrences(of: " ", with: "~")
                    .replacingOccurrences(of: "-", with: "\\text{-}")
                return "\\mathrm{\(p1)}"
            } else {
                return "\\text{\(p1)}"
            }
        case "roman numeral":
            return "\\mathrm{\(str(buf, "p1"))}"
        case "state of aggregation":
            let i = try arrInner(buf, "p1")
            return "\\mskip2mu \(i)"
        case "state of aggregation subscript":
            let i = try arrInner(buf, "p1")
            return "\\mskip1mu \(i)"
        case "bond":
            let k = str(buf, "kind_")
            guard let b = getBond(k) else {
                throw MhChemError.msg("Unknown bond (\(k))")
            }
            return b
        case "frac":
            let p1 = str(buf, "p1")
            let p2 = str(buf, "p2")
            let c = "\\frac{\(p1)}{\(p2)}"
            return "\\mathchoice{\\textstyle\(c)}{\(c)}{\(c)}{\(c)}"
        case "pu-frac":
            let p1 = try arrInner(buf, "p1")
            let p2 = try arrInner(buf, "p2")
            let d = "\\frac{\(p1)}{\(p2)}"
            return "\\mathchoice{\\textstyle\(d)}{\(d)}{\(d)}{\(d)}"
        case "tex-math":
            return "\(str(buf, "p1")) "
        case "frac-ce":
            let p1 = try arrInner(buf, "p1")
            let p2 = try arrInner(buf, "p2")
            return "\\frac{\(p1)}{\(p2)}"
        case "overset":
            let p1 = try arrInner(buf, "p1")
            let p2 = try arrInner(buf, "p2")
            return "\\overset{\(p1)}{\(p2)}"
        case "underset":
            let p1 = try arrInner(buf, "p1")
            let p2 = try arrInner(buf, "p2")
            return "\\underset{\(p1)}{\(p2)}"
        case "underbrace":
            let p1 = try arrInner(buf, "p1")
            let p2 = try arrInner(buf, "p2")
            return "\\underbrace{\(p1)}_{\(p2)}"
        case "color":
            let c1 = str(buf, "color1")
            let c2 = try arrInner(buf, "color2")
            return "{\\color{\(c1)}{\(c2)}}"
        case "color0":
            return "\\color{\(str(buf, "color"))}"
        case "arrow":
            let rd = try arrInner(buf, "rd")
            let rq = try arrInner(buf, "rq")
            let r = str(buf, "r")
            var arrow = "\\x\(try getArrow(r))"
            if !rq.isEmpty {
                arrow += "[{\(rq)}]"
            }
            if !rd.isEmpty {
                arrow += "{\(rd)}"
            } else {
                arrow += "{}"
            }
            return arrow
        case "operator":
            let k = str(buf, "kind_")
            guard let op = getOperator(k) else {
                throw MhChemError.msg("Unknown operator (\(k))")
            }
            return op
        case "1st-level escape":
            return "\(str(buf, "p1")) "
        case "space":
            return " "
        case "entitySkip":
            return "~"
        case "pu-space-1":
            return "~"
        case "pu-space-2":
            return "\\mkern3mu "
        case "1000 separator":
            return "\\mkern2mu "
        case "commaDecimal":
            return "{,}"
        case "comma enumeration L":
            return "{\(str(buf, "p1"))}\\mkern6mu "
        case "comma enumeration M":
            return "{\(str(buf, "p1"))}\\mkern3mu "
        case "comma enumeration S":
            return "{\(str(buf, "p1"))}\\mkern1mu "
        case "hyphen":
            return "\\text{-}"
        case "addition compound":
            return "\\,{\\cdot}\\,"
        case "electron dot":
            return "\\mkern1mu \\bullet\\mkern1mu "
        case "KV x":
            return "{\\times}"
        case "prime":
            return "\\prime "
        case "cdot":
            return "\\cdot "
        case "tight cdot":
            return "\\mkern1mu{\\cdot}\\mkern1mu "
        case "times":
            return "\\times "
        case "circa":
            return "{\\sim}"
        case "^":
            return "\\uparrow "
        case "v":
            return "\\downarrow "
        case "ellipsis":
            return "\\ldots "
        case "/":
            return "/"
        case " / ":
            return "\\,/\\,"
        default:
            throw MhChemError.msg("texify: unknown type (\(typ))")
        }
    }

    private static func getArrow(_ a: String) throws(MhChemError) -> String {
        switch a {
        case "->", "\u{2192}", "\u{27f6}":
            return "rightarrow"
        case "<-":
            return "leftarrow"
        case "<->":
            return "leftrightarrow"
        case "<-->":
            return "rightleftarrows"
        case "<=>", "\u{21cc}":
            return "rightleftharpoons"
        case "<=>>":
            return "rightequilibrium"
        case "<<=>":
            return "leftequilibrium"
        default:
            throw MhChemError.msg("unknown arrow \"\(a)\"")
        }
    }

    private static func getBond(_ a: String) -> String? {
        switch a {
        case "-", "1":
            return "{-}"
        case "=", "2":
            return "{=}"
        case "#", "3":
            return "{\\equiv}"
        case "~":
            return "{\\tripledash}"
        case "~-":
            return "{\\mathrlap{\\raisebox{-.1em}{$-$}}\\raisebox{.1em}{$\\tripledash$}}"
        case "~=":
            return "{\\mathrlap{\\raisebox{-.2em}{$-$}}\\mathrlap{\\raisebox{.2em}{$\\tripledash$}}-}"
        case "~--":
            return "{\\mathrlap{\\raisebox{-.2em}{$-$}}\\mathrlap{\\raisebox{.2em}{$\\tripledash$}}-}"
        case "-~-":
            return "{\\mathrlap{\\raisebox{-.2em}{$-$}}\\mathrlap{\\raisebox{.2em}{$-$}}\\tripledash}"
        case "...":
            return "{{\\cdot}{\\cdot}{\\cdot}}"
        case "....":
            return "{{\\cdot}{\\cdot}{\\cdot}{\\cdot}}"
        case "->":
            return "{\\rightarrow}"
        case "<-":
            return "{\\leftarrow}"
        case "<":
            return "{<}"
        case ">":
            return "{>}"
        default:
            return nil
        }
    }

    private static func getOperator(_ a: String) -> String? {
        switch a {
        case "+":
            return " {}+{} "
        case "-":
            return " {}-{} "
        case "=":
            return " {}={} "
        case "<":
            return " {}<{} "
        case ">":
            return " {}>{} "
        case "<<":
            return " {}\\ll{} "
        case ">>":
            return " {}\\gg{} "
        case "\\pm":
            return " {}\\pm{} "
        case "\\approx", "$\\approx$":
            return " {}\\approx{} "
        case "v", "(v)":
            return " \\downarrow{} "
        case "^", "(^)":
            return " \\uparrow{} "
        default:
            return nil
        }
    }
}
