import SwiftUI
import AppKit

@MainActor struct CodeView: NSViewRepresentable {
    let text: String
    var syntax = false
    var highContrast = false
    @Environment(\.colorScheme) private var colorScheme
    func makeNSView(context: Context) -> NSScrollView {
        let scroll=NSScrollView()
        scroll.hasVerticalScroller=true; scroll.hasHorizontalScroller=true
        let view=NSTextView(frame: .zero)
        view.isEditable=false; view.isSelectable=true; view.isRichText=false
        view.usesFindBar=true; view.isAutomaticQuoteSubstitutionEnabled=false
        view.font=NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        view.textContainerInset=NSSize(width: 18, height: 16)
        view.isHorizontallyResizable=true; view.isVerticallyResizable=true
        view.autoresizingMask=[.width]
        view.textContainer?.widthTracksTextView=false
        view.textContainer?.containerSize=NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.minSize=NSSize(width: 0, height: 0)
        view.maxSize=NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.setAccessibilityLabel(syntax ? "Decompiled code" : "Binary details")
        scroll.documentView=view
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view=scroll.documentView as? NSTextView else { return }
        let foreground: NSColor=highContrast ? .white : .labelColor
        let background: NSColor=highContrast ? .black : .textBackgroundColor
        view.backgroundColor=background; scroll.backgroundColor=background
        let key="\(colorScheme)-\(highContrast)-\(syntax)"
        if view.string == text && view.identifier?.rawValue == key { return }
        view.identifier=NSUserInterfaceItemIdentifier(key)
        let rendered=NSMutableAttributedString(string: text, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), .foregroundColor: foreground])
        if syntax && !highContrast {
            let rules: [(String,NSColor)]=[
                (#"\b(if|else|return|while|for|switch|case|break|void|int|char|long|short|unsigned|struct|undefined[0-9]*|float|double|bool)\b"#, .systemPurple),
                (#"\b(0x[0-9a-fA-F]+|[0-9]+)\b"#, .systemBlue),
                (#"\"(?:\\.|[^\"\\])*\""#, .systemRed),
                (#"(?s)/\*.*?\*/|//[^\n]*"#, .secondaryLabelColor)
            ]
            let range=NSRange(text.startIndex..<text.endIndex, in: text)
            for (pattern,color) in rules {
                if let regex=try? NSRegularExpression(pattern: pattern) {
                    for match in regex.matches(in: text, range: range) { rendered.addAttribute(.foregroundColor, value: color, range: match.range) }
                }
            }
        }
        view.textStorage?.setAttributedString(rendered)
        view.scrollToBeginningOfDocument(nil)
    }
}
