import AppKit

@main struct GeometryRuntimeMain {
    static func main() {
        let main = CGRect(x:0,y:0,width:1512,height:982)
        let below = CGRect(x:0,y:-1080,width:1920,height:1080)
        let left = CGRect(x:-1920,y:80,width:1920,height:1080)
        let selection = CGRect(x:50,y:100,width:200,height:300)
        precondition(CaptureGeometry.sourceRect(selection:selection,screen:main) == CGRect(x:50,y:582,width:200,height:300))
        precondition(CaptureGeometry.sourceRect(selection:selection.offsetBy(dx:0,dy:-1080),screen:below) == CGRect(x:50,y:680,width:200,height:300))
        precondition(CaptureGeometry.sourceRect(selection:selection.offsetBy(dx:-1920,dy:80),screen:left) == CGRect(x:50,y:680,width:200,height:300))
        precondition(CaptureGeometry.cocoaRect(CGRect(x:-1900,y:-100,width:300,height:400),primaryHeight:982) == CGRect(x:-1900,y:682,width:300,height:400))
        precondition(CaptureGeometry.normalized(CGPoint(x:200,y:200),CGPoint(x:-50,y:40),within:main) == CGRect(x:0,y:40,width:200,height:160))
        var constraint = CaptureConstraint();constraint.mode = "ratio"
        for end in [CGPoint(x:2000,y:500),CGPoint(x:0,y:0),CGPoint(x:900,y:1800)] {
            let rect = constraint.rect(from:CGPoint(x:500,y:500),to:end,within:main,scale:2)
            precondition(abs(rect.width/rect.height-16/9.0)<0.0001 && main.contains(rect))
        }
        constraint.mode = "pixels";constraint.pixelWidth = 1000;constraint.pixelHeight = 700
        let fixed = constraint.rect(from:CGPoint(x:1500,y:980),to:.zero,within:main,scale:2)
        precondition(fixed.width == 500 && fixed.height == 350 && main.contains(fixed))
        constraint.mode = "full"
        precondition(constraint.rect(from:.zero,to:.zero,within:main,scale:2) == main)
        print("PASS geometry: flipped origin, negative monitor coordinates, clipping, reverse drag")
    }
}
