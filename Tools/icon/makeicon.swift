import AppKit
import CoreGraphics
import CoreText
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

        mark(ctx, center: CGPoint(x: rect.midX, y: rect.midY), scale: rect.width)
    }

    /// The two arcs alone, sized to `scale` — the width of the shape they sit in.
    /// Shared with the social card so both come from one description of the mark.
    static func mark(_ ctx: CGContext, center: CGPoint, scale: CGFloat) {
        // Session: 70% of the way round, starting at twelve o'clock.
        arc(
            ctx,
            center: center,
            radius: scale * 0.295,
            width: scale * 0.115,
            sweep: 0.70,
            color: sessionArc
        )

        // Week: a shorter inner sweep, so the two read as one family.
        arc(
            ctx,
            center: center,
            radius: scale * 0.155,
            width: scale * 0.082,
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

/// Draws the repository's social preview card.
///
/// GitHub wants at least 640x320 and renders best at 1280x640, and it crops the
/// card to other ratios in some places, so everything sits well inside the edges.
enum Social {

    static let width = 1280
    static let height = 640

    static func render() -> CGImage? {
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.setAllowsAntialiasing(true)
        ctx.setFillColor(Icon.background)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let title = line("Claude Usage", size: 92, weight: .semibold, color: Icon.sessionArc)
        let subtitle = line(
            "Session and week limits, in the menu bar",
            size: 38,
            weight: .regular,
            color: Icon.weekArc
        )

        // Centre the mark and the text as one group, measuring the type rather
        // than positioning it by hand, so editing the wording keeps the margins.
        let markScale: CGFloat = 400
        let markRadius = markScale * (0.295 + 0.115 / 2)  // outer arc plus half its stroke
        let gap: CGFloat = 76
        let text = max(width(of: title), width(of: subtitle))
        let left = (CGFloat(width) - (markRadius * 2 + gap + text)) / 2

        let middle = CGFloat(height) / 2

        // The mark full-bleed on the clay rather than the icon's rounded square:
        // the card is already a rectangle, and a tile inside it reads as a mistake.
        Icon.mark(ctx, center: CGPoint(x: left + markRadius, y: middle), scale: markScale)

        // Baselines chosen so the two lines straddle the mark's centre.
        let textLeft = left + markRadius * 2 + gap
        draw(title, at: CGPoint(x: textLeft, y: middle + 9), in: ctx)
        draw(subtitle, at: CGPoint(x: textLeft, y: middle - 67), in: ctx)

        return ctx.makeImage()
    }

    /// The system font by weight, so no PostScript name has to be guessed.
    private static func line(
        _ text: String,
        size: CGFloat,
        weight: NSFont.Weight,
        color: CGColor
    ) -> CTLine {
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String):
                    NSFont.systemFont(ofSize: size, weight: weight),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            ]
        )
        return CTLineCreateWithAttributedString(attributed)
    }

    private static func width(of line: CTLine) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    private static func draw(_ line: CTLine, at origin: CGPoint, in ctx: CGContext) {
        ctx.textPosition = origin
        CTLineDraw(line, ctx)
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
        let args = CommandLine.arguments.dropFirst()
        let out = URL(fileURLWithPath: args.first ?? "AppIcon.iconset")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        for variant in variants {
            guard let image = Icon.render(size: variant.pixels) else {
                FileHandle.standardError.write("could not render \(variant.name)\n".data(using: .utf8)!)
                exit(1)
            }
            try Icon.write(image, to: out.appendingPathComponent("\(variant.name).png"))
        }
        print("wrote \(variants.count) images to \(out.path)")

        // Second argument, if given, is where the social preview card goes.
        guard let path = args.dropFirst().first else { return }
        guard let card = Social.render() else {
            FileHandle.standardError.write("could not render the social card\n".data(using: .utf8)!)
            exit(1)
        }
        let cardURL = URL(fileURLWithPath: path)
        try Icon.write(card, to: cardURL)
        print("wrote \(Social.width)x\(Social.height) card to \(cardURL.path)")
    }
}
