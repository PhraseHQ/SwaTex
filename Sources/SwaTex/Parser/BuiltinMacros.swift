// Built-in text macros, mirroring KaTeX's `macros.ts` (via RaTeX macro_expander.rs).

extension MacroExpander {
    static let builtinTextMacros: [(String, String)] = [
        // ── Grouping ──
        ("\\bgroup", "{"),
        ("\\egroup", "}"),

        // ── Symbols from latex.ltx ──
        ("\\lq", "`"),
        ("\\rq", "'"),
        // \lbrack and \rbrack are in the symbol table directly
        ("\\aa", "\\r a"),
        ("\\AA", "\\r A"),

        // ── Active characters ──
        ("~", "\\nobreakspace"),

        // ── Phantoms ──
        ("\\hphantom", "\\smash{\\phantom{#1}}"),

        // ── Negated symbols ──
        ("\\not", "\\html@mathml{\\mathrel{\\mathrlap\\@not}\\nobreak}{\\char\"338}"),
        ("\\neq", "\\html@mathml{\\mathrel{\\not=}}{\\mathrel{\\char`≠}}"),
        ("\\ne", "\\neq"),
        ("\u{2260}", "\\neq"),
        ("\\notin", "\\html@mathml{\\mathrel{{\\in}\\mathllap{/\\mskip1mu}}}{\\mathrel{\\char`∉}}"),
        ("\u{2209}", "\\notin"),
        ("\\notni", "\\html@mathml{\\not\\ni}{\\mathrel{\\char`\u{220C}}}"),
        ("\u{220C}", "\\notni"),
        // \le and \ge are in the symbol table directly, not macros

        // ── amsmath iff/implies ──
        ("\\iff", "\\DOTSB\\;\\Longleftrightarrow\\;"),
        ("\\implies", "\\DOTSB\\;\\Longrightarrow\\;"),
        ("\\impliedby", "\\DOTSB\\;\\Longleftarrow\\;"),

        // ── Italic Greek capitals ──
        ("\\varGamma", "\\mathit{\\Gamma}"),
        ("\\varDelta", "\\mathit{\\Delta}"),
        ("\\varTheta", "\\mathit{\\Theta}"),
        ("\\varLambda", "\\mathit{\\Lambda}"),
        ("\\varXi", "\\mathit{\\Xi}"),
        ("\\varPi", "\\mathit{\\Pi}"),
        ("\\varSigma", "\\mathit{\\Sigma}"),
        ("\\varUpsilon", "\\mathit{\\Upsilon}"),
        ("\\varPhi", "\\mathit{\\Phi}"),
        ("\\varPsi", "\\mathit{\\Psi}"),
        ("\\varOmega", "\\mathit{\\Omega}"),

        // ── Spacing (mode-aware via \TextOrMath) ──
        ("\\,", "\\TextOrMath{\\kern{.1667em}}{\\mskip{3mu}}"),
        ("\\thinspace", "\\,"),
        ("\\>", "\\mskip{4mu}"),
        ("\\:", "\\TextOrMath{\\kern{.2222em}}{\\mskip{4mu}}"),
        ("\\medspace", "\\:"),
        ("\\;", "\\TextOrMath{\\kern{.2777em}}{\\mskip{5mu}}"),
        ("\\thickspace", "\\;"),
        ("\\!", "\\TextOrMath{\\kern{-.1667em}}{\\mskip{-3mu}}"),
        ("\\negthinspace", "\\!"),
        ("\\negmedspace", "\\TextOrMath{\\kern{-.2222em}}{\\mskip{-4mu}}"),
        ("\\negthickspace", "\\TextOrMath{\\kern{-.2777em}}{\\mskip{-5mu}}"),
        ("\\enspace", "\\kern.5em "),
        ("\\enskip", "\\hskip.5em\\relax"),
        ("\\quad", "\\hskip1em\\relax"),
        ("\\qquad", "\\hskip2em\\relax"),

        // ── Newline ──
        ("\\newline", "\\\\\\relax"),

        // ── hspace ──
        ("\\@hspace", "\\hskip #1\\relax"),
        ("\\@hspacer", "\\rule{0pt}{0pt}\\hskip #1\\relax"),

        // ── llap / rlap / clap ──
        ("\\llap", "\\mathllap{\\textrm{#1}}"),
        ("\\rlap", "\\mathrlap{\\textrm{#1}}"),
        ("\\clap", "\\mathclap{\\textrm{#1}}"),

        // ── Logos ──
        (
            "\\TeX",
            "\\textrm{\\html@mathml{T\\kern-.1667em\\raisebox{-.5ex}{E}\\kern-.125emX}{TeX}}"
        ),
        (
            "\\LaTeX",
            "\\textrm{\\html@mathml{L\\kern-.36em\\raisebox{0.21em}{\\scriptstyle A}\\kern-.15em\\TeX}{LaTeX}}"
        ),
        (
            "\\KaTeX",
            "\\textrm{\\html@mathml{K\\kern-.17em\\raisebox{0.21em}{\\scriptstyle A}\\kern-.15em\\TeX}{KaTeX}}"
        ),

        // ── imath / jmath ──
        ("\\imath", "\\html@mathml{\\@imath}{\u{0131}}"),
        ("\\jmath", "\\html@mathml{\\@jmath}{\u{0237}}"),

        // ── minuso ──
        (
            "\\minuso",
            "\\mathbin{\\html@mathml{{\\mathrlap{\\mathchoice{\\kern{0.145em}}{\\kern{0.145em}}{\\kern{0.1015em}}{\\kern{0.0725em}}\\circ}{-}}}{\\char`\u{29B5}}}"
        ),

        // ── mathstrut / underbar ──
        ("\\mathstrut", "\\vphantom{(}"),
        ("\\underbar", "\\underline{\\text{#1}}"),

        // ── Bbbk ──
        ("\\Bbbk", "\\Bbb{k}"),

        // ── substack ──
        ("\\substack", "\\begin{subarray}{c}#1\\end{subarray}"),

        // ── boxed ──
        ("\\boxed", "\\fbox{$\\displaystyle{#1}$}"),

        // ── colon ──
        (
            "\\colon",
            "\\nobreak\\mskip2mu\\mathpunct{}\\mathchoice{\\mkern-3mu}{\\mkern-3mu}{}{}{:}\\mskip6mu\\relax"
        ),

        // ── dots (string-based) ──
        ("\\dots", "\\cdots"),
        ("\\cdots", "\\@cdots"),
        ("\\dotsb", "\\cdots"),
        ("\\dotsm", "\\cdots"),
        ("\\dotsi", "\\!\\cdots"),
        ("\\dotsx", "\\ldots\\,"),
        ("\\dotso", "\\ldots"),  // other
        ("\\DOTSI", "\\relax"),
        ("\\DOTSB", "\\relax"),
        ("\\DOTSX", "\\relax"),

        // ── negated relations / corners (→ symbol table \@xxx) ──
        ("\\gvertneqq", "\\@gvertneqq"),
        ("\\lvertneqq", "\\@lvertneqq"),
        ("\\ngeqq", "\\@ngeqq"),
        ("\\ngeqslant", "\\@ngeqslant"),
        ("\\nleqq", "\\@nleqq"),
        ("\\nleqslant", "\\@nleqslant"),
        ("\\nshortmid", "\\@nshortmid"),
        ("\\nshortparallel", "\\@nshortparallel"),
        ("\\nsubseteqq", "\\@nsubseteqq"),
        ("\\nsupseteqq", "\\@nsupseteqq"),
        ("\\ulcorner", "\\@ulcorner"),
        ("\\urcorner", "\\@urcorner"),
        ("\\llcorner", "\\@llcorner"),
        ("\\lrcorner", "\\@lrcorner"),
        ("\\varsubsetneq", "\\@varsubsetneq"),
        ("\\varsubsetneqq", "\\@varsubsetneqq"),
        ("\\varsupsetneq", "\\@varsupsetneq"),
        ("\\varsupsetneqq", "\\@varsupsetneqq"),

        // ── delimiters / text (compose from existing) ──
        // Match KaTeX `macros.ts` html@mathml first branch (STIX-style white tortoise brackets).
        ("\\lBrace", "\\mathopen{\\{\\mkern-3.2mu[}"),
        ("\\rBrace", "\\mathclose{]\\mkern-3.2mu\\}}"),
        ("\\llbracket", "\\mathopen{[\\mkern-3.2mu[}"),
        ("\\rrbracket", "\\mathclose{]\\mkern-3.2mu]}"),
        ("\\copyright", "\\textcircled{c}"),
        ("\\textregistered", "\\textcircled{\\scriptsize R}"),
        ("\\textcopyright", "\\html@mathml{\\textcircled{c}}{\\char`©}"),

        // ── tmspace (TeX primitive used by \, \: \; \!) ──
        // KaTeX `\tmspace` takes 3 args: sign (+/-), mu-glue, em-kern.
        ("\\tmspace", "\\TextOrMath{\\kern#1#3}{\\mskip#1#2}\\relax"),

        // ── Unicode shorthand aliases ──
        // Mirrors the `defineMacro("\u{...}", "...")` block in KaTeX
        // `src/macros.ts`, so users can paste raw glyphs and get the same
        // expansion as the named macro.
        // Stacked relations (U+2258..U+225F).
        ("\u{2258}", "\\mathrel{\u{E258}}"),
        ("\u{2259}", "\\stackrel{\\tiny\\wedge}{=}"),
        ("\u{225A}", "\\stackrel{\\tiny\\vee}{=}"),
        ("\u{225B}", "\\stackrel{\\scriptsize\\star}{=}"),
        ("\u{225D}", "\\stackrel{\\tiny\\mathrm{def}}{=}"),
        ("\u{225E}", "\\mathrel{\u{E25E}}"),
        ("\u{225F}", "\\stackrel{\\tiny?}{=}"),
        // Misc relations / corners / punctuation.
        ("\u{27C2}", "\\perp"),
        ("\u{203C}", "\\mathclose{!\\mkern-0.8mu!}"),
        ("\u{231C}", "\\ulcorner"),
        ("\u{231D}", "\\urcorner"),
        ("\u{231E}", "\\llcorner"),
        ("\u{231F}", "\\lrcorner"),
        ("\u{00A9}", "\\copyright"),
        ("\u{00AE}", "\\textregistered"),
        // Mathtools colon variants (∷ ∹ ≔ ≕ ⩴).
        ("\u{2237}", "\\dblcolon"),
        ("\u{2239}", "\\eqcolon"),
        ("\u{2254}", "\\coloneqq"),
        ("\u{2255}", "\\eqqcolon"),
        ("\u{2A74}", "\\Coloneqq"),
        // stmaryrd brackets.
        ("\u{27E6}", "\\llbracket"),
        ("\u{27E7}", "\\rrbracket"),
        ("\u{2983}", "\\lBrace"),
        ("\u{2984}", "\\rBrace"),
        // Plimsoll.
        ("\u{29B5}", "\\minuso"),

        // ── dddot / ddddot ──
        ("\\dddot", "{\\overset{\\raisebox{-0.1ex}{\\normalsize ...}}{#1}}"),
        ("\\ddddot", "{\\overset{\\raisebox{-0.1ex}{\\normalsize ....}}{#1}}"),

        // ── vdots ──
        ("\\vdots", "{\\varvdots\\rule{0pt}{15pt}}"),
        ("\u{22EE}", "\\vdots"),

        // ── bmod / pod / pmod / mod ──
        (
            "\\bmod",
            "\\mathchoice{\\mskip1mu}{\\mskip1mu}{\\mskip5mu}{\\mskip5mu}\\mathbin{\\rm mod}\\mathchoice{\\mskip1mu}{\\mskip1mu}{\\mskip5mu}{\\mskip5mu}"
        ),
        ("\\pod", "\\allowbreak\\mathchoice{\\mkern18mu}{\\mkern8mu}{\\mkern8mu}{\\mkern8mu}(#1)"),
        ("\\pmod", "\\pod{{\\rm mod}\\mkern6mu#1}"),
        (
            "\\mod",
            "\\allowbreak\\mathchoice{\\mkern18mu}{\\mkern12mu}{\\mkern12mu}{\\mkern12mu}{\\rm mod}\\,\\,#1"
        ),

        // ── limsup / liminf / etc ──
        ("\\limsup", "\\DOTSB\\operatorname*{lim\\,sup}"),
        ("\\liminf", "\\DOTSB\\operatorname*{lim\\,inf}"),
        ("\\injlim", "\\DOTSB\\operatorname*{inj\\,lim}"),
        ("\\projlim", "\\DOTSB\\operatorname*{proj\\,lim}"),
        ("\\varlimsup", "\\DOTSB\\operatorname*{\\overline{\\mathrm{lim}}}"),
        ("\\varliminf", "\\DOTSB\\operatorname*{\\underline{\\mathrm{lim}}}"),
        ("\\varinjlim", "\\DOTSB\\operatorname*{\\underrightarrow{\\mathrm{lim}}}"),
        ("\\varprojlim", "\\DOTSB\\operatorname*{\\underleftarrow{\\mathrm{lim}}}"),

        // ── statmath ──
        ("\\argmin", "\\DOTSB\\operatorname*{arg\\,min}"),
        ("\\argmax", "\\DOTSB\\operatorname*{arg\\,max}"),
        ("\\plim", "\\DOTSB\\mathop{\\operatorname{plim}}\\limits"),

        // ── mathtools colon variants ──
        ("\\ordinarycolon", ":"),
        ("\\vcentcolon", "\\mathrel{\\mathop\\ordinarycolon}"),
        (
            "\\dblcolon",
            "\\html@mathml{\\mathrel{\\vcentcolon\\mathrel{\\mkern-.9mu}\\vcentcolon}}{\\mathop{\\char\"2237}}"
        ),
        (
            "\\coloneqq",
            "\\html@mathml{\\mathrel{\\vcentcolon\\mathrel{\\mkern-1.2mu}=}}{\\mathop{\\char\"2254}}"
        ),
        (
            "\\Coloneqq",
            "\\html@mathml{\\mathrel{\\dblcolon\\mathrel{\\mkern-1.2mu}=}}{\\mathop{\\char\"2237\\char\"3d}}"
        ),
        (
            "\\coloneq",
            "\\html@mathml{\\mathrel{\\vcentcolon\\mathrel{\\mkern-1.2mu}\\mathrel{-}}}{\\mathop{\\char\"3a\\char\"2212}}"
        ),
        (
            "\\Coloneq",
            "\\html@mathml{\\mathrel{\\dblcolon\\mathrel{\\mkern-1.2mu}\\mathrel{-}}}{\\mathop{\\char\"2237\\char\"2212}}"
        ),
        (
            "\\eqqcolon",
            "\\html@mathml{\\mathrel{=\\mathrel{\\mkern-1.2mu}\\vcentcolon}}{\\mathop{\\char\"2255}}"
        ),
        (
            "\\Eqqcolon",
            "\\html@mathml{\\mathrel{=\\mathrel{\\mkern-1.2mu}\\dblcolon}}{\\mathop{\\char\"3d\\char\"2237}}"
        ),
        (
            "\\eqcolon",
            "\\html@mathml{\\mathrel{\\mathrel{-}\\mathrel{\\mkern-1.2mu}\\vcentcolon}}{\\mathop{\\char\"2239}}"
        ),
        (
            "\\Eqcolon",
            "\\html@mathml{\\mathrel{\\mathrel{-}\\mathrel{\\mkern-1.2mu}\\dblcolon}}{\\mathop{\\char\"2212\\char\"2237}}"
        ),
        (
            "\\colonapprox",
            "\\html@mathml{\\mathrel{\\vcentcolon\\mathrel{\\mkern-1.2mu}\\approx}}{\\mathop{\\char\"3a\\char\"2248}}"
        ),
        (
            "\\Colonapprox",
            "\\html@mathml{\\mathrel{\\dblcolon\\mathrel{\\mkern-1.2mu}\\approx}}{\\mathop{\\char\"2237\\char\"2248}}"
        ),
        (
            "\\colonsim",
            "\\html@mathml{\\mathrel{\\vcentcolon\\mathrel{\\mkern-1.2mu}\\sim}}{\\mathop{\\char\"3a\\char\"223c}}"
        ),
        (
            "\\Colonsim",
            "\\html@mathml{\\mathrel{\\dblcolon\\mathrel{\\mkern-1.2mu}\\sim}}{\\mathop{\\char\"2237\\char\"223c}}"
        ),

        // ── colonequals alternate names ──
        ("\\ratio", "\\vcentcolon"),
        ("\\coloncolon", "\\dblcolon"),
        ("\\colonequals", "\\coloneqq"),
        ("\\coloncolonequals", "\\Coloneqq"),
        ("\\equalscolon", "\\eqqcolon"),
        ("\\equalscoloncolon", "\\Eqqcolon"),
        ("\\colonminus", "\\coloneq"),
        ("\\coloncolonminus", "\\Coloneq"),
        ("\\minuscolon", "\\eqcolon"),
        ("\\minuscoloncolon", "\\Eqcolon"),
        ("\\coloncolonapprox", "\\Colonapprox"),
        ("\\coloncolonsim", "\\Colonsim"),
        ("\\simcolon", "\\mathrel{\\sim\\mathrel{\\mkern-1.2mu}\\vcentcolon}"),
        ("\\simcoloncolon", "\\mathrel{\\sim\\mathrel{\\mkern-1.2mu}\\dblcolon}"),
        ("\\approxcolon", "\\mathrel{\\approx\\mathrel{\\mkern-1.2mu}\\vcentcolon}"),
        ("\\approxcoloncolon", "\\mathrel{\\approx\\mathrel{\\mkern-1.2mu}\\dblcolon}"),

        // ── braket (string-based) ──
        ("\\bra", "\\mathinner{\\langle{#1}|}"),
        ("\\ket", "\\mathinner{|{#1}\\rangle}"),
        ("\\braket", "\\mathinner{\\langle{#1}\\rangle}"),
        (
            "\\Braket",
            "\\bra@ket{\\left\\langle}{\\,\\middle\\vert\\,}{\\,\\middle\\vert\\,}{\\right\\rangle}"
        ),
        ("\\Bra", "\\left\\langle#1\\right|"),
        ("\\Ket", "\\left|#1\\right\\rangle"),

        // ── texvc (MediaWiki) ──
        ("\\darr", "\\downarrow"),
        ("\\dArr", "\\Downarrow"),
        ("\\Darr", "\\Downarrow"),
        ("\\lang", "\\langle"),
        ("\\rang", "\\rangle"),
        ("\\uarr", "\\uparrow"),
        ("\\uArr", "\\Uparrow"),
        ("\\Uarr", "\\Uparrow"),
        ("\\N", "\\mathbb{N}"),
        ("\\R", "\\mathbb{R}"),
        ("\\Z", "\\mathbb{Z}"),
        ("\\alef", "\\aleph"),
        ("\\alefsym", "\\aleph"),
        ("\\Alpha", "\\mathrm{A}"),
        ("\\Beta", "\\mathrm{B}"),
        ("\\bull", "\\bullet"),
        ("\\Chi", "\\mathrm{X}"),
        ("\\clubs", "\\clubsuit"),
        ("\\cnums", "\\mathbb{C}"),
        ("\\Complex", "\\mathbb{C}"),
        ("\\Dagger", "\\ddagger"),
        ("\\diamonds", "\\diamondsuit"),
        ("\\empty", "\\emptyset"),
        ("\\Epsilon", "\\mathrm{E}"),
        ("\\Eta", "\\mathrm{H}"),
        ("\\exist", "\\exists"),
        ("\\harr", "\\leftrightarrow"),
        ("\\hArr", "\\Leftrightarrow"),
        ("\\Harr", "\\Leftrightarrow"),
        ("\\hearts", "\\heartsuit"),
        ("\\image", "\\Im"),
        ("\\infin", "\\infty"),
        ("\\Iota", "\\mathrm{I}"),
        ("\\isin", "\\in"),
        ("\\Kappa", "\\mathrm{K}"),
        ("\\larr", "\\leftarrow"),
        ("\\lArr", "\\Leftarrow"),
        ("\\Larr", "\\Leftarrow"),
        ("\\lrarr", "\\leftrightarrow"),
        ("\\lrArr", "\\Leftrightarrow"),
        ("\\Lrarr", "\\Leftrightarrow"),
        ("\\Mu", "\\mathrm{M}"),
        ("\\natnums", "\\mathbb{N}"),
        ("\\Nu", "\\mathrm{N}"),
        ("\\Omicron", "\\mathrm{O}"),
        ("\\plusmn", "\\pm"),
        ("\\rarr", "\\rightarrow"),
        ("\\rArr", "\\Rightarrow"),
        ("\\Rarr", "\\Rightarrow"),
        ("\\real", "\\Re"),
        ("\\reals", "\\mathbb{R}"),
        ("\\Reals", "\\mathbb{R}"),
        ("\\Rho", "\\mathrm{P}"),
        ("\\sdot", "\\cdot"),
        ("\\sect", "\\S"),
        ("\\spades", "\\spadesuit"),
        ("\\sub", "\\subset"),
        ("\\sube", "\\subseteq"),
        ("\\supe", "\\supseteq"),
        ("\\Tau", "\\mathrm{T}"),
        ("\\thetasym", "\\vartheta"),
        ("\\weierp", "\\wp"),
        ("\\Zeta", "\\mathrm{Z}"),

        // ── Khan Academy color aliases ──
        ("\\blue", "\\textcolor{##6495ed}{#1}"),
        ("\\orange", "\\textcolor{##ffa500}{#1}"),
        ("\\pink", "\\textcolor{##ff00af}{#1}"),
        ("\\red", "\\textcolor{##df0030}{#1}"),
        ("\\green", "\\textcolor{##28ae7b}{#1}"),
        ("\\gray", "\\textcolor{gray}{#1}"),
        ("\\purple", "\\textcolor{##9d38bd}{#1}"),

        // ── Unicode script letters ──
        ("\u{212C}", "\\mathscr{B}"),
        ("\u{2130}", "\\mathscr{E}"),
        ("\u{2131}", "\\mathscr{F}"),
        ("\u{210B}", "\\mathscr{H}"),
        ("\u{2110}", "\\mathscr{I}"),
        ("\u{2112}", "\\mathscr{L}"),
        ("\u{2133}", "\\mathscr{M}"),
        ("\u{211B}", "\\mathscr{R}"),
        ("\u{212D}", "\\mathfrak{C}"),
        ("\u{210C}", "\\mathfrak{H}"),
        ("\u{2128}", "\\mathfrak{Z}"),

        // ── actuarialangle ──
        ("\\angln", "{\\angl n}"),

        // ── set/Set (braket notation, simplified) ──
        ("\\set", "\\bra@set{\\{\\,}{\\mid}{}{\\,\\}}"),
        (
            "\\Set",
            "\\bra@set{\\left\\{\\:}{\\;\\middle\\vert\\;}{\\;\\middle\\Vert\\;}{\\:\\right\\}}"
        ),

        // ── KaTeX mhchem (\tripledash for \bond ~ forms) ──
        (
            "\\tripledash",
            "{\\vphantom{-}\\raisebox{2.56mu}{$\\mkern2mu\\tiny\\text{-}\\mkern1mu\\text{-}\\mkern1mu\\text{-}\\mkern2mu$}}"
        ),
    ]
}
