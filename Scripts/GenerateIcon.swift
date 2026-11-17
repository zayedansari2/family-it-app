import AppKit
import Foundation

// Reproducible native placeholder artwork; no downloaded assets.
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let frame = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor(calibratedRed: 0.10, green: 0.28, blue: 0.26, alpha: 1).setFill()
    NSBezierPath(roundedRect: frame.insetBy(dx: Double(size) * 0.04, dy: Double(size) * 0.04),
                 xRadius: Double(size) * 0.18, yRadius: Double(size) * 0.18).fill()
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: Double(size) * 0.47, weight: .semibold),
        .foregroundColor: NSColor(calibratedWhite: 0.97, alpha: 1)
    ]
    let text = "IT" as NSString
    let bounds = text.size(withAttributes: attributes)
    text.draw(at: NSPoint(x: (Double(size) - bounds.width) / 2,
                         y: (Double(size) - bounds.height) / 2), withAttributes: attributes)
    image.unlockFocus()
    let representation = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try representation.representation(using: .png, properties: [:])!.write(
        to: directory.appendingPathComponent("Icon\(size).png"))
}
