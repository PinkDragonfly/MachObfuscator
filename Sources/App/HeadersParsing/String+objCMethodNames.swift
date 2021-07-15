import Foundation

/// Remove __unsafe_unretained, _Nullable, _Nonnull and their variations and arrays, eg. [_Nonnull]
private let removedParameterAttributes = try! NSRegularExpression(pattern: "\\b(__unsafe_unretained)|(\\[?__?[nN]ullable\\]?)|(\\[?__?[nN]onnull\\]?)\\b")
private let methodStartRegexp = try! NSRegularExpression(pattern: "^\\s*[-+]\\s*\\([^\\(\\)]*(\\([^\\(\\)]+\\)[^\\(\\)]*)*[^\\(\\)]*\\)", options: [.anchorsMatchLines])
private let methodSuffixRegexp = try! NSRegularExpression(pattern: "\\s([A-Z_]+_[A-Z_]+\\b)|(__[a-z_]+\\b)", options: [])
private let namedParameterRegexp = try! NSRegularExpression(pattern: "\\b(\\w+:)", options: [])
private let parameterlessMethodNameRegexp = try! NSRegularExpression(pattern: "\\b(\\w+)\\b", options: [])

private let methodNameDelimiters = CharacterSet([";", "{", "}"])

extension String {
    var objCMethodNames: [String] {
        let headerWithoutComments = withoutComments
        let allLines = headerWithoutComments.components(separatedBy: methodNameDelimiters)
            .map { $0.withoutOccurences(of: removedParameterAttributes) }
        return allLines.compactMap { $0.objCMethodNameFromLine }
    }

    private var objCMethodNameRange: NSRange? {
        guard let methodStartMatch = methodStartRegexp.firstMatch(in: self) else {
            return nil
        }
        let methodNameLowerBound = methodStartMatch.range.upperBound
        let methodNameUpperBoundSearchRange =
            NSRange(location: methodNameLowerBound, length: count - methodNameLowerBound)
        let methodNameUpperBound =
            methodSuffixRegexp.firstMatch(in: self,
                                          options: [],
                                          range: methodNameUpperBoundSearchRange)?
            .range.lowerBound
            ?? count
        return NSRange(location: methodNameLowerBound,
                       length: methodNameUpperBound - methodNameLowerBound)
    }

    private var objCMethodNameFromLine: String? {
        guard let methodNameRange = objCMethodNameRange else {
            return nil
        }
        let namedParameterMatches = namedParameterRegexp.matches(in: self, options: [], range: methodNameRange)
        if !namedParameterMatches.isEmpty {
            return namedParameterMatches
                .map { self[$0.range(at: 1)] }
                .joined()
        }

        return parameterlessMethodNameRegexp
            .firstMatch(in: self, options: [], range: methodNameRange)
            .flatMap { self[$0.range(at: 1)] }
    }
}
