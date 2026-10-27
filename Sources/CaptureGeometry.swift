import AppKit

struct CaptureConstraint: Codable, Equatable {
    var mode = "free"
    var ratio = "16:9"
    var portrait = false
    var pixelWidth = 1000
    var pixelHeight = 700

    func rect(from start: CGPoint, to end: CGPoint, within bounds: CGRect, scale: CGFloat) -> CGRect {
        if mode == "full" { return bounds }
        if mode == "pixels" {
            let size = CGSize(width:min(bounds.width,CGFloat(max(1,pixelWidth))/scale),height:min(bounds.height,CGFloat(max(1,pixelHeight))/scale))
            return CGRect(x:max(bounds.minX,min(start.x,bounds.maxX-size.width)),y:max(bounds.minY,min(start.y,bounds.maxY-size.height)),width:size.width,height:size.height)
        }
        guard mode == "ratio" else { return CaptureGeometry.normalized(start,end,within:bounds) }
        let parts = ratio.split(separator:":").compactMap { Double($0) }
        guard parts.count == 2,parts[1] > 0 else { return CaptureGeometry.normalized(start,end,within:bounds) }
        let aspect = CGFloat(portrait ? parts[1]/parts[0] : parts[0]/parts[1])
        let right = end.x >= start.x,up = end.y >= start.y
        let availableWidth = right ? bounds.maxX-start.x : start.x-bounds.minX
        let availableHeight = up ? bounds.maxY-start.y : start.y-bounds.minY
        let width = min(max(abs(end.x-start.x),abs(end.y-start.y)*aspect),availableWidth,availableHeight*aspect)
        let height = width/aspect
        return CGRect(x:right ? start.x : start.x-width,y:up ? start.y : start.y-height,width:width,height:height)
    }
}

enum CaptureGeometry {
    static func normalized(_ start: CGPoint, _ end: CGPoint, within bounds: CGRect) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y)).intersection(bounds)
    }

    // AppKit's origin is lower-left; ScreenCaptureKit uses display-local upper-left.
    static func sourceRect(selection: CGRect, screen: CGRect) -> CGRect {
        CGRect(x: selection.minX - screen.minX, y: screen.maxY - selection.maxY,
               width: selection.width, height: selection.height)
    }

    static func cocoaRect(_ quartz: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: quartz.minX, y: primaryHeight - quartz.maxY, width: quartz.width, height: quartz.height)
    }
}
