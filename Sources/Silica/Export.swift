import AppKit

/// Two exports, both from the same plain text: the file itself, or a printed
/// page of it. Anything richer would mean the app stopped being a text editor.
enum Export {
    static func markdown(_ note: Note?) {
        guard let note else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(note.title).md"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? note.text.write(to: url, atomically: true, encoding: .utf8)
    }

    static func pdf(_ note: Note?, fontSize: Double) {
        guard let note else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(note.title).pdf"
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        // US Letter with one-inch margins, laid out by the printing system so long
        // notes paginate instead of being squashed onto a single tall page.
        let pageWidth: CGFloat = 612, pageHeight: CGFloat = 792, margin: CGFloat = 72
        let textView = NSTextView(frame: NSRect(
            x: 0, y: 0,
            width: pageWidth - margin * 2,
            height: pageHeight - margin * 2
        ))
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.45
        paragraph.paragraphSpacing = fontSize
        textView.textStorage?.setAttributedString(NSAttributedString(
            string: note.text,
            attributes: [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: NSColor.black,
                .paragraphStyle: paragraph
            ]
        ))
        textView.sizeToFit()

        let info = NSPrintInfo()
        info.paperSize = NSSize(width: pageWidth, height: pageHeight)
        info.topMargin = margin
        info.bottomMargin = margin
        info.leftMargin = margin
        info.rightMargin = margin
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

        let operation = NSPrintOperation(view: textView, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.run()
    }
}
