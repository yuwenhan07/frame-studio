import AppKit

let output = CommandLine.arguments[1]
let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let base = NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 192, yRadius: 192)
let gradient = NSGradient(colors: [NSColor(srgbRed: 0.9, green: 0.66, blue: 0.53, alpha: 1), NSColor(srgbRed: 0.48, green: 0.31, blue: 0.29, alpha: 1)])!
gradient.draw(in: base, angle: -60)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
NSColor(srgbRed: 0.97, green: 0.94, blue: 0.87, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 202, y: 290, width: 620, height: 478), xRadius: 40, yRadius: 40).fill()
NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.saveGraphicsState()
let photo = NSBezierPath(roundedRect: NSRect(x: 224, y: 312, width: 576, height: 434), xRadius: 23, yRadius: 23)
photo.addClip()
NSGradient(colors: [NSColor(srgbRed: 0.93, green: 0.76, blue: 0.64, alpha: 1), NSColor(srgbRed: 0.53, green: 0.61, blue: 0.53, alpha: 1)])!.draw(in: photo, angle: -90)
NSColor(srgbRed: 0.99, green: 0.88, blue: 0.65, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 570, y: 566, width: 90, height: 90)).fill()
let hill = NSBezierPath()
hill.move(to: NSPoint(x: 200, y: 310))
hill.line(to: NSPoint(x: 200, y: 420))
hill.curve(to: NSPoint(x: 830, y: 370), controlPoint1: NSPoint(x: 430, y: 660), controlPoint2: NSPoint(x: 600, y: 340))
hill.line(to: NSPoint(x: 830, y: 290)); hill.close()
NSColor(srgbRed: 0.32, green: 0.43, blue: 0.36, alpha: 1).setFill(); hill.fill()
NSGraphicsContext.restoreGraphicsState()
NSColor.white.withAlphaComponent(0.92).setFill()
NSBezierPath(roundedRect: NSRect(x: 354, y: 212, width: 128, height: 15), xRadius: 7, yRadius: 7).fill()
NSBezierPath(roundedRect: NSRect(x: 502, y: 215, width: 168, height: 9), xRadius: 4, yRadius: 4).fill()
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
