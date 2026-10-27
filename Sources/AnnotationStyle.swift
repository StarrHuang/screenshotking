import AppKit

public enum AnnotationShape: String, Codable, CaseIterable, Identifiable {
    case rectangle, roundedRectangle, circle, triangle, chatBubble, star, pentagon, hexagon
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .rectangle: "矩形"
        case .roundedRectangle: "圆角矩形"
        case .circle: "圆形"
        case .triangle: "三角形"
        case .chatBubble: "聊天框"
        case .star: "五角星"
        case .pentagon: "五边形"
        case .hexagon: "六边形"
        }
    }
}

public enum AnnotationFill: String, Codable, CaseIterable, Identifiable {
    case outline, translucent, solid, dashedOutline, dashedTranslucent, hatched
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .outline: "镂空"
        case .translucent: "半透明"
        case .solid: "实心"
        case .dashedOutline: "虚线镂空"
        case .dashedTranslucent: "虚线半透明"
        case .hatched: "斜纹填充"
        }
    }
}

public enum AnnotationArrow: String, Codable, CaseIterable, Identifiable {
    case straight, single, cone, double, dashed, dashedSingle, dashedDouble
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .straight: "直线"
        case .single: "单箭头"
        case .cone: "锥形箭头"
        case .double: "双箭头"
        case .dashed: "虚线"
        case .dashedSingle: "虚线单箭头"
        case .dashedDouble: "虚线双箭头"
        }
    }
    public var dashed: Bool { self == .dashed || self == .dashedSingle || self == .dashedDouble }
    public var hasHead: Bool { self == .single || self == .cone || self == .double || self == .dashedSingle || self == .dashedDouble }
    public var hasTail: Bool { self == .double || self == .dashedDouble }
}

public enum AnnotationBrush: String, Codable, CaseIterable, Identifiable {
    case pen, highlighter
    public var id: String { rawValue }
    public var title: String { self == .pen ? "普通笔" : "荧光笔" }
}

public enum AnnotationMosaicMode: String, Codable, CaseIterable, Identifiable {
    case rectangle, brushSmall, brushMedium, brushLarge
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .rectangle: "矩形"
        case .brushSmall: "画笔·小"
        case .brushMedium: "画笔·中"
        case .brushLarge: "画笔·大"
        }
    }
    public var radius: Double {
        switch self { case .rectangle: 0; case .brushSmall: 10; case .brushMedium: 22; case .brushLarge: 38 }
    }
}

public enum AnnotationMosaicStyle: String, Codable, CaseIterable, Identifiable {
    case finePixelated, pixelated, coarsePixelated, lightBlur, gaussianBlur, strongBlur
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .finePixelated: "细像素"
        case .pixelated: "像素"
        case .coarsePixelated: "粗像素"
        case .lightBlur: "轻模糊"
        case .gaussianBlur: "模糊"
        case .strongBlur: "强模糊"
        }
    }
}

public enum AnnotationStepStyle: String, Codable, CaseIterable, Identifiable {
    case integrated, connected
    public var id: String { rawValue }
    public var title: String { self == .integrated ? "一体" : "连线" }
}

public enum AnnotationStepDirection: String, Codable, CaseIterable, Identifiable {
    case right, left, above, below
    public var id: String { rawValue }
    public var title: String {
        switch self { case .right: "右侧"; case .left: "左侧"; case .above: "上方"; case .below: "下方" }
    }
}

public enum AnnotationSize: String, Codable, CaseIterable, Identifiable {
    case small, medium, large
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .small: "小"
        case .medium: "中"
        case .large: "大"
        }
    }
    public var fontSize: Double {
        switch self {
        case .small: 13
        case .medium: 17
        case .large: 23
        }
    }
}

public enum AnnotationColorPreset: String, Codable, CaseIterable, Identifiable {
    case red, green, blue, purple, white, black, theme, custom
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .red: "红"
        case .green: "绿"
        case .blue: "蓝"
        case .purple: "紫"
        case .white: "白"
        case .black: "黑"
        case .theme: "跟随主题"
        case .custom: "自定义"
        }
    }
    public var color: NSColor {
        switch self {
        case .red: .systemRed
        case .green: .systemGreen
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .white: .white
        case .black: .black
        case .theme: .controlAccentColor
        case .custom: .systemRed
        }
    }
}

public struct AnnotationRGBA: Codable, Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double
    public init(_ color: NSColor) {
        let c = color.usingColorSpace(.deviceRGB) ?? .red
        red = c.redComponent; green = c.greenComponent; blue = c.blueComponent; alpha = c.alphaComponent
    }
    public var nsColor: NSColor { NSColor(deviceRed: red, green: green, blue: blue, alpha: alpha) }
}

public enum AnnotationTheme {
    public static var size:AnnotationSize {
        get { AnnotationSize(rawValue:UserDefaults.standard.string(forKey:"annotationThemeSize") ?? "medium") ?? .medium }
        set { UserDefaults.standard.set(newValue.rawValue,forKey:"annotationThemeSize") }
    }
    public static var color:NSColor {
        get {
            guard let rgba = UserDefaults.standard.array(forKey:"annotationThemeColor") as? [Double],rgba.count == 4 else { return .systemBlue }
            return NSColor(srgbRed:rgba[0],green:rgba[1],blue:rgba[2],alpha:rgba[3])
        }
        set { let rgba = AnnotationRGBA(newValue);UserDefaults.standard.set([rgba.red,rgba.green,rgba.blue,rgba.alpha],forKey:"annotationThemeColor") }
    }
}

/// Per-annotation appearance. Optional fields make old v1 documents decode with defaults.
public struct AnnotationStyle: Codable, Equatable {
    public var shape: AnnotationShape
    public var fill: AnnotationFill
    public var arrow: AnnotationArrow
    public var brush: AnnotationBrush
    public var step: AnnotationStepStyle
    public var stepDirection: AnnotationStepDirection
    public var highlightOpacity: Double
    public var mosaicMode: AnnotationMosaicMode
    public var mosaicStyle: AnnotationMosaicStyle
    public var magnifierScale: Double
    public var watermarkOpacity: Double
    public var watermarkDensity: Double
    public var watermarkAngle: Double
    public var watermarkVisible: Bool
    public var sticker: StickerSelection?
    public var stickerRotation: Double
    public var size: AnnotationSize
    public var colorPreset: AnnotationColorPreset
    public var fontName: String
    public var fontSize: Double
    public var bold: Bool
    public var italic: Bool
    public var underline: Bool
    public var strikethrough: Bool
    public var textBackground: AnnotationRGBA?
    public var textOutline: AnnotationRGBA?
    public var fillColor: AnnotationRGBA?
    public var followsThemeSize = false
    public var resolvedFontSize:Double { followsThemeSize ? fontSize * AnnotationTheme.size.fontSize / 17 : fontSize }

    public init(shape: AnnotationShape = .rectangle, fill: AnnotationFill = .outline, arrow: AnnotationArrow = .single, brush: AnnotationBrush = .pen, step: AnnotationStepStyle = .integrated, stepDirection: AnnotationStepDirection = .right, highlightOpacity: Double = 0.32, mosaicMode: AnnotationMosaicMode = .rectangle, mosaicStyle: AnnotationMosaicStyle = .pixelated, magnifierScale: Double = 2, watermarkOpacity: Double = 0.3, watermarkDensity: Double = 1, watermarkAngle: Double = -14, watermarkVisible: Bool = true, sticker: StickerSelection? = nil, stickerRotation: Double = 0, size: AnnotationSize = .medium, colorPreset: AnnotationColorPreset = .red, fontName: String = NSFont.systemFont(ofSize: 17).fontName, fontSize: Double = 17, bold: Bool = false, italic: Bool = false, underline: Bool = false, strikethrough: Bool = false, textBackground: AnnotationRGBA? = nil, textOutline: AnnotationRGBA? = nil, fillColor: AnnotationRGBA? = nil) {
        self.shape = shape; self.fill = fill; self.arrow = arrow; self.brush = brush; self.step = step; self.stepDirection = stepDirection; self.highlightOpacity = highlightOpacity
        self.mosaicMode = mosaicMode; self.mosaicStyle = mosaicStyle
        self.magnifierScale = magnifierScale; self.watermarkOpacity = watermarkOpacity; self.watermarkDensity = watermarkDensity; self.watermarkAngle = watermarkAngle; self.watermarkVisible = watermarkVisible
        self.sticker = sticker; self.stickerRotation = stickerRotation
        self.size = size; self.colorPreset = colorPreset; self.fontName = fontName; self.fontSize = fontSize
        self.bold = bold; self.italic = italic; self.underline = underline; self.strikethrough = strikethrough
        self.textBackground = textBackground; self.textOutline = textOutline; self.fillColor = fillColor
    }

    private enum CodingKeys: String, CodingKey {
        case shape, fill, arrow, brush, step, stepDirection, highlightOpacity, mosaicMode, mosaicStyle, magnifierScale, watermarkOpacity, watermarkDensity, watermarkAngle, watermarkVisible, sticker, stickerRotation, size, colorPreset, fontName, fontSize
        case bold, italic, underline, strikethrough, textBackground, textOutline, fillColor, followsThemeSize
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(shape: try c.decodeIfPresent(AnnotationShape.self, forKey: .shape) ?? .rectangle,
                  fill: try c.decodeIfPresent(AnnotationFill.self, forKey: .fill) ?? .outline,
                  arrow: try c.decodeIfPresent(AnnotationArrow.self, forKey: .arrow) ?? .single,
                  brush: try c.decodeIfPresent(AnnotationBrush.self, forKey: .brush) ?? .pen,
                  step: try c.decodeIfPresent(AnnotationStepStyle.self, forKey: .step) ?? .integrated,
                  stepDirection: try c.decodeIfPresent(AnnotationStepDirection.self, forKey: .stepDirection) ?? .right,
                  highlightOpacity: try c.decodeIfPresent(Double.self, forKey: .highlightOpacity) ?? 0.32,
                  mosaicMode: try c.decodeIfPresent(AnnotationMosaicMode.self, forKey: .mosaicMode) ?? .rectangle,
                  mosaicStyle: try c.decodeIfPresent(AnnotationMosaicStyle.self, forKey: .mosaicStyle) ?? .pixelated,
                  magnifierScale: try c.decodeIfPresent(Double.self, forKey: .magnifierScale) ?? 2,
                  watermarkOpacity: try c.decodeIfPresent(Double.self, forKey: .watermarkOpacity) ?? 0.3,
                  watermarkDensity: try c.decodeIfPresent(Double.self, forKey: .watermarkDensity) ?? 1,
                  watermarkAngle: try c.decodeIfPresent(Double.self, forKey: .watermarkAngle) ?? -14,
                  watermarkVisible: try c.decodeIfPresent(Bool.self, forKey: .watermarkVisible) ?? true,
                  sticker: try c.decodeIfPresent(StickerSelection.self, forKey: .sticker),
                  stickerRotation: try c.decodeIfPresent(Double.self, forKey: .stickerRotation) ?? 0,
                  size: try c.decodeIfPresent(AnnotationSize.self, forKey: .size) ?? .medium,
                  colorPreset: try c.decodeIfPresent(AnnotationColorPreset.self, forKey: .colorPreset) ?? .red,
                  fontName: try c.decodeIfPresent(String.self, forKey: .fontName) ?? NSFont.systemFont(ofSize: 17).fontName,
                  fontSize: try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? 17,
                  bold: try c.decodeIfPresent(Bool.self, forKey: .bold) ?? false,
                  italic: try c.decodeIfPresent(Bool.self, forKey: .italic) ?? false,
                  underline: try c.decodeIfPresent(Bool.self, forKey: .underline) ?? false,
                  strikethrough: try c.decodeIfPresent(Bool.self, forKey: .strikethrough) ?? false,
                  textBackground: try c.decodeIfPresent(AnnotationRGBA.self, forKey: .textBackground),
                  textOutline: try c.decodeIfPresent(AnnotationRGBA.self, forKey: .textOutline),
                  fillColor: try c.decodeIfPresent(AnnotationRGBA.self, forKey: .fillColor))
        followsThemeSize = try c.decodeIfPresent(Bool.self,forKey:.followsThemeSize) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(shape, forKey: .shape); try c.encode(fill, forKey: .fill); try c.encode(arrow, forKey: .arrow)
        try c.encode(brush, forKey: .brush); try c.encode(step, forKey: .step); try c.encode(stepDirection, forKey: .stepDirection); try c.encode(highlightOpacity, forKey: .highlightOpacity); try c.encode(mosaicMode, forKey: .mosaicMode); try c.encode(mosaicStyle, forKey: .mosaicStyle)
        try c.encode(magnifierScale, forKey: .magnifierScale); try c.encode(watermarkOpacity, forKey: .watermarkOpacity); try c.encode(watermarkDensity, forKey: .watermarkDensity); try c.encode(watermarkAngle, forKey: .watermarkAngle); try c.encode(watermarkVisible, forKey: .watermarkVisible); try c.encode(size, forKey: .size)
        try c.encodeIfPresent(sticker, forKey: .sticker); try c.encode(stickerRotation, forKey: .stickerRotation)
        try c.encode(colorPreset, forKey: .colorPreset); try c.encode(fontName, forKey: .fontName); try c.encode(fontSize, forKey: .fontSize)
        try c.encode(bold, forKey: .bold); try c.encode(italic, forKey: .italic); try c.encode(underline, forKey: .underline); try c.encode(strikethrough, forKey: .strikethrough)
        try c.encodeIfPresent(textBackground, forKey: .textBackground); try c.encodeIfPresent(textOutline, forKey: .textOutline); try c.encodeIfPresent(fillColor, forKey: .fillColor)
        try c.encode(followsThemeSize,forKey:.followsThemeSize)
    }
}
