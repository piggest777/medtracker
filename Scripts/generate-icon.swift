// Run from the repository root: swift Scripts/generate-icon.swift
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
                        bytesPerRow: 4096, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(red: 0.04, green: 0.42, blue: 0.40, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.08))
context.fillEllipse(in: CGRect(x: 125, y: 125, width: 774, height: 774))
context.translateBy(x: 512, y: 512)
context.rotate(by: .pi * 42 / 180)
context.setFillColor(CGColor(red: 0.92, green: 0.98, blue: 0.93, alpha: 1))
context.addPath(CGPath(roundedRect: CGRect(x: -280, y: -122, width: 560, height: 244),
                       cornerWidth: 122, cornerHeight: 122, transform: nil))
context.fillPath()
context.saveGState()
context.addPath(CGPath(roundedRect: CGRect(x: -260, y: -102, width: 520, height: 204),
                       cornerWidth: 102, cornerHeight: 102, transform: nil))
context.clip()
context.setFillColor(CGColor(red: 0.45, green: 0.81, blue: 0.68, alpha: 1))
context.fill(CGRect(x: -270, y: -110, width: 260, height: 220))
context.restoreGState()
context.setStrokeColor(CGColor(red: 0.04, green: 0.42, blue: 0.40, alpha: 0.6))
context.setLineWidth(12)
context.move(to: CGPoint(x: 0, y: -92))
context.addLine(to: CGPoint(x: 0, y: 92))
context.strokePath()
let url = URL(fileURLWithPath: "MedTracker/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
precondition(CGImageDestinationFinalize(destination))
