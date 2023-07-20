import Foundation

private let propertyPrefixRegexp = try! NSRegularExpression(pattern: "@property\\s*(\\([^)]+\\))?", options: [])
private let propertySuffixRegexp = try! NSRegularExpression(pattern: "\\s[A-Z_]+_[A-Z_]+\\b", options: [])
private let blockPropertyRegexp = try! NSRegularExpression(pattern: "\\([*^](\\w+)\\)", options: [])
private let pointerPropertRegexp = try! NSRegularExpression(pattern: "((\\*?\\s*\\w+,\\s*)*\\*?\\s*\\w+)\\s*$", options: [])

let spacesAndAsterisks = CharacterSet.whitespacesAndNewlines
    .union(CharacterSet(charactersIn: "*"))

extension String {
    var objCPropertyNames: [String] {
        /** 遍历头文件内容*/
        let headerWithoutComments = withoutComments
//        print("__> Without Comments: \(withoutComments)")
        let allLines = headerWithoutComments.components(separatedBy: ";")
//        print("__> All Lines: \(allLines)")
        let propertyLines = allLines.filter { $0.contains("@property") }
//        print("__> Property Lines: \(propertyLines)")
        
        return propertyLines.flatMap { $0.objCPropertyNameFromPropertyLine }
    }

    private var objCPropertyNameFromPropertyLine: [String] { /** 正则匹配属性名称*/
        let propertyBodyRange = objCPropertyBodyRangeFromPropertyLine
        let matcherConfigurations: [(regexp: NSRegularExpression, group: Int)] = [
            (regexp: blockPropertyRegexp, group: 1),
            (regexp: pointerPropertRegexp, group: 1),
        ]
        
        let matchedNames: [String] = matcherConfigurations.flatMap { c in
            return c.regexp.matches(in: self, options: [], range: propertyBodyRange)
                .map { (match: NSTextCheckingResult) -> String in
                    return self[match.range(at: c.group)]
                }
        }
        
//        print("__> Matched Name: \(matchedNames)")
        
        if matchedNames.isEmpty {
            let propertyCode: String = (self as NSString).substring(with: propertyBodyRange)
            fatalError("Couldn't resolve property name for line: '\(self)', propertyCode: \(propertyCode), matcherConfigurations: \(matcherConfigurations)")
        }
        if matchedNames.count > 1 {
            fatalError("Property name resolved ambiguously for line: '\(self)'. Matched names: \(matchedNames)")
        }
        let matchedName = matchedNames[0].trimmingCharacters(in: spacesAndAsterisks)
        if matchedName.contains(",") {
            return matchedName
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: spacesAndAsterisks) }
        }
        return [matchedName]
    }

    private var objCPropertyBodyRangeFromPropertyLine: NSRange {
        let propertyBodyLowerBoundSearchRange = NSRange(location: 0, length: self.count)
        let propertyBodyLowerBound =
            propertyPrefixRegexp.firstMatch(in: self,
                                            options: [],
                                            range: propertyBodyLowerBoundSearchRange)!
            .range.upperBound
        let propertyBodyUpperBoundSearchRange =
            NSRange(location: propertyBodyLowerBound, length: count - propertyBodyLowerBound)
        let propertyBodyUpperBound =
            propertySuffixRegexp.firstMatch(in: self,
                                            options: [],
                                            range: propertyBodyUpperBoundSearchRange)?
            .range.lowerBound
            ?? count
        return NSRange(location: propertyBodyLowerBound,
                       length: propertyBodyUpperBound - propertyBodyLowerBound)
    }
}
