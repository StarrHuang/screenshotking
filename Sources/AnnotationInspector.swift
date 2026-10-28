import AppKit
import SwiftUI

@MainActor struct AnnotationInspector:View {
    let tool:ImageEditorTool
    @Binding var style:AnnotationStyle
    @Binding var color:Color
    @Binding var width:Double
    var onThemeChanged:()->Void = {}
    @State private var fontSearch = ""
    var body:some View {
        ScrollView {
            Form {
                Section(L("颜色与粗细")) {
                    Toggle(L("颜色跟随主题"),isOn:Binding(get:{style.colorPreset == .theme},set:{style.colorPreset = $0 ? .theme : .custom}))
                    HStack { ForEach([AnnotationColorPreset.red,.green,.blue,.purple,.white,.black],id:\.self) { value in
                        Button { style.colorPreset = value;color = Color(nsColor:value.color) } label: { Circle().fill(Color(nsColor:value.color)).overlay(Circle().stroke(.gray.opacity(0.5))).frame(width:22,height:22) }.buttonStyle(.plain).help(value.title)
                    } }
                    ColorPicker(L("自定义颜色"),selection:Binding(get:{color},set:{color = $0;style.colorPreset = .custom}))
                    Button(L("设为全局主题色")) { AnnotationTheme.color = NSColor(color);style.colorPreset = .theme;onThemeChanged() }
                    HStack { Text(L("线宽"));Slider(value:$width,in:1...32);Text(width,format:.number.precision(.fractionLength(0))).monospacedDigit().frame(width:30);Text(L("pt")) }
                }
                if tool == .shape {
                    Section(L("形状")) {
                        Picker(L("图形"),selection:$style.shape) { ForEach(AnnotationShape.allCases) { Text($0.title).tag($0) } }
                        Picker(L("填充"),selection:$style.fill) { ForEach(AnnotationFill.allCases) { Text($0.title).tag($0) } }
                        ColorPicker(L("填充颜色"),selection:Binding(get:{Color(nsColor:style.fillColor?.nsColor ?? NSColor(color))},set:{style.fillColor = AnnotationRGBA(NSColor($0))}))
                    }
                }
                if tool == .step {
                    Picker(L("步骤样式"),selection:$style.step) { ForEach(AnnotationStepStyle.allCases) { Text($0.title).tag($0) } }
                    Picker(L("说明框方向"),selection:$style.stepDirection) { ForEach(AnnotationStepDirection.allCases) { Text($0.title).tag($0) } }
                }
                if tool == .highlight {
                    Section(L("高亮区域")) {
                        HStack { Text(L("透明度"));Slider(value:$style.highlightOpacity,in:0.05...0.8);Text(LF("%ld%%", Int(style.highlightOpacity*100))) }
                    }
                }
                if tool == .arrow { Picker(L("箭头"),selection:$style.arrow) { ForEach(AnnotationArrow.allCases) { Text($0.title).tag($0) } } }
                if tool == .pen { Picker(L("笔刷"),selection:$style.brush) { ForEach(AnnotationBrush.allCases) { Text($0.title).tag($0) } } }
                if tool == .mosaic {
                    Picker(L("模式"),selection:$style.mosaicMode) { ForEach(AnnotationMosaicMode.allCases) { Text($0.title).tag($0) } }
                    Picker(L("样式"),selection:$style.mosaicStyle) { ForEach(AnnotationMosaicStyle.allCases) { Text($0.title).tag($0) } }
                }
                if tool == .magnifier { Picker(L("倍率"),selection:$style.magnifierScale) { ForEach([1.5,2,2.5,3,3.5,4],id:\.self) { Text(LF("%.1f×", $0)).tag($0) } } }
                if tool == .watermark {
                    Section(L("平铺水印")) {
                        Toggle(L("显示水印"),isOn:$style.watermarkVisible)
                        Text(L("点击图片输入文案；双击已有水印修改，最多16字。")).font(.caption).foregroundStyle(.secondary)
                        HStack { Text(L("不透明度"));Slider(value:$style.watermarkOpacity,in:0.01...1);Text(LF("%ld%%", Int(style.watermarkOpacity*100))) }
                        HStack { Text(L("密度"));Slider(value:$style.watermarkDensity,in:0.25...3);Text(LF("%ld%%", Int(style.watermarkDensity*100))) }
                        HStack { Text(L("角度"));Slider(value:$style.watermarkAngle,in:-90...90);Text(LF("%ld°", Int(style.watermarkAngle))) }
                    }
                }
                if tool == .sticker {
                    HStack { Text(L("贴纸旋转"));Slider(value:$style.stickerRotation,in:-180...180);Text(LF("%ld°", Int(style.stickerRotation))) }
                }
                if [.note,.step,.shape,.text,.watermark].contains(tool) {
                    Section(L("文字")) {
                        Toggle(L("字号跟随主题"),isOn:$style.followsThemeSize)
                        HStack { Text(L("字号"));TextField(L("字号"),value:Binding(get:{style.resolvedFontSize},set:{style.followsThemeSize = false;style.fontSize = min(96,max(8,$0))}),format:.number).frame(width:60);Stepper("",value:Binding(get:{style.resolvedFontSize},set:{style.followsThemeSize = false;style.fontSize = $0}),in:8...96,step:1).labelsHidden();Text(L("pt")) }
                        TextField(L("搜索系统字体"),text:$fontSearch)
                        Picker(L("字体"),selection:$style.fontName) { Text(style.fontName).tag(style.fontName);ForEach(NSFontManager.shared.availableFonts.filter { $0 != style.fontName && (fontSearch.isEmpty || $0.localizedCaseInsensitiveContains(fontSearch)) },id:\.self) { Text($0).tag($0) } }
                        HStack { Toggle(L("加粗"),isOn:$style.bold);Toggle(L("斜体"),isOn:$style.italic) }
                        HStack { Toggle(L("下划线"),isOn:$style.underline);Toggle(L("删除线"),isOn:$style.strikethrough) }
                        Toggle(L("文字底色"),isOn:Binding(get:{style.textBackground != nil},set:{style.textBackground = $0 ? AnnotationRGBA(.white) : nil}))
                        if style.textBackground != nil { ColorPicker(L("底色"),selection:Binding(get:{Color(nsColor:style.textBackground!.nsColor)},set:{style.textBackground = AnnotationRGBA(NSColor($0))})) }
                    }
                }
                if [.note,.step,.shape,.text,.arrow,.pen].contains(tool) {
                    Toggle(L("自定义描边颜色"),isOn:Binding(get:{style.textOutline != nil},set:{style.textOutline = $0 ? AnnotationRGBA(.black) : nil}))
                    if style.textOutline != nil { ColorPicker(L("描边颜色"),selection:Binding(get:{Color(nsColor:style.textOutline!.nsColor)},set:{style.textOutline = AnnotationRGBA(NSColor($0))})) }
                }
            }.formStyle(.grouped).padding(8)
        }.frame(width:410,height:560)
    }
}
