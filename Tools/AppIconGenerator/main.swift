import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: AppIconGenerator <output.icns>\n".utf8))
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

let chunks: [(type: String, pixels: Int)] = [
    ("icp4", 16),
    ("icp5", 32),
    ("ic11", 32),
    ("icp6", 64),
    ("ic12", 64),
    ("ic07", 128),
    ("ic08", 256),
    ("ic13", 256),
    ("ic09", 512),
    ("ic14", 512),
    ("ic10", 1_024),
]

var body = Data()
var rendered: [Int: Data] = [:]
for chunk in chunks {
    let png = try rendered[chunk.pixels] ?? renderIcon(pixels: chunk.pixels)
    rendered[chunk.pixels] = png
    body.append(Data(chunk.type.utf8))
    body.append(bigEndian: UInt32(png.count + 8))
    body.append(png)
}
var icon = Data("icns".utf8)
icon.append(bigEndian: UInt32(body.count + 8))
icon.append(body)
try icon.write(to: outputURL, options: .atomic)

func renderIcon(pixels: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw IconError.couldNotCreateBitmap
    }

    bitmap.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }

    let size = CGFloat(pixels)
    context.cgContext.clear(CGRect(x: 0, y: 0, width: size, height: size))

    let inset = size * 0.055
    let tileRect = CGRect(
        x: inset,
        y: inset + size * 0.012,
        width: size - inset * 2,
        height: size - inset * 2
    )
    let tilePath = NSBezierPath(
        roundedRect: tileRect,
        xRadius: size * 0.205,
        yRadius: size * 0.205
    )

    if pixels >= 64 {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowBlurRadius = size * 0.055
        shadow.shadowOffset = NSSize(width: 0, height: -size * 0.025)
        shadow.set()
    }

    let gradient = NSGradient(colors: [
        NSColor(red: 0.99, green: 0.31, blue: 0.08, alpha: 1),
        NSColor(red: 1.00, green: 0.61, blue: 0.12, alpha: 1),
    ])
    gradient?.draw(in: tilePath, angle: -22)

    NSGraphicsContext.current?.cgContext.setShadow(offset: .zero, blur: 0)
    NSColor.white.withAlphaComponent(0.18).setStroke()
    tilePath.lineWidth = max(1, size * 0.007)
    tilePath.stroke()

    let symbolConfiguration = NSImage.SymbolConfiguration(
        pointSize: size * 0.43,
        weight: .semibold
    ).applying(NSImage.SymbolConfiguration(hierarchicalColor: .white))
    guard let symbol = NSImage(
        systemSymbolName: "externaldrive.fill",
        accessibilityDescription: "Kick"
    )?.withSymbolConfiguration(symbolConfiguration) else {
        throw IconError.missingSystemSymbol
    }

    let symbolSize = NSSize(width: size * 0.50, height: size * 0.50)
    let symbolRect = CGRect(
        x: (size - symbolSize.width) / 2,
        y: (size - symbolSize.height) / 2 + size * 0.018,
        width: symbolSize.width,
        height: symbolSize.height
    )
    symbol.draw(
        in: symbolRect,
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: false,
        hints: nil
    )

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw IconError.couldNotEncodePNG
    }
    return data
}

enum IconError: Error {
    case couldNotCreateBitmap
    case couldNotEncodePNG
    case missingSystemSymbol
}

private extension Data {
    mutating func append(bigEndian value: UInt32) {
        var encoded = value.bigEndian
        Swift.withUnsafeBytes(of: &encoded) { append(contentsOf: $0) }
    }
}
