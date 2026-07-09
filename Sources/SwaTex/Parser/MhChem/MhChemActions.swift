/// State machine actions (global + per-machine), mirroring KaTeX `mhchem.js`.
///
/// Port of RaTeX `mhchem/actions.rs`.

import Foundation

enum MhChemActions {
    // Compiled once; `Regex` values are immutable and thread-safe to share.
    nonisolated(unsafe) private static let reDigitsOnly = try! Regex(#"^[0-9]+$"#)
    nonisolated(unsafe) private static let reCelsiusC = try! Regex(#"\u{00B0}C|\^oC|\^\{o\}C"#)
    nonisolated(unsafe) private static let reCelsiusF = try! Regex(#"\u{00B0}F|\^oF|\^\{o\}F"#)
    nonisolated(unsafe) private static let reHalf =
        try! Regex(#"^([0-9]+|\$[a-z]\$|[a-z])\/([0-9]+)(\$[a-z]\$|[a-z])?$"#)

    static func apply(
        _ data: MhChemData,
        machine: String,
        buffer: MhChemBuffer,
        m: MhChemMatchToken,
        spec: MhChemActionSpec
    ) throws(MhChemError) -> [MhChemValue] {
        switch (machine, spec.type) {
        case ("ce", "output"):
            return try ceOutput(data, buffer, entity: spec.option)
        case ("ce", "o after d"):
            return try ceOAfterD(data, buffer, m)
        case ("ce", "d= kv"):
            buffer.d = tokenString(m)
            buffer.dType = "kv"
            return []
        case ("ce", "charge or bond"):
            return try ceChargeOrBond(data, buffer, m)
        case ("ce", "- after o/d"):
            let afterD = spec.option?.asBool ?? false
            return try ceAfterOD(data, buffer, m, isAfterD: afterD)
        case ("ce", "a to o"):
            buffer.o = buffer.a
            buffer.a = nil
            return []
        case ("ce", "sb=true"):
            buffer.sb = true
            return []
        case ("ce", "sb=false"):
            buffer.sb = false
            return []
        case ("ce", "beginsWithBond=true"):
            buffer.beginsWithBond = true
            return []
        case ("ce", "beginsWithBond=false"):
            buffer.beginsWithBond = false
            return []
        case ("ce", "parenthesisLevel++"):
            buffer.parenthesisLevel += 1
            return []
        case ("ce", "parenthesisLevel--"):
            buffer.parenthesisLevel -= 1
            return []
        case ("ce", "state of aggregation"):
            return [
                .object([
                    "type_": .string("state of aggregation"),
                    "p1": .array(
                        try MhChemEngine.goMachine(data, input: tokenString(m), machine: "o")),
                ])
            ]
        case ("ce", "comma"):
            return ceComma(buffer, m)
        case ("ce", "oxidation-output"):
            var v: [MhChemValue] = [.string("{")]
            v.append(
                contentsOf: try MhChemEngine.goMachine(
                    data, input: tokenString(m), machine: "oxidation"))
            v.append(.string("}"))
            return v
        case ("ce", "frac-output"):
            guard case .a(let parts) = m else {
                throw MhChemError.msg("frac-output")
            }
            guard parts.count >= 2 else {
                throw MhChemError.msg("frac-output len")
            }
            return [
                .object([
                    "type_": .string("frac-ce"),
                    "p1": .array(try MhChemEngine.goMachine(data, input: parts[0], machine: "ce")),
                    "p2": .array(try MhChemEngine.goMachine(data, input: parts[1], machine: "ce")),
                ])
            ]
        case ("ce", "overset-output"), ("ce", "underset-output"), ("ce", "underbrace-output"):
            guard case .a(let parts) = m else {
                throw MhChemError.msg("two-arg output")
            }
            guard parts.count >= 2 else {
                throw MhChemError.msg("two-arg len")
            }
            let ty =
                switch spec.type {
                case "overset-output": "overset"
                case "underset-output": "underset"
                default: "underbrace"
                }
            return [
                .object([
                    "type_": .string(ty),
                    "p1": .array(try MhChemEngine.goMachine(data, input: parts[0], machine: "ce")),
                    "p2": .array(try MhChemEngine.goMachine(data, input: parts[1], machine: "ce")),
                ])
            ]
        case ("ce", "color-output"):
            guard case .a(let parts) = m else {
                throw MhChemError.msg("color-output")
            }
            guard parts.count >= 2 else {
                throw MhChemError.msg("color-output len")
            }
            return [
                .object([
                    "type_": .string("color"),
                    "color1": .string(parts[0]),
                    "color2": .array(
                        try MhChemEngine.goMachine(data, input: parts[1], machine: "ce")),
                ])
            ]
        case ("ce", "operator"):
            let kind = spec.option?.asString ?? matchStr(m) ?? ""
            return [.object(["type_": .string("operator"), "kind_": .string(kind)])]

        case ("text", "output"):
            if let tx = buffer.text {
                buffer.clearAll()
                return [.object(["type_": .string("text"), "p1": .string(tx)])]
            }
            return []

        case ("pq", "state of aggregation"):
            return [
                .object([
                    "type_": .string("state of aggregation subscript"),
                    "p1": .array(
                        try MhChemEngine.goMachine(data, input: tokenString(m), machine: "o")),
                ])
            ]
        case ("pq", "color-output"), ("bd", "color-output"):
            guard case .a(let parts) = m else {
                throw MhChemError.msg("color bd/pq")
            }
            let sm = machine == "pq" ? "pq" : "bd"
            return [
                .object([
                    "type_": .string("color"),
                    "color1": .string(parts[0]),
                    "color2": .array(
                        try MhChemEngine.goMachine(data, input: parts[1], machine: sm)),
                ])
            ]

        case ("oxidation", "roman-numeral"):
            return [
                .object([
                    "type_": .string("roman numeral"),
                    "p1": .string(matchStr(m) ?? ""),
                ])
            ]

        case ("tex-math", "output"), ("tex-math tight", "output"):
            if let o = buffer.o {
                buffer.clearAll()
                return [.object(["type_": .string("tex-math"), "p1": .string(o)])]
            }
            return []
        case ("tex-math tight", "tight operator"):
            let op = matchStr(m) ?? ""
            buffer.o = "\(buffer.o ?? ""){\(op)}"
            return []

        case ("9,9", "comma"):
            return [.object(["type_": .string("commaDecimal")])]

        case ("pu", "enumber"):
            return try puEnumber(data, m)
        case ("pu", "number^"):
            return try puNumberPow(data, m)
        case ("pu", "space"):
            return [.object(["type_": .string("pu-space-1")])]
        case ("pu", "output"):
            return try puOutput(data, buffer)

        case ("pu-2", "cdot"):
            return [.object(["type_": .string("tight cdot")])]
        case ("pu-2", "^(-1)"):
            let pow = matchStr(m) ?? ""
            buffer.rm = "\(buffer.rm ?? "")^{\(pow)}"
            return []
        case ("pu-2", "space"):
            return [.object(["type_": .string("pu-space-2")])]
        case ("pu-2", "output"):
            return try pu2Output(data, buffer)

        case ("pu-9,9", "comma"):
            return [.object(["type_": .string("commaDecimal")])]
        case ("pu-9,9", "output-0"):
            return pu99Out(buffer, reverseTriplets: false)
        case ("pu-9,9", "output-o"):
            return pu99Out(buffer, reverseTriplets: true)

        default:
            return try globalAction(data, machine: machine, buffer: buffer, m: m, spec: spec)
        }
    }

    private static func matchStr(_ m: MhChemMatchToken) -> String? {
        switch m {
        case .s(let s):
            return s
        case .a(let v):
            return v.first
        }
    }

    private static func tokenString(_ m: MhChemMatchToken) -> String {
        switch m {
        case .s(let s):
            return s
        case .a(let v):
            return v.joined()
        }
    }

    private static func ceComma(_ buffer: MhChemBuffer, _ m: MhChemMatchToken) -> [MhChemValue] {
        let raw = tokenString(m)
        var trimmed = raw
        while let last = trimmed.last, last.isWhitespace {
            trimmed.removeLast()
        }
        let withSpace = trimmed != raw
        let ty =
            (withSpace && buffer.parenthesisLevel == 0)
            ? "comma enumeration L"
            : "comma enumeration M"
        return [.object(["type_": .string(ty), "p1": .string(trimmed)])]
    }

    private static func ceOAfterD(
        _ data: MhChemData,
        _ buffer: MhChemBuffer,
        _ m: MhChemMatchToken
    ) throws(MhChemError) -> [MhChemValue] {
        var ret: [MhChemValue] = []
        let digitsOnly = buffer.d.map { (try? reDigitsOnly.firstMatch(in: $0)) != nil } ?? false
        if digitsOnly {
            let tmp = buffer.d
            buffer.d = nil
            ret.append(contentsOf: try ceOutput(data, buffer, entity: nil))
            buffer.b = tmp
        } else {
            ret.append(contentsOf: try ceOutput(data, buffer, entity: nil))
        }
        cat(&buffer.o, m)
        return ret
    }

    private static func ceChargeOrBond(
        _ data: MhChemData,
        _ buffer: MhChemBuffer,
        _ m: MhChemMatchToken
    ) throws(MhChemError) -> [MhChemValue] {
        if buffer.beginsWithBond {
            var ret = try ceOutput(data, buffer, entity: nil)
            ret.append(.object(["type_": .string("bond"), "kind_": .string("-")]))
            return ret
        } else {
            buffer.d = tokenString(m)
            return []
        }
    }

    private static func ceAfterOD(
        _ data: MhChemData,
        _ buffer: MhChemBuffer,
        _ m: MhChemMatchToken,
        isAfterD: Bool
    ) throws(MhChemError) -> [MhChemValue] {
        let dash = tokenString(m)
        let o = buffer.o ?? ""
        let c1 = try? MhChemPatterns.matchPattern(data, "orbital", o)
        let c2 = try? MhChemPatterns.matchPattern(data, "one lowercase greek letter $", o)
        let c3 = try? MhChemPatterns.matchPattern(data, "one lowercase latin letter $", o)
        let c4 = try? MhChemPatterns.matchPattern(data, "$one lowercase latin letter$ $", o)
        let hOrb = (c1 ?? nil)?.remainder.isEmpty ?? false
        let hyphenFollows =
            dash == "-"
            && (hOrb || (c2 ?? nil) != nil || (c3 ?? nil) != nil || (c4 ?? nil) != nil)

        if hyphenFollows
            && MhChemBuffer.isSlotEmpty(buffer.a)
            && MhChemBuffer.isSlotEmpty(buffer.b)
            && MhChemBuffer.isSlotEmpty(buffer.p)
            && MhChemBuffer.isSlotEmpty(buffer.d)
            && MhChemBuffer.isSlotEmpty(buffer.q)
            && (c1 ?? nil) == nil
            && (c3 ?? nil) != nil
        {
            let oo = buffer.o ?? ""
            buffer.o = "$\(oo)$"
        }

        var ret: [MhChemValue] = []
        if hyphenFollows {
            ret.append(contentsOf: try ceOutput(data, buffer, entity: nil))
            ret.append(.object(["type_": .string("hyphen")]))
            return ret
        }

        let digitsD = try? MhChemPatterns.matchPattern(data, "digits", buffer.d ?? "")
        let dOnly = (digitsD ?? nil)?.remainder.isEmpty ?? false
        if isAfterD && dOnly {
            cat(&buffer.d, m)
            ret.append(contentsOf: try ceOutput(data, buffer, entity: nil))
        } else {
            ret.append(contentsOf: try ceOutput(data, buffer, entity: nil))
            ret.append(.object(["type_": .string("bond"), "kind_": .string("-")]))
        }
        return ret
    }

    private static func ceOutput(
        _ data: MhChemData,
        _ buffer: MhChemBuffer,
        entity: MhChemOption?
    ) throws(MhChemError) -> [MhChemValue] {
        let entityFollows = entity?.asInt

        if MhChemBuffer.isSlotEmpty(buffer.r) {
            let emptyPiece =
                MhChemBuffer.isSlotEmpty(buffer.a)
                && MhChemBuffer.isSlotEmpty(buffer.b)
                && MhChemBuffer.isSlotEmpty(buffer.p)
                && MhChemBuffer.isSlotEmpty(buffer.o)
                && MhChemBuffer.isSlotEmpty(buffer.q)
                && MhChemBuffer.isSlotEmpty(buffer.d)
                && entityFollows == nil
            if emptyPiece {
                buffer.clearSoft()
                return []
            }

            var ret: [MhChemValue] = []
            if buffer.sb {
                ret.append(.object(["type_": .string("entitySkip")]))
            }

            var dType = buffer.dType
            if !MhChemBuffer.isSlotEmpty(buffer.o)
                && dType == "kv"
                && ((try? MhChemPatterns.matchPattern(data, "d-oxidation$", buffer.d ?? "")) ?? nil)
                    != nil
            {
                dType = "oxidation"
            } else if !MhChemBuffer.isSlotEmpty(buffer.o)
                && dType == "kv"
                && MhChemBuffer.isSlotEmpty(buffer.q)
            {
                dType = nil
            }

            if MhChemBuffer.isSlotEmpty(buffer.o)
                && MhChemBuffer.isSlotEmpty(buffer.q)
                && MhChemBuffer.isSlotEmpty(buffer.d)
                && MhChemBuffer.isSlotEmpty(buffer.b)
                && MhChemBuffer.isSlotEmpty(buffer.p)
                && entityFollows != 2
            {
                buffer.o = buffer.a
                buffer.a = nil
            } else if MhChemBuffer.isSlotEmpty(buffer.o)
                && MhChemBuffer.isSlotEmpty(buffer.q)
                && MhChemBuffer.isSlotEmpty(buffer.d)
                && (!MhChemBuffer.isSlotEmpty(buffer.b) || !MhChemBuffer.isSlotEmpty(buffer.p))
            {
                buffer.o = buffer.a
                buffer.d = buffer.b
                buffer.q = buffer.p
                buffer.a = nil
                buffer.b = nil
                buffer.p = nil
            }

            let a = try MhChemEngine.goMachine(data, input: buffer.a ?? "", machine: "a")
            let b = try MhChemEngine.goMachine(data, input: buffer.b ?? "", machine: "bd")
            let p = try MhChemEngine.goMachine(data, input: buffer.p ?? "", machine: "pq")
            let o = try MhChemEngine.goMachine(data, input: buffer.o ?? "", machine: "o")
            let q = try MhChemEngine.goMachine(data, input: buffer.q ?? "", machine: "pq")
            let dSm = dType == "oxidation" ? "oxidation" : "bd"
            let d = try MhChemEngine.goMachine(data, input: buffer.d ?? "", machine: dSm)

            var chem: [(String, MhChemValue)] = [
                ("type_", .string("chemfive")),
                ("a", .array(a)),
                ("b", .array(b)),
                ("p", .array(p)),
                ("o", .array(o)),
                ("q", .array(q)),
                ("d", .array(d)),
            ]
            if let dt = dType {
                chem.append(("dType", .string(dt)))
            }
            ret.append(.obj(chem))
            buffer.clearSoft()
            return ret
        } else {
            let r = buffer.r ?? ""
            let rdt = buffer.rdt
            let rd = buffer.rd ?? ""
            let rdAst: [MhChemValue]
            if rdt == "M" {
                rdAst = try MhChemEngine.goMachine(data, input: rd, machine: "tex-math")
            } else if rdt == "T" {
                rdAst = [.object(["type_": .string("text"), "p1": .string(rd)])]
            } else {
                rdAst = try MhChemEngine.goMachine(data, input: rd, machine: "ce")
            }

            let rqt = buffer.rqt
            let rq = buffer.rq ?? ""
            let rqAst: [MhChemValue]
            if rqt == "M" {
                rqAst = try MhChemEngine.goMachine(data, input: rq, machine: "tex-math")
            } else if rqt == "T" {
                rqAst = [.object(["type_": .string("text"), "p1": .string(rq)])]
            } else {
                rqAst = try MhChemEngine.goMachine(data, input: rq, machine: "ce")
            }

            let node = MhChemValue.object([
                "type_": .string("arrow"),
                "r": .string(r),
                "rd": .array(rdAst),
                "rq": .array(rqAst),
            ])
            buffer.clearSoft()
            return [node]
        }
    }

    private static func puEnumber(
        _ data: MhChemData,
        _ m: MhChemMatchToken
    ) throws(MhChemError) -> [MhChemValue] {
        guard case .a(let parts) = m else {
            return []
        }
        var ret: [MhChemValue] = []
        let g0 = parts.first ?? ""
        if g0 == "+-" || g0 == "+/-" {
            ret.append(.string("\\pm "))
        } else if !g0.isEmpty {
            ret.append(.string(g0))
        }
        if parts.count > 1, !parts[1].isEmpty {
            ret.append(
                contentsOf: try MhChemEngine.goMachine(data, input: parts[1], machine: "pu-9,9"))
            if parts.count > 2 {
                let p2 = parts[2]
                if !p2.isEmpty {
                    if p2.contains(",") || p2.contains(".") {
                        ret.append(
                            contentsOf: try MhChemEngine.goMachine(
                                data, input: p2, machine: "pu-9,9"))
                    } else {
                        ret.append(.string(p2))
                    }
                }
            }
            // Regex group 5 = `*` / `×` branch; group 4 = `e`/`E` or `\s*...\s*10\^`. When `e` matches,
            // group 5 is present as empty string — pick the non-empty branch like KaTeX `m[5] || m[4]`.
            let gStar = parts.count > 4 ? parts[4] : ""
            let gEOrTimes = parts.count > 3 ? parts[3] : ""
            let a = gStar.trimmingCharacters(in: .whitespaces)
            let b = gEOrTimes.trimmingCharacters(in: .whitespaces)
            let mult = !a.isEmpty ? a : b
            // KaTeX mhchem: lowercase `e` → \cdot, uppercase `E` → \times (see golden 0100/0101 vs 0102/0103).
            if !mult.isEmpty {
                if mult == "e" || mult.hasPrefix("*") {
                    ret.append(.object(["type_": .string("cdot")]))
                } else {
                    ret.append(.object(["type_": .string("times")]))
                }
            }
        }
        if parts.count > 5, !parts[5].isEmpty {
            ret.append(.string("10^{\(parts[5])}"))
        }
        return ret
    }

    private static func puNumberPow(
        _ data: MhChemData,
        _ m: MhChemMatchToken
    ) throws(MhChemError) -> [MhChemValue] {
        guard case .a(let parts) = m else {
            return []
        }
        var ret: [MhChemValue] = []
        let g0 = parts.first ?? ""
        if g0 == "+-" || g0 == "+/-" {
            ret.append(.string("\\pm "))
        } else if !g0.isEmpty {
            ret.append(.string(g0))
        }
        if parts.count > 1 {
            ret.append(
                contentsOf: try MhChemEngine.goMachine(data, input: parts[1], machine: "pu-9,9"))
        }
        if parts.count > 2 {
            ret.append(.string("^{\(parts[2])}"))
        }
        return ret
    }

    private static func puOutput(
        _ data: MhChemData,
        _ buffer: MhChemBuffer
    ) throws(MhChemError) -> [MhChemValue] {
        var d = buffer.d ?? ""
        if let md = (try? MhChemPatterns.matchPattern(data, "{(...)}", d)) ?? nil,
            md.remainder.isEmpty,
            case .s(let inner) = md.token
        {
            d = inner
        }
        var qv = buffer.q ?? ""
        if let mq = (try? MhChemPatterns.matchPattern(data, "{(...)}", qv)) ?? nil,
            mq.remainder.isEmpty,
            case .s(let inner) = mq.token
        {
            qv = inner
        }
        d = d.replacing(reCelsiusC, with: "{}^{\\circ}C")
        qv = qv.replacing(reCelsiusC, with: "{}^{\\circ}C")
        d = d.replacing(reCelsiusF, with: "{}^{\\circ}F")
        qv = qv.replacing(reCelsiusF, with: "{}^{\\circ}F")

        let res: [MhChemValue]
        if !qv.isEmpty {
            let b5d = try MhChemEngine.goMachine(data, input: d, machine: "pu")
            let b5q = try MhChemEngine.goMachine(data, input: qv, machine: "pu")
            if buffer.o == "//" {
                res = [
                    .object(["type_": .string("pu-frac"), "p1": .array(b5d), "p2": .array(b5q)])
                ]
            } else {
                var v = b5d
                if b5d.count > 1 || b5q.count > 1 {
                    v.append(.object(["type_": .string(" / ")]))
                } else {
                    v.append(.object(["type_": .string("/")]))
                }
                v.append(contentsOf: b5q)
                res = v
            }
        } else {
            res = try MhChemEngine.goMachine(data, input: d, machine: "pu-2")
        }
        buffer.clearAll()
        return res
    }

    private static func pu2Output(
        _ data: MhChemData,
        _ buffer: MhChemBuffer
    ) throws(MhChemError) -> [MhChemValue] {
        var res: [MhChemValue] = []
        if let rm = buffer.rm {
            buffer.rm = nil
            if let mrm = (try? MhChemPatterns.matchPattern(data, "{(...)}", rm)) ?? nil {
                if mrm.remainder.isEmpty, case .s(let inner) = mrm.token {
                    res = try MhChemEngine.goMachine(data, input: inner, machine: "pu")
                } else if mrm.remainder.isEmpty {
                    res = []
                } else {
                    res = [.object(["type_": .string("rm"), "p1": .string(rm)])]
                }
            } else {
                res = [.object(["type_": .string("rm"), "p1": .string(rm)])]
            }
        }
        buffer.clearAll()
        return res
    }

    private static func pu99Out(_ buffer: MhChemBuffer, reverseTriplets: Bool) -> [MhChemValue] {
        let t = buffer.text ?? ""
        buffer.text = nil
        var ret: [MhChemValue] = []
        let chars = Array(t)
        if chars.count > 4 {
            if reverseTriplets {
                var a = chars.count % 3
                if a == 0 {
                    a = 3
                }
                var i = chars.count - 3
                while i > 0 {
                    ret.append(.string(String(chars[i..<i + 3])))
                    ret.append(.object(["type_": .string("1000 separator")]))
                    i -= 3
                }
                ret.append(.string(String(chars[..<a])))
                ret.reverse()
            } else {
                let a = chars.count - 3
                var i = 0
                while i < a {
                    ret.append(.string(String(chars[i..<i + 3])))
                    ret.append(.object(["type_": .string("1000 separator")]))
                    i += 3
                }
                ret.append(.string(String(chars[i...])))
            }
        } else {
            ret.append(.string(t))
        }
        buffer.clearAll()
        return ret
    }

    private static func globalAction(
        _ data: MhChemData,
        machine: String,
        buffer: MhChemBuffer,
        m: MhChemMatchToken,
        spec: MhChemActionSpec
    ) throws(MhChemError) -> [MhChemValue] {
        switch spec.type {
        case "a=":
            cat(&buffer.a, m)
            return []
        case "b=":
            cat(&buffer.b, m)
            return []
        case "p=":
            cat(&buffer.p, m)
            return []
        case "o=":
            cat(&buffer.o, m)
            return []
        case "q=":
            cat(&buffer.q, m)
            return []
        case "d=":
            cat(&buffer.d, m)
            return []
        case "rm=":
            cat(&buffer.rm, m)
            return []
        case "text=":
            cat(&buffer.text, m)
            return []
        case "r=":
            buffer.r = tokenString(m)
            return []
        case "rdt=":
            buffer.rdt = tokenString(m)
            return []
        case "rqt=":
            buffer.rqt = tokenString(m)
            return []
        case "rd=":
            buffer.rd = tokenString(m)
            return []
        case "rq=":
            buffer.rq = tokenString(m)
            return []
        case "insert":
            let opt = spec.option?.asString ?? ""
            return [.object(["type_": .string(opt)])]
        case "insert+p1":
            return [
                .object([
                    "type_": .string(spec.option?.asString ?? ""),
                    "p1": .string(matchStr(m) ?? ""),
                ])
            ]
        case "insert+p1+p2":
            guard case .a(let v) = m else {
                throw MhChemError.msg("insert+p1+p2")
            }
            guard v.count >= 2 else {
                throw MhChemError.msg("insert+p1+p2 short")
            }
            return [
                .object([
                    "type_": .string(spec.option?.asString ?? ""),
                    "p1": .string(v[0]),
                    "p2": .string(v[1]),
                ])
            ]
        case "copy":
            return [.string(tokenString(m))]
        case "rm":
            return [.object(["type_": .string("rm"), "p1": .string(matchStr(m) ?? "")])]
        case "text":
            return try MhChemEngine.goMachine(data, input: tokenString(m), machine: "text")
        case "{text}":
            var v: [MhChemValue] = [.string("{")]
            v.append(
                contentsOf: try MhChemEngine.goMachine(data, input: tokenString(m), machine: "text")
            )
            v.append(.string("}"))
            return v
        case "tex-math":
            return try MhChemEngine.goMachine(data, input: tokenString(m), machine: "tex-math")
        case "tex-math tight":
            return try MhChemEngine.goMachine(
                data, input: tokenString(m), machine: "tex-math tight")
        case "bond":
            let kind = spec.option?.asString ?? matchStr(m) ?? "-"
            return [.object(["type_": .string("bond"), "kind_": .string(kind)])]
        case "color0-output":
            guard case .a(let v) = m else {
                throw MhChemError.msg("color0-output")
            }
            return [.object(["type_": .string("color0"), "color": .string(v.first ?? "")])]
        case "ce":
            return try MhChemEngine.goMachine(data, input: tokenString(m), machine: "ce")
        case "1/2":
            return halfAction(m)
        case "9,9":
            return try MhChemEngine.goMachine(data, input: tokenString(m), machine: "9,9")
        case "operator":
            let kind = spec.option?.asString ?? matchStr(m) ?? ""
            return [.object(["type_": .string("operator"), "kind_": .string(kind)])]
        default:
            throw MhChemError.msg("mhchem bug A: \(machine) / \(spec.type)")
        }
    }

    private static func cat(_ slot: inout String?, _ m: MhChemMatchToken) {
        let t = tokenString(m)
        if let s = slot {
            slot = s + t
        } else {
            slot = t
        }
    }

    private static func halfAction(_ m: MhChemMatchToken) -> [MhChemValue] {
        var s = tokenString(m)
        var ret: [MhChemValue] = []
        if s.hasPrefix("+") || s.hasPrefix("-") {
            ret.append(.string(String(s.prefix(1))))
            s = String(s.dropFirst())
        }
        guard let cm = (try? reHalf.firstMatch(in: s)) ?? nil else {
            return []
        }
        let n1 = (cm.output[1].substring.map(String.init) ?? "").replacingOccurrences(
            of: "$", with: "")
        let n2 = cm.output[2].substring.map(String.init) ?? ""
        ret.append(.object(["type_": .string("frac"), "p1": .string(n1), "p2": .string(n2)]))
        if let t = cm.output[3].substring {
            let t3 = String(t).replacingOccurrences(of: "$", with: "")
            ret.append(.object(["type_": .string("tex-math"), "p1": .string(t3)]))
        }
        return ret
    }
}
