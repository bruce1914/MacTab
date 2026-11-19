import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let factor = CGFloat(pixels) / 1024
        let transform = NSAffineTransform()
        transform.scale(by: factor)
        transform.concat()
        let background = NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 210, yRadius: 210)
        NSGradient(starting: NSColor(calibratedRed: 0.48, green: 0.83, blue: 1, alpha: 1),
                   ending: NSColor(calibratedRed: 0.12, green: 0.40, blue: 0.72, alpha: 1))!.draw(in: background, angle: -70)
        let back = NSBezierPath(roundedRect: NSRect(x: 180, y: 390, width: 510, height: 390), xRadius: 45, yRadius: 45)
        NSColor.white.withAlphaComponent(0.6).setFill()
        back.fill()
        let front = NSBezierPath(roundedRect: NSRect(x: 330, y: 245, width: 520, height: 395), xRadius: 45, yRadius: 45)
        NSColor(calibratedRed: 0.95, green: 0.98, blue: 1, alpha: 1).setFill()
        front.fill()
        NSColor(calibratedRed: 0.14, green: 0.42, blue: 0.63, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 370, y: 535, width: 440, height: 58), xRadius: 12, yRadius: 12).fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
