import AppKit

public enum ClipboardWriter {
    @discardableResult
    public static func write(_ image: CGImage, scale: CGFloat) -> Bool {
        guard let data = PNGEncoder.encode(image, scale: scale) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setData(data, forType: .png)
    }
}
