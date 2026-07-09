import Testing

@testable import SwaTex

/// Exact-string mhchem translation tests.
///
/// Every expected TeX string below was produced by the RaTeX (Rust) reference
/// implementation (`crates/ratex-parser/src/mhchem`, `chem_parse_str`), which is
/// itself a port of KaTeX mhchem 3.3.0. SwaTex must translate identically.
@Suite("MhChemCoverage")
struct MhChemCoverageTests {
    static let cases: [(mode: String, input: String, expected: String)] = [
        ("ce", #"H2O"#, #"{\mathrm{H}{\vphantom{X}}_{\smash[t]{2}}\mathrm{O}}"#),
        (
            "ce", #"^{227}_{90}Th+"#,
            #"{{\vphantom{X}}^{\hphantom{227}}_{\hphantom{90}}{\vphantom{X}}^{\smash[t]{\vphantom{2}}\mathllap{227}}_{\vphantom{2}\mathllap{\smash[t]{90}}}\mathrm{Th}{\vphantom{X}}^{+}}"#
        ),
        ("ce", #"C#C"#, #"{\mathrm{C}{\equiv}\mathrm{C}}"#),
        ("ce", #"A <=>> B"#, #"{\mathrm{A}\xrightequilibrium{}\mathrm{B}}"#),
        ("ce", #"A <<=> B"#, #"{\mathrm{A}\xleftequilibrium{}\mathrm{B}}"#),
        ("ce", #"KMnO4 v"#, #"{\mathrm{KMnO}{\vphantom{X}}_{\smash[t]{4}} \downarrow{} }"#),
        ("ce", #"NH3 ^"#, #"{\mathrm{NH}{\vphantom{X}}_{\smash[t]{3}} \uparrow{} }"#),
        (
            "ce", #"Fe^{II}Fe^{III}2O4"#,
            #"{\mathrm{Fe}{\vphantom{X}}^{\mathrm{II}}\mathrm{Fe}{\vphantom{X}}^{\mathrm{III}}{\vphantom{X}}_{\smash[t]{2}}\mathrm{O}{\vphantom{X}}_{\smash[t]{4}}}"#
        ),
        ("ce", #"Cu^{+II}"#, #"{\mathrm{Cu}{\vphantom{X}}^{+\mathrm{II}}}"#),
        ("ce", #"(1/2)H2O"#, #"{(1/2)\,\mathrm{H}{\vphantom{X}}_{\smash[t]{2}}\mathrm{O}}"#),
        (
            "ce", #"1/2H2O"#,
            #"{\mathchoice{\textstyle\frac{1}{2}}{\frac{1}{2}}{\frac{1}{2}}{\frac{1}{2}}\,\mathrm{H}{\vphantom{X}}_{\smash[t]{2}}\mathrm{O}}"#
        ),
        ("ce", #"$n/2$H2O"#, #"{n/2 \mathrm{H}{\vphantom{X}}_{\smash[t]{2}}\mathrm{O}}"#),
        ("ce", #"A \overset{x}{=} B"#, #"{\mathrm{A}~\overset{\mathrm{x}}{ {}={} }~\mathrm{B}}"#),
        ("ce", #"A \underset{x}{=} B"#, #"{\mathrm{A}~\underset{\mathrm{x}}{ {}={} }~\mathrm{B}}"#),
        (
            "ce", #"A \underbrace{xxx}_{yyy} B"#,
            #"{\mathrm{A}~\underbrace{\mathrm{xxx}}_{\mathrm{yyy}}~\mathrm{B}}"#
        ),
        (
            "ce", #"\color{red}{H2O}"#,
            #"{{\color{red}{\mathrm{H}{\vphantom{X}}_{\smash[t]{2}}\mathrm{O}}}}"#
        ),
        (
            "ce", #"A ->[\color{blue}{x}] B"#,
            #"{\mathrm{A}\xrightarrow{{\color{blue}{\mathrm{x}}}}\mathrm{B}}"#
        ),
        ("ce", #"A-B=C#D"#, #"{\mathrm{A}{-}\mathrm{B}{=}\mathrm{C}{\equiv}\mathrm{D}}"#),
        (
            "ce", #"A\bond{-}B\bond{=}C\bond{#}D"#,
            #"{\mathrm{A}{-}\mathrm{B}{=}\mathrm{C}{\equiv}\mathrm{D}}"#
        ),
        (
            "ce", #"A\bond{1}B\bond{2}C\bond{3}D"#,
            #"{\mathrm{A}{-}\mathrm{B}{=}\mathrm{C}{\equiv}\mathrm{D}}"#
        ),
        (
            "ce", #"A\bond{~}B\bond{~-}C"#,
            #"{\mathrm{A}{\tripledash}\mathrm{B}{\mathrlap{\raisebox{-.1em}{$-$}}\raisebox{.1em}{$\tripledash$}}\mathrm{C}}"#
        ),
        (
            "ce", #"A\bond{~--}B\bond{~=}C\bond{-~-}D"#,
            #"{\mathrm{A}{\mathrlap{\raisebox{-.2em}{$-$}}\mathrlap{\raisebox{.2em}{$\tripledash$}}-}\mathrm{B}{\mathrlap{\raisebox{-.2em}{$-$}}\mathrlap{\raisebox{.2em}{$\tripledash$}}-}\mathrm{C}{\mathrlap{\raisebox{-.2em}{$-$}}\mathrlap{\raisebox{.2em}{$-$}}\tripledash}\mathrm{D}}"#
        ),
        (
            "ce", #"A\bond{...}B\bond{....}C"#,
            #"{\mathrm{A}{{\cdot}{\cdot}{\cdot}}\mathrm{B}{{\cdot}{\cdot}{\cdot}{\cdot}}\mathrm{C}}"#
        ),
        (
            "ce", #"A\bond{->}B\bond{<-}C"#,
            #"{\mathrm{A}{\rightarrow}\mathrm{B}{\leftarrow}\mathrm{C}}"#
        ),
        ("ce", #"Br-"#, #"{\mathrm{Br}{\vphantom{X}}^{-}}"#),
        ("ce", #". OH"#, #"{\,{\cdot}\,\mathrm{OH}}"#),
        (
            "ce", #"^. OH"#,
            #"{{\vphantom{X}}^{\hphantom{\mkern1mu \bullet\mkern1mu }}_{\hphantom{}}{\vphantom{X}}^{\smash[t]{\vphantom{2}}\mathllap{\mkern1mu \bullet\mkern1mu }}_{\vphantom{2}\mathllap{\smash[t]{}}}\mathrm{OH}}"#
        ),
        (
            "ce", #"H{}^3HO"#,
            #"{\mathrm{H}{\vphantom{X}}^{\hphantom{3}}_{\hphantom{}}{\vphantom{X}}^{\smash[t]{\vphantom{2}}\mathllap{3}}_{\vphantom{2}\mathllap{\smash[t]{}}}\mathrm{HO}}"#
        ),
        (
            "ce", #"SO4^2- + Ba^2+ -> BaSO4 v"#,
            #"{\mathrm{SO}{\vphantom{X}}_{\smash[t]{4}}{\vphantom{X}}^{2-} {}+{} \mathrm{Ba}{\vphantom{X}}^{2+}\xrightarrow{}\mathrm{BaSO}{\vphantom{X}}_{\smash[t]{4}} \downarrow{} }"#
        ),
        ("ce", #"NaOH(aq,$\infty$)"#, #"{\mathrm{NaOH}\mskip2mu (\mathrm{aq},\infty )}"#),
        (
            "ce", #""foo" + H2O"#,
            #"{"\mathrm{foo}" {}+{} \mathrm{H}{\vphantom{X}}_{\smash[t]{2}}\mathrm{O}}"#
        ),
        ("ce", #"{H+}"#, #"{{\text{H+}}}"#),
        ("ce", #"$x$ + H2O"#, #"{x  {}+{} \mathrm{H}{\vphantom{X}}_{\smash[t]{2}}\mathrm{O}}"#),
        ("ce", #"A ->[$x$][$y$] B"#, #"{\mathrm{A}\xrightarrow[{y }]{x }\mathrm{B}}"#),
        (
            "ce", #"A ->[{above}][{below}] B"#,
            #"{\mathrm{A}\xrightarrow[{{\text{below}}}]{{\text{above}}}\mathrm{B}}"#
        ),
        (
            "ce", #"KCr(SO4)2 * 12 H2O"#,
            #"{\mathrm{KCr}(\mathrm{SO}{\vphantom{X}}_{\smash[t]{4}}){\vphantom{X}}_{\smash[t]{2}}\,{\cdot}\,12\,\mathrm{H}{\vphantom{X}}_{\smash[t]{2}}\mathrm{O}}"#
        ),
        (
            "ce", #"CuSO4.5H2O"#,
            #"{\mathrm{CuSO}{\vphantom{X}}_{\smash[t]{4}}\,{\cdot}\,5\,\mathrm{H}{\vphantom{X}}_{\smash[t]{2}}\mathrm{O}}"#
        ),
        ("ce", #"Fe^n+"#, #"{\mathrm{Fe}{\vphantom{X}}^{n +}}"#),
        ("ce", #"NO_x"#, #"{\mathrm{NO}{\vphantom{X}}_{\smash[t]{x }}}"#),
        ("ce", #"mu-Cl"#, #"{\mathrm{mu}{-}\mathrm{Cl}}"#),
        ("ce", #"pH = 7"#, #"{\mathrm{pH} {}={} 7}"#),
        ("ce", #"2,5 H2O"#, #"{2{,}5\,\mathrm{H}{\vphantom{X}}_{\smash[t]{2}}\mathrm{O}}"#),
        ("ce", #"0.5 H2O"#, #"{0.5\,\mathrm{H}{\vphantom{X}}_{\smash[t]{2}}\mathrm{O}}"#),
        (
            "ce", #"H2O(l)"#,
            #"{\mathrm{H}{\vphantom{X}}_{\smash[t]{2}}\mathrm{O}\mskip2mu (\mathrm{l})}"#
        ),
        (
            "ce", #"H2O_{(l)}"#,
            #"{\mathrm{H}{\vphantom{X}}_{\smash[t]{2}}\mathrm{O}{\vphantom{X}}_{\smash[t]{\mskip1mu (\mathrm{l})}}}"#
        ),
        (
            "ce", #"CO3^2-(aq)"#,
            #"{\mathrm{CO}{\vphantom{X}}_{\smash[t]{3}}{\vphantom{X}}^{2-}\mskip2mu (\mathrm{aq})}"#
        ),
        (
            "ce", #"(NH4)2S"#,
            #"{(\mathrm{NH}{\vphantom{X}}_{\smash[t]{4}}){\vphantom{X}}_{\smash[t]{2}}\mathrm{S}}"#
        ),
        ("ce", #"Xy^2+Z"#, #"{\mathrm{Xy}{\vphantom{X}}^{2+}\mathrm{Z}}"#),
        ("ce", #"albumin"#, #"{\mathrm{albumin}}"#),
        ("ce", #"A <--> B"#, #"{\mathrm{A}\xrightleftarrows{}\mathrm{B}}"#),
        ("ce", #"A <-> B"#, #"{\mathrm{A}\xleftrightarrow{}\mathrm{B}}"#),
        ("ce", #"A <- B"#, #"{\mathrm{A}\xleftarrow{}\mathrm{B}}"#),
        ("ce", #"A .. B"#, #"{\mathrm{A}\,{\cdot}\,\,{\cdot}\,\mathrm{B}}"#),
        ("ce", #"A ... B"#, #"{\mathrm{A}~\ldots ~\mathrm{B}}"#),
        (
            "ce", #"x Na(NH4)HPO4 ->[\Delta] (NaPO3)_x + x NH3 ^ + x H2O"#,
            #"{x\,\mathrm{Na}(\mathrm{NH}{\vphantom{X}}_{\smash[t]{4}})\mathrm{HPO}{\vphantom{X}}_{\smash[t]{4}}\xrightarrow{\mathrm{\Delta}}(\mathrm{NaPO}{\vphantom{X}}_{\smash[t]{3}}){\vphantom{X}}_{\smash[t]{x }} {}+{} x\,\mathrm{NH}{\vphantom{X}}_{\smash[t]{3}} \uparrow{}  {}+{} x\,\mathrm{H}{\vphantom{X}}_{\smash[t]{2}}\mathrm{O}}"#
        ),
        (
            "ce", #"Zn^2+ <=>[+ 2OH-][+ 2H+] $\underset{\text{amph.}}{\ce{Zn(OH)2 v}}$"#,
            #"{\mathrm{Zn}{\vphantom{X}}^{2+}\xrightleftharpoons[{ {}+{} 2\,\mathrm{H}{\vphantom{X}}^{+}}]{ {}+{} 2\,\mathrm{OH}{\vphantom{X}}^{-}}\underset{\text{amph.}}{\ce{Zn(OH)2 v}} }"#
        ),
        (
            "ce", #"$K = \frac{[\ce{Hg^2+}][\ce{Hg}]}{[\ce{Hg2^2+}]}$"#,
            #"{K = \frac{[\ce{Hg^2+}][\ce{Hg}]}{[\ce{Hg2^2+}]} }"#
        ),
        ("ce", #"\{H2O\}"#, #"{\{\mathrm{H}{\vphantom{X}}_{\smash[t]{2}}\mathrm{O}\}}"#),
        ("ce", #"(aq)"#, #"{\mskip2mu (\mathrm{aq})}"#),
        ("ce", #"\ca 5 g"#, #"{{\sim}5\,\mathrm{g}}"#),
        ("ce", #"A + B"#, #"{\mathrm{A} {}+{} \mathrm{B}}"#),
        ("ce", #"A - B"#, #"{\mathrm{A} {}-{} \mathrm{B}}"#),
        ("ce", #"A = B"#, #"{\mathrm{A} {}={} \mathrm{B}}"#),
        ("ce", #"A \pm B"#, #"{\mathrm{A} {}\pm{} \mathrm{B}}"#),
        ("pu", #"123 kJ"#, #"{123~\mathrm{kJ}}"#),
        ("pu", #"123 mm2"#, #"{123~\mathrm{mm^{2}}}"#),
        ("pu", #"123 J s"#, #"{123~\mathrm{J}\mkern3mu \mathrm{s}}"#),
        ("pu", #"123 J*s"#, #"{123~\mathrm{J}\mkern1mu{\cdot}\mkern1mu \mathrm{s}}"#),
        ("pu", #"123 kJ/mol"#, #"{123~\mathrm{kJ}/\mathrm{mol}}"#),
        (
            "pu", #"123 kJ//mol"#,
            #"{123~\mathchoice{\textstyle\frac{\mathrm{kJ}}{\mathrm{mol}}}{\frac{\mathrm{kJ}}{\mathrm{mol}}}{\frac{\mathrm{kJ}}{\mathrm{mol}}}{\frac{\mathrm{kJ}}{\mathrm{mol}}}}"#
        ),
        ("pu", #"123 kJ.mol-1"#, #"{123~\mathrm{kJ}\mkern1mu{\cdot}\mkern1mu \mathrm{mol^{-1}}}"#),
        ("pu", #"123 kJ mol-1"#, #"{123~\mathrm{kJ}\mkern3mu \mathrm{mol^{-1}}}"#),
        ("pu", #"1.2e3 J"#, #"{1.2\cdot 10^{3}~\mathrm{J}}"#),
        ("pu", #"1,2e3 J"#, #"{1{,}2\cdot 10^{3}~\mathrm{J}}"#),
        ("pu", #"1.2E3 J"#, #"{1.2\times 10^{3}~\mathrm{J}}"#),
        ("pu", #"1.2*10^3 J"#, #"{1.2\cdot 10^{3}~\mathrm{J}}"#),
        ("pu", #"1e-7 s"#, #"{1\cdot 10^{-7}~\mathrm{s}}"#),
        ("pu", #"1234567 J"#, #"{123\mkern2mu 456\mkern2mu 7~\mathrm{J}}"#),
        ("pu", #"0.1234567 kg"#, #"{0.1\mkern2mu 234\mkern2mu 567~\mathrm{kg}}"#),
        ("pu", #"123.456,78"#, #"{123.456~\mathrm{,^{78}}}"#),
        ("pu", #"3.4e-3"#, #"{3.4\cdot 10^{-3}}"#),
        ("pu", #"2.5-3.5 mm"#, #"{2.5-3.5~\mathrm{mm}}"#),
        ("pu", #"$x$ m"#, #"{\mathrm{$x$}\mkern3mu \mathrm{m}}"#),
        ("pu", #"+-12 m"#, #"{\pm 12~\mathrm{m}}"#),
        ("pu", #"25.0 +- 0.5 g"#, #"{25.0 {}\pm{} 0.5~\mathrm{g}}"#),
        ("pu", #"10^3 m"#, #"{10^{3}~\mathrm{m}}"#),
        ("pu", #"2^24 B"#, #"{2^{24}~\mathrm{B}}"#),
        ("pu", #"123 456 789 J"#, #"{123~\mathrm{456}\mkern3mu \mathrm{789}\mkern3mu \mathrm{J}}"#),
        ("pu", #"0,123456 kg"#, #"{0{,}123\mkern2mu 456~\mathrm{kg}}"#),
        ("ce", #"A ->M[$x+y$] B"#, #"{\mathrm{A}\xrightarrow{$x+y$ }\mathrm{B}}"#),
        ("ce", #"A ->T[hello] B"#, #"{\mathrm{A}\xrightarrow{\text{hello}}\mathrm{B}}"#),
        (
            "ce", #"A ->C[H2O] B"#,
            #"{\mathrm{A}\xrightarrow{\mathrm{H}{\vphantom{X}}_{\smash[t]{2}}\mathrm{O}}\mathrm{B}}"#
        ),
        (
            "ce", #"A ->[above]M[$z$] B"#,
            #"{\mathrm{A}\xrightarrow[{$z$ }]{\mathrm{above}}\mathrm{B}}"#
        ),
        (
            "ce", #"A ->[above]T[below text] B"#,
            #"{\mathrm{A}\xrightarrow[{\text{below text}}]{\mathrm{above}}\mathrm{B}}"#
        ),
        (
            "ce", #"A ->[above]C[H2O] B"#,
            #"{\mathrm{A}\xrightarrow[{\mathrm{H}{\vphantom{X}}_{\smash[t]{2}}\mathrm{O}}]{\mathrm{above}}\mathrm{B}}"#
        ),
        ("ce", #"+II"#, #"{{+\mathrm{II}}}"#),
        ("ce", #"-IX"#, #"{{-\mathrm{IX}}}"#),
        ("ce", #"\pm0"#, #"{{\pm0}}"#),
        ("ce", #"$\pm$0"#, #"{{\pm 0}}"#),
        ("ce", #"Fe^{+III}"#, #"{\mathrm{Fe}{\vphantom{X}}^{+\mathrm{III}}}"#),
        ("ce", #"2"#, #"{2}"#),
        (
            "ce", #"1/2"#,
            #"{\mathchoice{\textstyle\frac{1}{2}}{\frac{1}{2}}{\frac{1}{2}}{\frac{1}{2}}}"#
        ),
        ("ce", #"-H"#, #"{{-}\mathrm{H}}"#),
        ("ce", #"=C"#, #"{{=}\mathrm{C}}"#),
        ("ce", #"#N"#, #"{{\equiv}\mathrm{N}}"#),
        ("ce", #"~A"#, #"{~\mathrm{A}}"#),
        ("ce", #"^2"#, #"{{\vphantom{X}}^{2}}"#),
        ("ce", #"_3"#, #"{{\vphantom{X}}_{\smash[t]{3}}}"#),
        ("ce", #"^{32}"#, #"{{\vphantom{X}}^{32}}"#),
        (
            "ce", #"C2-C3"#,
            #"{\mathrm{C}{\vphantom{X}}_{\smash[t]{2}}{-}\mathrm{C}{\vphantom{X}}_{\smash[t]{3}}}"#
        ),
        ("ce", #"A2-B"#, #"{\mathrm{A}{\vphantom{X}}_{\smash[t]{2}}{-}\mathrm{B}}"#),
        (
            "ce", #"CH3-CH3"#,
            #"{\mathrm{CH}{\vphantom{X}}_{\smash[t]{3}}{-}\mathrm{CH}{\vphantom{X}}_{\smash[t]{3}}}"#
        ),
        ("ce", #"pi-Bond"#, #"{\mathrm{pi}{-}\mathrm{Bond}}"#),
        ("ce", #"sp3-C"#, #"{\mathrm{sp}{\vphantom{X}}_{\smash[t]{3}}\text{-}\mathrm{C}}"#),
        ("ce", #"d-D"#, #"{d \text{-}\mathrm{D}}"#),
        (
            "ce", #"NO_{\color{blue}{x}}"#,
            #"{\mathrm{NO}{\vphantom{X}}_{\smash[t]{{\color{blue}{x }}}}}"#
        ),
        (
            "ce", #"H_{\color{red}{2}}O"#,
            #"{\mathrm{H}{\vphantom{X}}_{\smash[t]{{\color{red}{2}}}}\mathrm{O}}"#
        ),
        ("ce", #"$x$-A"#, #"{x \text{-}\mathrm{A}}"#),
        ("ce", #"e-"#, #"{\mathrm{e}{\vphantom{X}}^{-}}"#),
        ("ce", #"e-(aq)"#, #"{\mathrm{e}{\vphantom{X}}^{-}\mskip2mu (\mathrm{aq})}"#),
        ("ce", #"OCO^{.-}"#, #"{\mathrm{OCO}{\vphantom{X}}^{\mkern1mu \bullet\mkern1mu -}}"#),
        (
            "ce", #"NO3^{.2-}"#,
            #"{\mathrm{NO}{\vphantom{X}}_{\smash[t]{3}}{\vphantom{X}}^{\mkern1mu \bullet\mkern1mu 2-}}"#
        ),
        ("ce", #"X-$x$"#, #"{\mathrm{X}{-}x }"#),
        ("ce", #"Y^{$x$}"#, #"{\mathrm{Y}{\vphantom{X}}^{x }}"#),
        ("pu", #"123 {kJ}"#, #"{123~\mathrm{kJ}}"#),
        ("pu", #"{kJ}"#, #"{\mathrm{kJ}}"#),
        ("pu", #"+-10^3 m"#, #"{\pm 10^{3}~\mathrm{m}}"#),
        ("pu", #"+/-12 m"#, #"{\pm 12~\mathrm{m}}"#),
        (
            "pu", #"1.2e3.4 J"#,
            #"{1.2\cdot 10^{3}~\mkern1mu{\cdot}\mkern1mu \mathrm{4}\mkern3mu \mathrm{J}}"#
        ),
        ("pu", #"1,2e3,4 J"#, #"{1{,}2\cdot 10^{3}~\mathrm{,^{4}}\mkern3mu \mathrm{J}}"#),
        ("pu", #"kJ/mol"#, #"{\mathrm{kJ}/\mathrm{mol}}"#),
        (
            "pu", #"kJ//mol"#,
            #"{\mathchoice{\textstyle\frac{\mathrm{kJ}}{\mathrm{mol}}}{\frac{\mathrm{kJ}}{\mathrm{mol}}}{\frac{\mathrm{kJ}}{\mathrm{mol}}}{\frac{\mathrm{kJ}}{\mathrm{mol}}}}"#
        ),
        ("pu", #"123 kJ / mol"#, #"{123~\mathrm{kJ}/\mathrm{mol}}"#),
        ("pu", #"J_2"#, #"{\mathrm{J_^{2}}}"#),
        ("pu", #"m_e"#, #"{\mathrm{m_e}}"#),
        ("pu", #"37.4;37.6 mm"#, #"{37.4~\mathrm{;^{37.6}}\mkern3mu \mathrm{mm}}"#),
        (
            "pu", #"1..2 s"#,
            #"{1~\mkern1mu{\cdot}\mkern1mu \mkern1mu{\cdot}\mkern1mu \mathrm{2}\mkern3mu \mathrm{s}}"#
        ),
        ("pu", #"-9,8 m"#, #"{-9{,}8~\mathrm{m}}"#),
        ("pu", #".5 kg"#, #"{.5~\mathrm{kg}}"#),
        ("pu", #",5 kg"#, #"{\mathrm{,^{5}}\mkern3mu \mathrm{kg}}"#),
        ("pu", #"123e4"#, #"{123\cdot 10^{4}}"#),
        ("ce", #"A ~ B"#, #"{\mathrm{A}~~~\mathrm{B}}"#),
        ("ce", #"1,2-DCB"#, #"{1,2\text{-}\mathrm{DCB}}"#),
        ("ce", #"0,1-DCB"#, #"{0,1\text{-}\mathrm{DCB}}"#),
        ("ce", #"Zn(s)"#, #"{\mathrm{Zn}\mskip2mu (\mathrm{s})}"#),
        ("ce", #"\ca100"#, #"{{\sim}100}"#),
        ("ce", #"{$x$}"#, #"{{x }}"#),
        ("ce", #"$2n$/2"#, #"{2n /2}"#),
        ("ce", #"(1/2)"#, #"{(1/2)}"#),
        (
            "ce", #"n/2"#,
            #"{\mathchoice{\textstyle\frac{n}{2}}{\frac{n}{2}}{\frac{n}{2}}{\frac{n}{2}}}"#
        ),
        ("ce", #"iPr"#, #"{\mathrm{iPr}}"#),
        ("ce", #"tBu"#, #"{t\,\mathrm{Bu}}"#),
        ("ce", #"H3O+"#, #"{\mathrm{H}{\vphantom{X}}_{\smash[t]{3}}\mathrm{O}{\vphantom{X}}^{+}}"#),
        ("ce", #"D2O"#, #"{\mathrm{D}{\vphantom{X}}_{\smash[t]{2}}\mathrm{O}}"#),
        ("ce", #"TiO2"#, #"{\mathrm{TiO}{\vphantom{X}}_{\smash[t]{2}}}"#),
        ("ce", #"A $->$ B"#, #"{\mathrm{A}~{-> }~\mathrm{B}}"#),
        ("ce", #"A\,B"#, #"{\mathrm{A}\,\mathrm{B}}"#),
        ("ce", #"A\;B"#, #"{\mathrm{A}\;\mathrm{B}}"#),
        ("ce", #"A\hspace{1em}B"#, #"{\mathrm{A}\hspace{1em}\mathrm{B}}"#),
        ("ce", #"A\nobreak B"#, #"{\mathrm{A}\nobreak \mathrm{B}}"#),
        ("ce", #"\underset{x}{Y}"#, #"{\underset{\mathrm{x}}{\mathrm{Y}}}"#),
        ("ce", #"\overset{x}{Y}Z"#, #"{\overset{\mathrm{x}}{\mathrm{Y}}\mathrm{Z}}"#),
        (
            "ce", #"^{13}C"#,
            #"{{\vphantom{X}}^{\hphantom{13}}_{\hphantom{}}{\vphantom{X}}^{\smash[t]{\vphantom{2}}\mathllap{13}}_{\vphantom{2}\mathllap{\smash[t]{}}}\mathrm{C}}"#
        ),
        ("ce", #"e^-"#, #"{\mathrm{e}{\vphantom{X}}^{-}}"#),
        ("ce", #"\gamma"#, #"{\mathrm{\gamma}}"#),
        ("ce", #"\mu-Cl"#, #"{\mathrm{\mu}\text{-}\mathrm{Cl}}"#),
        (
            "ce", #"[Co(NH3)6]^3+"#,
            #"{[\mathrm{Co}(\mathrm{NH}{\vphantom{X}}_{\smash[t]{3}}){\vphantom{X}}_{\smash[t]{6}}]{\vphantom{X}}^{3+}}"#
        ),
        (
            "ce", #"Ca^2+ + CO3^2- <=> CaCO3"#,
            #"{\mathrm{Ca}{\vphantom{X}}^{2+} {}+{} \mathrm{CO}{\vphantom{X}}_{\smash[t]{3}}{\vphantom{X}}^{2-}\xrightleftharpoons{}\mathrm{CaCO}{\vphantom{X}}_{\smash[t]{3}}}"#
        ),
        ("ce", #"$\ce{H2O}$"#, #"{\mathrm{H}{\vphantom{X}}_{\smash[t]{2}}\mathrm{O}}"#),
        ("ce", #"A / B"#, #"{\mathrm{A}~/~\mathrm{B}}"#),
        ("ce", #"A // B"#, #"{\mathrm{A}~//~\mathrm{B}}"#),
        ("ce", #"A < B"#, #"{\mathrm{A} {}<{} \mathrm{B}}"#),
        ("ce", #"A > B"#, #"{\mathrm{A} {}>{} \mathrm{B}}"#),
        ("ce", #"A << B"#, #"{\mathrm{A} {}\ll{} \mathrm{B}}"#),
        ("ce", #"A >> B"#, #"{\mathrm{A} {}\gg{} \mathrm{B}}"#),
        ("ce", #"A \approx B"#, #"{\mathrm{A} {}\approx{} \mathrm{B}}"#),
        ("ce", #"^ A"#, #"{ \uparrow{} ~\mathrm{A}}"#),
        ("ce", #"v A"#, #"{ \downarrow{} ~\mathrm{A}}"#),
        ("ce", #"(v) X"#, #"{ \downarrow{} ~\mathrm{X}}"#),
        ("ce", #"(^) X"#, #"{ \uparrow{} ~\mathrm{X}}"#),
        ("ce", #"--A"#, #"{{-}{-}\mathrm{A}}"#),
        ("ce", #"-{-}A"#, #"{{-}{\text{-}}\mathrm{A}}"#),
        ("ce", #"-2"#, #"{{-2}}"#),
        ("ce", #"- -A"#, #"{ {}-{} {-}\mathrm{A}}"#),
        (
            "ce", #"C2- C"#,
            #"{\mathrm{C}{\vphantom{X}}_{\smash[t]{2}}{\vphantom{X}}^{-}~\mathrm{C}}"#
        ),
        ("ce", #"H2-"#, #"{\mathrm{H}{\vphantom{X}}_{\smash[t]{2}}{\vphantom{X}}^{-}}"#),
        (
            "ce", #"A2- B"#,
            #"{\mathrm{A}{\vphantom{X}}_{\smash[t]{2}}{\vphantom{X}}^{-}~\mathrm{B}}"#
        ),
        ("ce", #"2$x$"#, #"{2x }"#),
        ("ce", #"2 $x$"#, #"{2\,x }"#),
        ("ce", #"3x"#, #"{3\,\mathrm{x}}"#),
        ("ce", #"H_{2,5}O"#, #"{\mathrm{H}{\vphantom{X}}_{\smash[t]{2{,}5}}\mathrm{O}}"#),
        ("ce", #"1,2,3-trimethyl"#, #"{1,2{,}\mkern3mu 3\text{-}\mathrm{trimethyl}}"#),
        (
            "ce", #"2.5,3H2O"#,
            #"{2.5{,}\mkern3mu 3\,\mathrm{H}{\vphantom{X}}_{\smash[t]{2}}\mathrm{O}}"#
        ),
        (
            "ce", #"Fe(CN)_{6/2}"#,
            #"{\mathrm{Fe}(\mathrm{CN}){\vphantom{X}}_{\smash[t]{\mathchoice{\textstyle\frac{6}{2}}{\frac{6}{2}}{\frac{6}{2}}{\frac{6}{2}}}}}"#
        ),
        ("ce", #"(1/2)x"#, #"{(1/2)\,\mathrm{x}}"#),
        ("ce", #"$a$ b"#, #"{a \,\mathrm{b}}"#),
        ("pu", #"kg-m"#, #"{\mathrm{kg-m}}"#),
        ("pu", #"a-b"#, #"{\mathrm{a-b}}"#),
        ("pu", #"123 abc-def"#, #"{123~\mathrm{abc-def}}"#),
        ("pu", #""#, #""#),
        ("pu", #" "#, #""#),
        ("pu", #"1e2.3"#, #"{1\cdot 10^{2}~\mkern1mu{\cdot}\mkern1mu \mathrm{3}}"#),
        ("pu", #"1.2e3,4"#, #"{1.2\cdot 10^{3}~\mathrm{,^{4}}}"#),
        ("pu", #"1,2e3.4"#, #"{1{,}2\cdot 10^{3}~\mkern1mu{\cdot}\mkern1mu \mathrm{4}}"#),
        ("pu", #"-10^3 m"#, #"{-10^{3}~\mathrm{m}}"#),
        ("pu", #"+10^3 m"#, #"{+10^{3}~\mathrm{m}}"#),
        ("pu", #"-2^24"#, #"{-2^{24}}"#),
        ("pu", #"J_{123}"#, #"{\mathrm{J_{123}}}"#),
        ("pu", #"J_2 s"#, #"{\mathrm{J_^{2}}\mkern3mu \mathrm{s}}"#),
        ("pu", #"123 / s"#, #"{123~\mathrm{/}\mkern3mu \mathrm{s}}"#),
        ("pu", #"/s"#, #"{\mathrm{/s}}"#),
        ("pu", #"123 //s"#, #"{123~\mathrm{/}/\mathrm{s}}"#),
        ("pu", #"{123}"#, #"{\mathrm{123}}"#),
        ("pu", #"\mathrm{kJ}"#, #"{\mathrm{\mathrm{kJ}}}"#),
        ("pu", #"123 \mathrm{kJ}"#, #"{123~\mathrm{\mathrm{kJ}}}"#),
        ("pu", #"12.34,56"#, #"{12.34~\mathrm{,^{56}}}"#),
        ("pu", #"123.4,5,6"#, #"{123.4~\mathrm{,^{5,6}}}"#),
        ("pu", #"1 000 000"#, #"{1~\mathrm{000}\mkern3mu \mathrm{000}}"#),
        (
            "ce", #"A ->[{\color{red} x}] B"#,
            #"{\mathrm{A}\xrightarrow{{\color{red}\text{ x}}}\mathrm{B}}"#
        ),
        (
            "ce", #"H\bond{~--}H"#,
            #"{\mathrm{H}{\mathrlap{\raisebox{-.2em}{$-$}}\mathrlap{\raisebox{.2em}{$\tripledash$}}-}\mathrm{H}}"#
        ),
        ("ce", #"A =- B"#, #"{\mathrm{A}~{=}{-}~\mathrm{B}}"#),
        ("ce", #"A-=B"#, #"{\mathrm{A}{-}{=}\mathrm{B}}"#),
        ("ce", #"\pu{123 kJ}"#, #"{\pu{123 kJ}}"#),
        ("ce", #"{\pu{1 s}}"#, #"{{\pu{1 s}}}"#),
    ]

    @Test(arguments: 0..<cases.count)
    func exactTranslation(_ i: Int) throws {
        let c = Self.cases[i]
        let got = try MhChem.chemParseStr(c.input, mode: c.mode)
        #expect(got == c.expected, Comment(rawValue: "input: \(c.input)"))
    }

    /// Inputs the Rust engine rejects; SwaTex must reject them identically.
    static let errorCases: [(mode: String, input: String)] = [
        ("ce", #"\color{red} H2O"#),
        ("ce", #"A\bond{\color{red}{-}}B"#),
        ("ce", #"\color{red}$x$"#),
        ("ce", #"A ->[\color{red}x] B"#),
    ]

    @Test(arguments: 0..<errorCases.count)
    func rejects(_ i: Int) {
        let c = Self.errorCases[i]
        #expect(throws: MhChemError.self) {
            try MhChem.chemParseStr(c.input, mode: c.mode)
        }
    }

    /// Translations whose TeX also fails to parse in the Rust reference
    /// engine (raw `$...$` fragments / `\mathrm{J_^{2}}`).
    static let skipParse: Set<String> = [
        "ce\u{1F}" + #"A ->M[$x+y$] B"#,
        "ce\u{1F}" + #"A ->[above]M[$z$] B"#,
        "pu\u{1F}" + #"$x$ m"#,
        "pu\u{1F}" + #"J_2"#,
        "pu\u{1F}" + #"J_2 s"#,
    ]

    /// The translated TeX must itself parse (cross-checked with Rust).
    @Test(arguments: 0..<cases.count)
    func translationParses(_ i: Int) throws {
        let c = Self.cases[i]
        if c.input.trimmingCharacters(in: .whitespaces).isEmpty
            || Self.skipParse.contains("\(c.mode)\u{1F}\(c.input)")
        {
            return
        }
        let wrapped = "\\\(c.mode){\(c.input)}"
        _ = try parseLaTeX(wrapped)
    }
}
