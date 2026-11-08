import AppKit
let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
func draw(size: Int, name: String) throws {
 let ctx = CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
 NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current = NSGraphicsContext(cgContext:ctx,flipped:false)
 ctx.scaleBy(x:CGFloat(size)/1024,y:CGFloat(size)/1024)
 let rect = NSRect(x:0,y:0,width:1024,height:1024)
 NSGradient(starting: NSColor(calibratedRed:0.02,green:0.30,blue:0.39,alpha:1), ending:NSColor(calibratedRed:0.06,green:0.66,blue:0.62,alpha:1))!.draw(in: rect, angle:45)
 // Folded map and route, drawn as vectors at every target size.
 let map = NSBezierPath();map.move(to:NSPoint(x:140,y:235));map.line(to:NSPoint(x:355,y:300));map.line(to:NSPoint(x:660,y:230));map.line(to:NSPoint(x:884,y:300));map.line(to:NSPoint(x:884,y:685));map.line(to:NSPoint(x:660,y:615));map.line(to:NSPoint(x:355,y:685));map.line(to:NSPoint(x:140,y:620));map.close()
 NSColor.white.withAlphaComponent(0.92).setFill();map.fill()
 let fold = NSBezierPath();fold.move(to:NSPoint(x:355,y:300));fold.line(to:NSPoint(x:355,y:685));fold.move(to:NSPoint(x:660,y:230));fold.line(to:NSPoint(x:660,y:615));fold.lineWidth=12;NSColor(calibratedRed:0.04,green:0.5,blue:0.53,alpha:0.25).setStroke();fold.stroke()
 let route = NSBezierPath();route.move(to:NSPoint(x:230,y:370));route.curve(to:NSPoint(x:710,y:425),controlPoint1:NSPoint(x:340,y:520),controlPoint2:NSPoint(x:560,y:270));route.lineWidth=25;route.lineCapStyle = .round;NSColor(calibratedRed:0.03,green:0.52,blue:0.55,alpha:0.65).setStroke();route.stroke()
 let pin = NSBezierPath();pin.move(to:NSPoint(x:512,y:362));pin.curve(to:NSPoint(x:314,y:698),controlPoint1:NSPoint(x:465,y:435),controlPoint2:NSPoint(x:314,y:563));pin.curve(to:NSPoint(x:710,y:698),controlPoint1:NSPoint(x:314,y:962),controlPoint2:NSPoint(x:710,y:962));pin.curve(to:NSPoint(x:512,y:362),controlPoint1:NSPoint(x:710,y:563),controlPoint2:NSPoint(x:559,y:435));pin.close();NSColor(calibratedRed:1,green:0.72,blue:0.23,alpha:1).setFill();pin.fill()
 NSColor.white.setFill();NSBezierPath(ovalIn:NSRect(x:432,y:642,width:160,height:160)).fill()
 NSGraphicsContext.restoreGraphicsState()
 let image=NSBitmapImageRep(cgImage:ctx.makeImage()!)
 try image.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name))
}
var entries:[[String:String]]=[]
for (points,scale) in [(20,2),(20,3),(29,2),(29,3),(40,2),(40,3),(60,2),(60,3)] {
 let name="icon-\(points)@\(scale)x.png";try draw(size:points*scale,name:name);entries.append(["idiom":"iphone","size":"\(points)x\(points)","scale":"\(scale)x","filename":name])
}
try draw(size:1024,name:"icon-1024.png");entries.append(["idiom":"ios-marketing","size":"1024x1024","scale":"1x","filename":"icon-1024.png"])
let json:[String:Any] = ["images":entries,"info":["version":1,"author":"xcode"]]
try JSONSerialization.data(withJSONObject:json,options:.prettyPrinted).write(to:output.appendingPathComponent("Contents.json"))
