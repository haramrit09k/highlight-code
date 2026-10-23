// Invokes the installed "Highlight Code" service the same way the Services menu does,
// then checks that highlighted RTF came back. Used by scripts/smoke-test.sh.
//
// Usage: swift scripts/perform-service.swift
import AppKit

let code = "```python\ndef greet(name):\n    return f\"Hello, {name}!\"  # comment\n```"
let pasteboard = NSPasteboard(name: NSPasteboard.Name("HighlightCodeSmokeTest-\(UUID().uuidString)"))
pasteboard.declareTypes([.string], owner: nil)
pasteboard.setString(code, forType: .string)

guard NSPerformService("Highlight Code", pasteboard) else {
    print("FAIL: NSPerformService returned false (service not registered?)")
    exit(1)
}
guard let rtf = pasteboard.data(forType: .rtf),
      let attributed = NSAttributedString(rtf: rtf, documentAttributes: nil) else {
    print("FAIL: the service returned no RTF. Types: \(pasteboard.types ?? [])")
    exit(1)
}

var colouredRuns = 0
attributed.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
    if value != nil { colouredRuns += 1 }
}
let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
print("Service returned: \(attributed.string.debugDescription)")
print("Coloured runs: \(colouredRuns), font: \(font?.fontName ?? "none")")

guard attributed.string.hasPrefix("def greet"), colouredRuns >= 3, font?.isFixedPitch == true else {
    print("FAIL: unexpected output")
    exit(1)
}
print("PASS")
