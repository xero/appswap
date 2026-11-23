// Draws the placeholder app icon, a 1024 px PNG, with CoreGraphics alone.
// usage: icon <out.png>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 2 else {
	FileHandle.standardError.write(Data("usage: icon <out.png>\n".utf8))
	exit(64)
}
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func fill(_ rect: CGRect, radius: CGFloat, gray: Int) {
	let v = CGFloat(gray) / 255
	ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
	ctx.setFillColor(CGColor(colorSpace: space, components: [v, v, v, 1])!)
	ctx.fillPath()
}

// The switcher in miniature: a #222 plate inset the way macOS icons are, and three cells with the middle one selected.
fill(CGRect(x: 100, y: 100, width: 824, height: 824), radius: 185, gray: 0x22)
for i in 0..<3 {
	let cell = CGRect(x: 212 + CGFloat(i) * 200, y: 412, width: 200, height: 200)
	if i == 1 { fill(cell, radius: 24, gray: 0x66) }
	fill(cell.insetBy(dx: 36, dy: 36), radius: 28, gray: 0xe0)
}

guard let image = ctx.makeImage(),
	let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, UTType.png.identifier as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(dest, image, nil)
exit(CGImageDestinationFinalize(dest) ? 0 : 1)
