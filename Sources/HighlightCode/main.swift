#if canImport(AppKit)
import AppKit
import HighlightCore

let arguments = CommandLine.arguments

// Command-line mode, e.g. `HighlightCode --rtf < main.py | pbcopy`.
if arguments.contains("--rtf") {
    let input = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
    do {
        let formatter = SnippetFormatter(highlighter: try CodeHighlighter(bundle: .main))
        var snippet = input
        if let index = arguments.firstIndex(of: "--language"), arguments.indices.contains(index + 1) {
            snippet = "```\(arguments[index + 1])\n\(input)\n```"
        }
        let output = formatter.format(snippet, options: Preferences.shared.renderOptions)
        FileHandle.standardError.write(Data("language: \(output.language ?? "unknown")\n".utf8))
        FileHandle.standardOutput.write(CodeRenderer.rtfData(for: output.attributed) ?? Data())
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("\(error)\n".utf8))
        exit(1)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate(arguments: arguments)
app.delegate = delegate
app.run()
#else
print("Highlight Code is a macOS app; only HighlightCore builds on this platform.")
#endif
