import AppKit

public enum ClipboardWriter {
    @discardableResult
    public static func write(_ image: CGImage, scale: CGFloat) -> Bool {
        guard let data = PNGEncoder.encode(image, scale: scale) else { return false }
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: CGFloat(image.width) / scale,
                          height: CGFloat(image.height) / scale)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let pngOK = pasteboard.setData(data, forType: .png)
        if let tiff = rep.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
        return pngOK
    }

    public static func write(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
