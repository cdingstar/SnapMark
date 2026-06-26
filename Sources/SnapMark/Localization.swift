import Foundation

enum AppLanguage: String {
    case english
    case simplifiedChinese

    var localeIdentifier: String {
        switch self {
        case .english:
            return "en"
        case .simplifiedChinese:
            return "zh-Hans"
        }
    }
}

enum AppLanguageSetting: String, CaseIterable {
    case system
    case simplifiedChinese
    case english

    var resolvedLanguage: AppLanguage {
        switch self {
        case .system:
            return Self.systemLanguage
        case .simplifiedChinese:
            return .simplifiedChinese
        case .english:
            return .english
        }
    }

    var localizedTitle: String {
        switch self {
        case .system:
            return L10n.text(.languageSystem)
        case .simplifiedChinese:
            return L10n.text(.languageChinese)
        case .english:
            return L10n.text(.languageEnglish)
        }
    }

    private static var systemLanguage: AppLanguage {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
        return preferred.hasPrefix("zh") ? .simplifiedChinese : .english
    }
}

enum L10n {
    enum Key: String, CaseIterable {
        case languageSystem
        case languageChinese
        case languageEnglish

        case menuRegionCapture
        case menuFullScreenCapture
        case menuOpenAutoSaveFolder
        case menuSettings
        case menuAboutFormat
        case aboutInformativeTextFormat
        case aboutAppDescription
        case contactAuthor
        case menuQuit
        case hotKeyUnset
        case statusToolTipFormat

        case settingsTitle
        case settingsShortcut
        case settingsSaveDirectory
        case settingsLanguage
        case settingsLaunchMode
        case settingsChoose
        case settingsLaunchAtLogin
        case settingsChooseSaveDirectoryTitle
        case settingsLaunchAtLoginErrorTitle
        case settingsLaunchAtLoginErrorMessage
        case shortcutRecordingPrompt

        case ok
        case later
        case openSettings
        case openSystemSettings
        case cancel
        case add

        case screenAccessTitle
        case screenAccessMessage
        case captureErrorTitle
        case captureErrorMessage
        case shortcutSetErrorTitle
        case shortcutRestoreErrorTitle
        case shortcutUnavailableTitle
        case shortcutFallbackTitle
        case shortcutRequiredTitle
        case shortcutRetryMessage
        case shortcutResetMessage
        case shortcutOccupiedFormat
        case shortcutUnresponsiveFormat
        case shortcutStatusFailureFormat
        case shortcutFailureFormat
        case shortcutFallbackMessageFormat
        case shortcutChangedTipFormat

        case toolArrow
        case toolRectangle
        case toolText
        case toolMosaic
        case toolMagnifier
        case toolPen
        case toolHand
        case shapeRectangle
        case shapeCircle
        case shapeEllipse
        case arrowSolid
        case arrowNotched
        case arrowLine
        case mosaicPlain
        case mosaicBordered
        case handSelection
        case handPan

        case toolbarZoom
        case toolbarZoomTooltip
        case toolbarFit
        case toolbarTools
        case toolbarToolsTooltip
        case toolbarColor
        case toolbarNewAnnotationColor
        case toolbarUndo
        case toolbarUndoTooltip
        case toolbarCopy
        case toolbarCopyTooltip
        case toolbarSave
        case toolbarSaveTooltip
        case toolbarShare
        case toolbarShareTooltip
        case toolbarActions
        case toolbarActionsTooltip
        case saveFailed
        case penSizeMenu
        case penSizeMenuItemFormat
        case tooltipListSeparator
        case toolTextTooltip
        case toolMagnifierTooltip
        case penTooltipFormat
        case shapeTooltipFormat
        case arrowTooltipFormat
        case mosaicTooltipFormat
        case handTooltipFormat
        case zoomModeActualSize
        case zoomModeBestFit
        case zoomModeFitIn
        case zoomModeNextTooltipFormat
        case zoomModeTooltip

        case textAnnotationTitle
        case addTextTitle
        case textContent
        case textColor
        case textFontSize
        case textPreview
        case textDefault

        case colorRed
        case colorBlue
        case colorBlack
        case colorWhite
        case colorGreen
        case colorMenuTitle
        case moreColors
        case colorHex
        case colorOpacity

        case selectionWindowHintFormat
    }

    static var currentLanguage: AppLanguage {
        AppSettings.shared.languageSetting.resolvedLanguage
    }

    static func text(_ key: Key) -> String {
        strings[currentLanguage]?[key] ?? strings[.english]?[key] ?? key.rawValue
    }

    static func format(_ key: Key, _ arguments: CVarArg...) -> String {
        String(
            format: text(key),
            locale: Locale(identifier: currentLanguage.localeIdentifier),
            arguments: arguments
        )
    }

    private static let strings: [AppLanguage: [Key: String]] = [
        .english: [
            .languageSystem: "Follow System",
            .languageChinese: "Simplified Chinese",
            .languageEnglish: "English",

            .menuRegionCapture: "Capture Region",
            .menuFullScreenCapture: "Capture Full Screen",
            .menuOpenAutoSaveFolder: "Open Auto-Save Folder",
            .menuSettings: "Settings...",
            .menuAboutFormat: "About %@",
            .aboutInformativeTextFormat: "%@\n\n%@\n\nMailto: %@",
            .aboutAppDescription: "SnapMark is a lightweight screenshot annotation tool for quickly capturing, marking up, saving, and sharing images.",
            .contactAuthor: "Contact Author",
            .menuQuit: "Quit",
            .hotKeyUnset: "Not Set",
            .statusToolTipFormat: "SnapMark V%@\n\nShortcut %@\n\nmailto: cdingstar@gmail.com",

            .settingsTitle: "Settings",
            .settingsShortcut: "Shortcut",
            .settingsSaveDirectory: "Save Folder",
            .settingsLanguage: "Language",
            .settingsLaunchMode: "Launch",
            .settingsChoose: "Choose...",
            .settingsLaunchAtLogin: "Launch at Login",
            .settingsChooseSaveDirectoryTitle: "Choose Auto-Save Folder",
            .settingsLaunchAtLoginErrorTitle: "Launch at Login Failed",
            .settingsLaunchAtLoginErrorMessage: "Make sure SnapMark is running from the .app bundle, not a temporary command-line process.",
            .shortcutRecordingPrompt: "Press a new shortcut",

            .ok: "OK",
            .later: "Later",
            .openSettings: "Open Settings",
            .openSystemSettings: "Open System Settings",
            .cancel: "Cancel",
            .add: "Add",

            .screenAccessTitle: "Screen Recording Permission Required",
            .screenAccessMessage: "Allow SnapMark in System Settings > Privacy & Security > Screen Recording, then try capturing again.",
            .captureErrorTitle: "Capture Failed",
            .captureErrorMessage: "SnapMark could not get a screen image. Please confirm Screen Recording permission is enabled.",
            .shortcutSetErrorTitle: "Shortcut Setup Failed",
            .shortcutRestoreErrorTitle: "Shortcut Restore Failed",
            .shortcutUnavailableTitle: "Capture Shortcut Unavailable",
            .shortcutFallbackTitle: "Capture Shortcut Adjusted",
            .shortcutRequiredTitle: "Capture Shortcut Required",
            .shortcutRetryMessage: "Please choose another hotkey.",
            .shortcutResetMessage: "Please choose another hotkey in Settings.",
            .shortcutOccupiedFormat: "%@ is already registered by another app or the system. macOS does not expose the app name.",
            .shortcutUnresponsiveFormat: "%@ registered successfully, but pressing it did not trigger SnapMark. Another app may be intercepting it.",
            .shortcutStatusFailureFormat: "%@ registration failed (OSStatus %ld).",
            .shortcutFailureFormat: "%@ registration failed.",
            .shortcutFallbackMessageFormat: "%@\nAutomatically switched to %@.",
            .shortcutChangedTipFormat: "Shortcut changed automatically\n\n%@ did not trigger SnapMark\nChanged to %@",

            .toolArrow: "Arrow",
            .toolRectangle: "Shape",
            .toolText: "Text",
            .toolMosaic: "Mosaic",
            .toolMagnifier: "Lens",
            .toolPen: "Pen",
            .toolHand: "Hand",
            .shapeRectangle: "Rectangle",
            .shapeCircle: "Circle",
            .shapeEllipse: "Ellipse",
            .arrowSolid: "Solid Arrow",
            .arrowNotched: "Notched Arrow",
            .arrowLine: "Line",
            .mosaicPlain: "No Border",
            .mosaicBordered: "Bordered",
            .handSelection: "Area Move",
            .handPan: "Pan Canvas",

            .toolbarZoom: "Zoom",
            .toolbarZoomTooltip: "Zoom and image size\nLeft shows zoom and matched mode; right shows pixel size. Hover to show the slider, drag it to zoom, or click Fit to cycle non-duplicate 1:1, Best Fit, and Fit In ratios.",
            .toolbarFit: "Fit",
            .toolbarTools: "Tools",
            .toolbarToolsTooltip: "Annotation tools\nEach icon selects a tool. Icons with multiple modes show the current mode in their own tooltip; click the selected icon again to cycle modes.",
            .toolbarColor: "Color",
            .toolbarNewAnnotationColor: "New annotation color\nClick the left area to cycle Red, White, Blue, and Black. Click the arrow to open the compact color palette.",
            .toolbarUndo: "Undo",
            .toolbarUndoTooltip: "Undo\nRevert the last annotation change.",
            .toolbarCopy: "Copy",
            .toolbarCopyTooltip: "Copy\nCopy the rendered image to the clipboard.",
            .toolbarSave: "Save",
            .toolbarSaveTooltip: "Save\nSave the rendered image to the auto-save folder.",
            .toolbarShare: "Share",
            .toolbarShareTooltip: "Share\nOpen macOS Share to send with AirDrop, Mail, and other services.",
            .toolbarActions: "Actions",
            .toolbarActionsTooltip: "Actions\nUndo the last edit, copy or save the rendered image, or share it with macOS Share.",
            .saveFailed: "Save Failed",
            .penSizeMenu: "Pen Size",
            .penSizeMenuItemFormat: "Pen %@",
            .tooltipListSeparator: ", ",
            .toolTextTooltip: "Text tool\nClick the image to add text. Click an existing text item to edit, move, resize, or delete it.",
            .toolMagnifierTooltip: "Lens tool\nDrag to create a magnified lens area. Select it later to move, resize, or delete it.",
            .penTooltipFormat: "Pen tool\nCurrent thickness: %@\nClick to draw freehand strokes; click the selected Pen again to cycle %@. Use the small menu arrow to choose directly.",
            .shapeTooltipFormat: "Shape tool\nCurrent mode: %@\nClick to draw a shape; click the selected Shape again to cycle %@.",
            .arrowTooltipFormat: "Arrow tool\nCurrent mode: %@\nClick to draw; click the selected Arrow again to cycle %@.",
            .mosaicTooltipFormat: "Mosaic tool\nCurrent mode: %@\nDrag to hide an area; click the selected Mosaic again to cycle %@.",
            .handTooltipFormat: "Hand tool\nCurrent mode: %@\nClick the selected Hand again to cycle %@. Area Move selects and moves or copies a region; Pan Canvas only drags the canvas.",
            .zoomModeActualSize: "1:1",
            .zoomModeBestFit: "Best Fit",
            .zoomModeFitIn: "Fit In",
            .zoomModeNextTooltipFormat: "Fit zoom\nCurrent: %@\nClick to switch to %@ (%@). Duplicate zoom ratios are skipped.",
            .zoomModeTooltip: "Fit zoom\nOnly one available zoom ratio is currently usable.",

            .textAnnotationTitle: "Text Annotation",
            .addTextTitle: "Add Text",
            .textContent: "Content",
            .textColor: "Color",
            .textFontSize: "Size",
            .textPreview: "Preview",
            .textDefault: "Text",

            .colorRed: "Red",
            .colorBlue: "Blue",
            .colorBlack: "Black",
            .colorWhite: "White",
            .colorGreen: "Green",
            .colorMenuTitle: "Choose Annotation Color",
            .moreColors: "More Colors...",
            .colorHex: "Hex",
            .colorOpacity: "Opacity",

            .selectionWindowHintFormat: "%@  Click to capture window · Drag to select area"
        ],
        .simplifiedChinese: [
            .languageSystem: "跟随系统",
            .languageChinese: "简体中文",
            .languageEnglish: "English",

            .menuRegionCapture: "区域截图",
            .menuFullScreenCapture: "全屏截图",
            .menuOpenAutoSaveFolder: "打开自动保存文件夹",
            .menuSettings: "设置...",
            .menuAboutFormat: "关于 %@",
            .aboutInformativeTextFormat: "%@\n\n%@\n\nMailto: %@",
            .aboutAppDescription: "SnapMark 是一款轻量截图标注工具，用于快速截图、添加标注，并保存或通过系统共享发送结果。",
            .contactAuthor: "联系作者",
            .menuQuit: "退出",
            .hotKeyUnset: "未设置",
            .statusToolTipFormat: "SnapMark V%@\n\n快捷键 %@\n\nmailto: cdingstar@gmail.com",

            .settingsTitle: "设置",
            .settingsShortcut: "快捷键",
            .settingsSaveDirectory: "存储目录",
            .settingsLanguage: "语言",
            .settingsLaunchMode: "启动方式",
            .settingsChoose: "选择...",
            .settingsLaunchAtLogin: "允许自动开机启动",
            .settingsChooseSaveDirectoryTitle: "选择自动保存目录",
            .settingsLaunchAtLoginErrorTitle: "开机启动设置失败",
            .settingsLaunchAtLoginErrorMessage: "请确认 SnapMark 是从 .app 包运行，而不是从命令行临时进程运行。",
            .shortcutRecordingPrompt: "请按新的快捷键",

            .ok: "知道了",
            .later: "稍后",
            .openSettings: "打开设置",
            .openSystemSettings: "打开系统设置",
            .cancel: "取消",
            .add: "添加",

            .screenAccessTitle: "需要屏幕录制权限",
            .screenAccessMessage: "请在 系统设置 > 隐私与安全性 > 屏幕录制 中允许 SnapMark，然后重新截图。",
            .captureErrorTitle: "截图失败",
            .captureErrorMessage: "没有拿到屏幕图像，请确认屏幕录制权限已开启。",
            .shortcutSetErrorTitle: "快捷键设置失败",
            .shortcutRestoreErrorTitle: "快捷键恢复失败",
            .shortcutUnavailableTitle: "截图快捷键不可用",
            .shortcutFallbackTitle: "截图快捷键已自动调整",
            .shortcutRequiredTitle: "需要设置截图快捷键",
            .shortcutRetryMessage: "请重新选择 Hotkey。",
            .shortcutResetMessage: "请在设置中重新选择 Hotkey。",
            .shortcutOccupiedFormat: "%@ 已被其他应用程序或系统注册。macOS 未提供具体应用名称。",
            .shortcutUnresponsiveFormat: "%@ 注册成功但按下后没有触发 SnapMark，可能被其他应用拦截。",
            .shortcutStatusFailureFormat: "%@ 注册失败（OSStatus %ld）。",
            .shortcutFailureFormat: "%@ 注册失败。",
            .shortcutFallbackMessageFormat: "%@\n已自动改用 %@。",
            .shortcutChangedTipFormat: "快捷键已自动切换\n\n%@ 没有触发 SnapMark\n已改为 %@",

            .toolArrow: "箭头",
            .toolRectangle: "形状",
            .toolText: "文字",
            .toolMosaic: "马赛克",
            .toolMagnifier: "放大镜",
            .toolPen: "画笔",
            .toolHand: "手形",
            .shapeRectangle: "矩形",
            .shapeCircle: "圆形",
            .shapeEllipse: "椭圆",
            .arrowSolid: "实心箭头",
            .arrowNotched: "凹口箭头",
            .arrowLine: "直线",
            .mosaicPlain: "无外框",
            .mosaicBordered: "有外框",
            .handSelection: "区域搬运",
            .handPan: "拖拉画布",

            .toolbarZoom: "缩放",
            .toolbarZoomTooltip: "缩放和截图尺寸\n左侧显示缩放比例和匹配模式，右侧显示像素尺寸。鼠标悬停可显示缩放滑杆，拖动可精细缩放；点击适应按钮会在去重后的 1:1、最佳适应、完整显示之间切换。",
            .toolbarFit: "适应",
            .toolbarTools: "工具",
            .toolbarToolsTooltip: "标注工具\n每个图标选择一种工具。带多模式的按钮会在自己的提示里显示当前模式；再次点击已选中的图标可循环切换。",
            .toolbarColor: "颜色",
            .toolbarNewAnnotationColor: "新标注颜色\n点击左侧区域会在红色、白色、蓝色、黑色之间循环；点击右侧箭头打开简洁色盘。",
            .toolbarUndo: "撤销",
            .toolbarUndoTooltip: "撤销\n回退上一步标注修改。",
            .toolbarCopy: "复制",
            .toolbarCopyTooltip: "复制\n把渲染后的图片复制到剪贴板。",
            .toolbarSave: "保存",
            .toolbarSaveTooltip: "保存\n把渲染后的图片保存到自动保存目录。",
            .toolbarShare: "共享",
            .toolbarShareTooltip: "共享\n打开 macOS 系统共享，可发送到 AirDrop、邮件和其他服务。",
            .toolbarActions: "操作",
            .toolbarActionsTooltip: "操作\n可撤销上一步、复制或保存渲染图片，也可以调用 macOS 系统共享。",
            .saveFailed: "保存失败",
            .penSizeMenu: "画笔粗细",
            .penSizeMenuItemFormat: "画笔 %@",
            .tooltipListSeparator: "、",
            .toolTextTooltip: "文字工具\n点击图片添加文字；点击已有文字可重新编辑、移动、缩放或删除。",
            .toolMagnifierTooltip: "放大镜工具\n拖拽创建放大镜区域；之后可选中移动、缩放或删除。",
            .penTooltipFormat: "画笔工具\n当前粗细：%@\n点击后可自由绘制；再次点击已选中的画笔可循环切换：%@。也可以通过小箭头直接选择粗细。",
            .shapeTooltipFormat: "形状工具\n当前模式：%@\n点击后绘制形状；再次点击已选中的形状可循环切换：%@。",
            .arrowTooltipFormat: "箭头工具\n当前模式：%@\n点击后绘制箭头或直线；再次点击已选中的箭头可循环切换：%@。",
            .mosaicTooltipFormat: "马赛克工具\n当前模式：%@\n拖拽遮挡区域；再次点击已选中的马赛克可循环切换：%@。",
            .handTooltipFormat: "手形工具\n当前模式：%@\n再次点击已选中的手形可循环切换：%@。区域搬运可选择并移动/复制区域，拖拉画布只移动视图。",
            .zoomModeActualSize: "1:1",
            .zoomModeBestFit: "最佳适应",
            .zoomModeFitIn: "完整显示",
            .zoomModeNextTooltipFormat: "适应缩放\n当前：%@\n点击切换到 %@（%@）。重复比例会自动排除。",
            .zoomModeTooltip: "适应缩放\n当前只有一个可用缩放比例。",

            .textAnnotationTitle: "文字标注",
            .addTextTitle: "添加文字",
            .textContent: "内容",
            .textColor: "颜色",
            .textFontSize: "字号",
            .textPreview: "预览",
            .textDefault: "文字",

            .colorRed: "红色",
            .colorBlue: "蓝色",
            .colorBlack: "黑色",
            .colorWhite: "白色",
            .colorGreen: "绿色",
            .colorMenuTitle: "选择标注颜色",
            .moreColors: "更多颜色...",
            .colorHex: "Hex",
            .colorOpacity: "透明度",

            .selectionWindowHintFormat: "%@  点击截取窗口 · 拖拽选择区域"
        ]
    ]
}
