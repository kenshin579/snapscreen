import AppKit

public enum PNGEncoder {
    public static func encode(_ image: CGImage, scale: CGFloat) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: CGFloat(image.width) / scale,
                          height: CGFloat(image.height) / scale)
        return rep.representation(using: .png, properties: [:])
    }
}
