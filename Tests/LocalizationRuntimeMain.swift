import Foundation

@main
struct LocalizationRuntimeTests {
    static func main() throws {
        let expected = CommandLine.arguments.last!
        let bundle = Bundle.main
        precondition(bundle.preferredLocalizations.first == expected, "Unexpected selected language: \(bundle.preferredLocalizations)")
        func table(_ language: String, _ name: String = "Localizable") throws -> [String: String] {
            let url = bundle.resourceURL!.appendingPathComponent("\(language).lproj/\(name).strings")
            return try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as! [String: String]
        }
        let english = try table("en"), chinese = try table("zh-Hans")
        precondition(Set(english.keys) == Set(chinese.keys))
        let pattern = try NSRegularExpression(pattern: #"%(?:\d+\$)?[-+ #0]*(?:\d+)?(?:\.\d+)?(?:hh|ll|[hlLzjt])?[@diuoxXfFeEgGaAcCsSp%]"#)
        func formats(_ text: String) -> [String] {
            let value = text.replacingOccurrences(of: "%title%", with: "")
            return pattern.matches(in: value, range: NSRange(value.startIndex..., in: value)).map { String(value[Range($0.range, in: value)!]) }.sorted()
        }
        let han = try NSRegularExpression(pattern: #"\p{Han}"#)
        let selected = expected == "en" ? english : chinese
        for key in english.keys {
            precondition(!english[key]!.isEmpty && !chinese[key]!.isEmpty, "Empty: \(key)")
            precondition(formats(key) == formats(english[key]!) && formats(key) == formats(chinese[key]!), "Format mismatch: \(key)")
            precondition(han.firstMatch(in: english[key]!, range: NSRange(english[key]!.startIndex..., in: english[key]!)) == nil, "Chinese in English translation: \(key)")
            precondition(L(key) == selected[key], "Bundle lookup failed: \(key)")
        }
        precondition(english["开始 / 停止录屏"] == "Start / Stop Recording", "Missing persisted shortcut label")
        precondition(LF("延迟 %ld 秒", 3) == (expected == "en" ? "Delay: 3 s" : "延迟 3 秒"))
        precondition(LF("步骤 %ld", 3) == (expected == "en" ? "Step 3" : "步骤 3"))
        for (key, value) in try table(expected, "InfoPlist") {
            precondition(bundle.localizedInfoDictionary?[key] as? String == value, "Permission string: \(key)")
        }
        print("PASS: \(english.count) localized strings, format substitutions and permission messages; selected \(expected)")
    }
}
