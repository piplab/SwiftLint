import Foundation
import SourceKittenFramework

public struct UnneededParenthesesInClosureArgumentRule: ConfigurationProviderRule, CorrectableRule, OptInRule,
                                                        AutomaticTestableRule {
    public var configuration = SeverityConfiguration(.warning)

    public init() {}

    public static let description = RuleDescription(
        identifier: "unneeded_parentheses_in_closure_argument",
        name: "Unneeded Parentheses in Closure Argument",
        description: "Parentheses are not needed when declaring closure arguments.",
        kind: .style,
        nonTriggeringExamples: [
            "let foo = { (bar: Int) in }\n",
            "let foo = { bar, _  in }\n",
            "let foo = { bar in }\n",
            "let foo = { bar -> Bool in return true }\n"
        ],
        triggeringExamples: [
            "call(arg: { ↓(bar) in })\n",
            "call(arg: { ↓(bar, _) in })\n",
            "let foo = { ↓(bar) -> Bool in return true }\n",
            "foo.map { ($0, $0) }.forEach { ↓(x, y) in }",
            "foo.bar { [weak self] ↓(x, y) in }",
            """
            [].first { ↓(temp) in
                [].first { ↓(temp) in
                    [].first { ↓(temp) in
                        _ = temp
                        return false
                    }
                    return false
                }
                return false
            }
            """,
            """
            [].first { temp in
                [].first { ↓(temp) in
                    [].first { ↓(temp) in
                        _ = temp
                        return false
                    }
                    return false
                }
                return false
            }
            """
        ],
        corrections: [
            "call(arg: { ↓(bar) in })\n": "call(arg: { bar in })\n",
            "call(arg: { ↓(bar, _) in })\n": "call(arg: { bar, _ in })\n",
            "let foo = { ↓(bar) -> Bool in return true }\n": "let foo = { bar -> Bool in return true }\n",
            "method { ↓(foo, bar) in }\n": "method { foo, bar in }\n",
            "foo.map { ($0, $0) }.forEach { ↓(x, y) in }": "foo.map { ($0, $0) }.forEach { x, y in }",
            "foo.bar { [weak self] ↓(x, y) in }": "foo.bar { [weak self] x, y in }"
        ]
    )

    public func validate(file: SwiftLintFile) -> [StyleViolation] {
        return violationRanges(file: file).map {
            StyleViolation(ruleDescription: type(of: self).description,
                           severity: configuration.severity,
                           location: Location(file: file, characterOffset: $0.location))
        }
    }

    private func violationRanges(file: SwiftLintFile) -> [NSRange] {
        let capturesPattern = "(?:\\[[^\\]]+\\])?"
        let pattern = "\\{\\s*\(capturesPattern)\\s*(\\([^:}]+?\\))\\s*(in|->)"
        let contents = file.stringView
        return regex(pattern).matches(in: file).compactMap { match -> NSRange? in
            let parametersRange = match.range(at: 1)
            let inRange = match.range(at: 2)
            guard let parametersByteRange = contents.NSRangeToByteRange(start: parametersRange.location,
                                                                        length: parametersRange.length),
                let inByteRange = contents.NSRangeToByteRange(start: inRange.location,
                                                              length: inRange.length) else {
                    return nil
            }

            let parametersTokens = file.syntaxMap.tokens(inByteRange: parametersByteRange)
            let parametersAreValid = parametersTokens.allSatisfy { token in
                if token.kind == .identifier {
                    return true
                }

                return token.kind == .keyword && file.contents(for: token) == "_"
            }

            let inKinds = Set(file.syntaxMap.kinds(inByteRange: inByteRange))
            guard parametersAreValid,
                inKinds.isEmpty || inKinds == [.keyword] else {
                    return nil
            }

            return parametersRange
        }
    }

    public func correct(file: SwiftLintFile) -> [Correction] {
        let violatingRanges = file.ruleEnabled(violatingRanges: violationRanges(file: file), for: self)
        var correctedContents = file.contents
        var adjustedLocations = [Int]()

        for violatingRange in violatingRanges.reversed() {
            let correctingRange = NSRange(location: violatingRange.location + 1,
                                          length: violatingRange.length - 2)
            if let indexRange = correctedContents.nsrangeToIndexRange(violatingRange),
                let updatedRange = correctedContents.nsrangeToIndexRange(correctingRange) {
                let updatedArguments = correctedContents[updatedRange]
                correctedContents = correctedContents.replacingCharacters(in: indexRange,
                                                                          with: String(updatedArguments))
                adjustedLocations.insert(violatingRange.location, at: 0)
            }
        }

        file.write(correctedContents)

        return adjustedLocations.map {
            Correction(ruleDescription: type(of: self).description,
                       location: Location(file: file, characterOffset: $0))
        }
    }
}
