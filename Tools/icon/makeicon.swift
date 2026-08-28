import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Draws the app icon and writes an .iconset.
///
/// The mark is the widget's own idea reduced to two arcs: a thick outer gauge
/// for the session and a shorter inner one for the week. Pure CoreGraphics so
/// the icon has a source of truth that can be edited, rather than a checked-in
/// binary nobody can change.
enum Icon {

    // Clay ground, near-white arcs. High contrast so it survives 16pt.
    static let background = CGColor(red: 0.76, green: 0.36, blue: 0.23, alpha: 1)
    static let sessionArc = CGColor(red: 1, green: 0.98, blue: 0.96, alpha: 1)
    static let weekArc = CGColor(red: 1, green: 0.98, blue: 0.96, alpha: 0.62)

    static func draw(size: CGFloat, into ctx: CGContext) {
        ctx.setAllowsAntialiasing(true)
        ctx.interpolationQuality = .high

        // macOS icons sit inset inside their canvas, with the Big Sur squircle
        // radius of ~22.4% of the shape's width.
        let inset = size * 0.055
        let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
        let radius = rect.width * 0.2237

        ctx.beginPath()
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.setFillColor(background)
        ctx.fillPath()

        let center = CGPoint(x: rect.midX, y: rect.midY)

        // Session: 70% of the way round, starting at twelve o'clock.
        arc(
            ctx,
            center: center,
            radius: rect.width * 0.295,
            width: rect.width * 0.115,
            sweep: 0.70,
            color: sessionArc
        )

        // Week: a shorter inner sweep, so the two read as one family.
        arc(
            ctx,
            center: center,
            radius: rect.width * 0.155,
            width: rect.width * 0.082,
            sweep: 0.30,
            color: weekArc
        )
    }

    /// `sweep` is a fraction of the full circle, drawn clockwise from the top.
    private static func arc(
        _ ctx: CGContext,
        center: CGPoint,
        radius: CGFloat,
        width: CGFloat,
        sweep: CGFloat,
        color: CGColor
    ) {
        let start = CGFloat.pi / 2
        let end = start - sweep * 2 * .pi

        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.beginPath()
        ctx.addArc(
            center: center,
            radius: radius,
            startAngle: start,
            endAngle: end,
            clockwise: true
        )
        ctx.strokePath()
    }

    static func render(size: Int) -> CGImage? {
        guard let ctx = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        draw(size: CGFloat(size), into: ctx)
        return ctx.makeImage()
    }

    static func write(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else {
            throw NSError(domain: "icon", code: 1)
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "icon", code: 2) }
    }
}

@main
struct Main {
    /// The sizes `iconutil` expects in an .iconset.
    static let variants: [(name: String, pixels: Int)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32),
        ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256),
        ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024),
    ]

    static func main() throws {
        let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        for variant in variants {
            guard let image = Icon.render(size: variant.pixels) else {
                FileHandle.standardError.write("could not render \(variant.name)\n".data(using: .utf8)!)
                exit(1)
            }
            try Icon.write(image, to: out.appendingPathComponent("\(variant.name).png"))
        }
        print("wrote \(variants.count) images to \(out.path)")
    }
}
