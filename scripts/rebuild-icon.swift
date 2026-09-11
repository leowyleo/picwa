import CoreGraphics
import Foundation
import ImageIO

guard CommandLine.arguments.count == 3 else {
    fputs("usage: rebuild-icon.swift input.png output.png\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fputs("could not read source image\n", stderr)
    exit(1)
}

// The reference artwork is a 1254px square export with a white surround.
// These bounds are the visible pale-blue icon panel; everything outside it
// becomes transparent while the artwork inside remains pixel-derived.
let panel = CGRect(x: 131, y: 119, width: 992, height: 996).integral
guard let cropped = image.cropping(to: panel) else {
    fputs("could not crop source image\n", stderr)
    exit(1)
}

let size = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("could not create bitmap context\n", stderr)
    exit(1)
}

context.clear(CGRect(x: 0, y: 0, width: size, height: size))
context.saveGState()
let iconBounds = CGRect(x: 0, y: 0, width: size, height: size)
context.addPath(CGPath(roundedRect: iconBounds, cornerWidth: 226, cornerHeight: 226, transform: nil))
context.clip()
context.interpolationQuality = .high
context.draw(cropped, in: iconBounds)
context.restoreGState()

guard let output = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, "public.png" as CFString, 1, nil) else {
    fputs("could not write output image\n", stderr)
    exit(1)
}
CGImageDestinationAddImage(destination, output, [kCGImagePropertyPNGInterlaceType: 0] as CFDictionary)
guard CGImageDestinationFinalize(destination) else {
    fputs("could not finalize output image\n", stderr)
    exit(1)
}
