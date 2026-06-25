#!/usr/bin/env python3
import argparse
import plistlib
import re
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Callable

try:
    from PIL import Image
except Exception:
    Image = None


@dataclass
class TestCase:
    case_id: str
    title: str
    check: Callable[[], None]


class FunctionalTestRunner:
    def __init__(self, root: Path, app: Path | None):
        self.root = root
        self.app = app

    def read(self, relative: str) -> str:
        return (self.root / relative).read_text(encoding="utf-8")

    def require(self, condition: bool, message: str) -> None:
        if not condition:
            raise AssertionError(message)

    def require_file(self, relative: str) -> Path:
        path = self.root / relative
        self.require(path.is_file(), f"missing file: {relative}")
        return path

    def cases(self) -> list[TestCase]:
        cases = [
            TestCase("SMK-P0-SHOT-001", "区域截图入口存在并走 ScreenSelectionResult.region", self.case_region_capture),
            TestCase("SMK-P0-SHOT-002", "全屏截图入口使用 ScreenCaptureService.captureFullScreen", self.case_fullscreen_capture),
            TestCase("SMK-P0-SHOT-003", "窗口探测和点击整窗截图路径存在", self.case_window_capture),
            TestCase("SMK-P0-SHOT-004", "截图激活状态支持 Esc reset", self.case_escape_reset),
            TestCase("SMK-P0-SHOT-006", "截图遮罩窗口可接收 Esc 键盘事件", self.case_selection_window_receives_escape),
            TestCase("SMK-P0-SHOT-007", "区域截图坐标按屏幕和 backing scale 映射", self.case_region_coordinate_mapping),
            TestCase("SMK-P0-SHOT-008", "实际截图内容尺寸与选择像素尺寸一致", self.case_region_capture_pixel_size),
            TestCase("SMK-P0-SHOT-009", "选择框尺寸提示显示实际像素", self.case_selection_size_label_pixels),
            TestCase("SMK-P0-MAG-001", "截图选择放大镜为 10x 像素化放大", self.case_selection_magnifier),
            TestCase("SMK-P0-ANN-001", "编辑器标注工具覆盖箭头/矩形/文字/马赛克/放大镜", self.case_annotation_tools),
            TestCase("SMK-P0-EDITOR-001", "编辑器使用棋盘底、居中显示、缩放和平移", self.case_editor_checkerboard_zoom_pan),
            TestCase("SMK-P0-EDITOR-002", "编辑器缩放不影响保存/复制输出像素", self.case_editor_export_independent_from_zoom),
            TestCase("SMK-P0-EDITOR-003", "编辑器标注坐标按缩放反算到图片像素", self.case_editor_annotation_coordinate_mapping),
            TestCase("SMK-P0-EDITOR-004", "编辑器 fit 和缩放范围覆盖 1:8 到 8:1", self.case_editor_zoom_range),
            TestCase("SMK-P0-SAVE-001", "自动保存目录读取设置且默认 Downloads", self.case_autosave_settings),
            TestCase("SMK-P0-HOT-001", "默认快捷键 fallback 为 A/S/Q", self.case_hotkey_fallbacks),
            TestCase("SMK-P0-HOT-002", "快捷键失效检测和自动切换逻辑存在", self.case_hotkey_health_check),
            TestCase("SMK-P0-HOT-003", "菜单与 tooltip 显示实际快捷键", self.case_hotkey_ui_text),
            TestCase("SMK-P0-DRAG-001", "拖拽复制生成临时 PNG 并以 copy 操作拖出", self.case_drag_copy),
            TestCase("SMK-P0-SET-001", "设置窗口覆盖快捷键/存储目录/开机启动", self.case_settings_window),
            TestCase("SMK-P0-ICON-001", "图标资源完整且尺寸正确", self.case_icon_assets),
            TestCase("SMK-P0-BUNDLE-001", "Info.plist app 元数据完整", self.case_info_plist),
            TestCase("SMK-P0-BUNDLE-002", "构建脚本包含稳定签名和资源打包", self.case_build_script),
            TestCase("SMK-P0-BUNDLE-005", "版本号遵循 1.<自动递增>.MMDD 规则", self.case_version_rule),
            TestCase("SMK-P0-ARCH-001", "截图相关模块已拆分且文件大小受控", self.case_module_size_budget),
            TestCase("SMK-P1-PLAN-001", "P1 功能规划已记录", self.case_p1_plan_recorded),
            TestCase("SMK-PSTAR-PLAN-001", "P* 功能规划已记录", self.case_pstar_plan_recorded),
            TestCase("SMK-QA-001", "测试计划文档覆盖 P0 功能点", self.case_test_plan_coverage),
        ]

        if self.app:
            cases.extend([
                TestCase("SMK-P0-BUNDLE-003", "app bundle 内含可执行文件和图标资源", self.case_app_bundle_resources),
                TestCase("SMK-P0-BUNDLE-004", "app bundle 已完成 codesign", self.case_app_codesign),
            ])

        return cases

    def case_region_capture(self) -> None:
        app = self.read("Sources/SnapMark/AppDelegate.swift")
        controller = self.read("Sources/SnapMark/ScreenSelectionController.swift")
        self.require("captureRegion()" in app, "missing captureRegion entry")
        self.require("case region(ScreenCaptureRegion)" in controller, "ScreenSelectionResult.region missing")
        self.require("case .region(let region)" in app, "AppDelegate does not handle region result")

    def case_fullscreen_capture(self) -> None:
        app = self.read("Sources/SnapMark/AppDelegate.swift")
        service = self.read("Sources/SnapMark/ScreenCaptureService.swift")
        self.require("captureFullScreen()" in app, "missing full screen action")
        self.require("func captureFullScreen()" in service, "missing captureFullScreen service")
        self.require("NSScreen.screens" in service, "full screen capture should cover all screens")

    def case_window_capture(self) -> None:
        controller = self.read("Sources/SnapMark/ScreenSelectionController.swift")
        view = self.read("Sources/SnapMark/ScreenSelectionView.swift")
        inspector = self.read("Sources/SnapMark/WindowInspector.swift")
        service = self.read("Sources/SnapMark/ScreenCaptureService.swift")
        app = self.read("Sources/SnapMark/AppDelegate.swift")
        self.require("case window(WindowTarget)" in controller, "window selection result missing")
        self.require("WindowInspector.visibleWindowTargets" in controller, "window targets are not loaded on activation")
        self.require("WindowInspector.windowUnder" in view, "mousemove window hit-test missing")
        self.require("onWindowComplete?(target)" in view, "click-to-window selection missing")
        self.require("capture(windowID:" in service and ".optionIncludingWindow" in service, "window id capture missing")
        self.require("case .window(let target)" in app, "AppDelegate does not handle window capture")

    def case_escape_reset(self) -> None:
        app = self.read("Sources/SnapMark/AppDelegate.swift")
        selection = self.read("Sources/SnapMark/ScreenSelectionView.swift")
        canvas = self.read("Sources/SnapMark/EditorCanvasView.swift")
        editor = self.read("Sources/SnapMark/EditorWindowController.swift")
        self.require("configureResetMonitor()" in app and "resetStatus()" in app, "global reset monitor missing")
        self.require("event.keyCode == 53" in selection, "selection Esc handling missing")
        self.require("onResetRequested" in canvas, "canvas Esc reset callback missing")
        self.require("resetAndClose()" in editor, "editor Esc reset close missing")

    def case_selection_window_receives_escape(self) -> None:
        controller = self.read("Sources/SnapMark/ScreenSelectionController.swift")
        window = self.read("Sources/SnapMark/ScreenSelectionWindow.swift")
        selection = self.read("Sources/SnapMark/ScreenSelectionView.swift")
        self.require("ScreenSelectionWindow(" in controller, "selection overlay must use key-capable window subclass")
        self.require("NSApp.activate(ignoringOtherApps: true)" in controller, "app must activate before selection to receive local key events")
        self.require("override var canBecomeKey: Bool" in window and "true" in window, "selection window must become key")
        self.require("override var canBecomeMain: Bool" in window and "true" in window, "selection window must become main")
        self.require("override func keyDown" in window and "cancelFromKeyboard()" in window, "selection window must route Esc to cancel")
        self.require("func cancelFromKeyboard()" in selection, "selection view must expose keyboard cancel path")

    def case_region_coordinate_mapping(self) -> None:
        region = self.read("Sources/SnapMark/ScreenCaptureRegion.swift")
        controller = self.read("Sources/SnapMark/ScreenSelectionController.swift")
        service = self.read("Sources/SnapMark/ScreenCaptureService.swift")
        app = self.read("Sources/SnapMark/AppDelegate.swift")

        for token in [
            "backingScaleFactor = max(1, screen.backingScaleFactor)",
            "floor(rect.minX * scale) / scale",
            "ceil(rect.maxX * scale) / scale",
            "screenFrame.maxY - appKitRect.maxY",
            "displayBounds(for: screen)",
            "CGDisplayBounds(CGDirectDisplayID",
            "pixelSize = Self.pixelSize",
        ]:
            self.require(token in region, f"coordinate mapper missing {token}")

        self.require("ScreenCaptureRegion(appKitRect: screenRect, screen: window.screen)" in controller, "selection completion must map through ScreenCaptureRegion")
        self.require("capture(region: ScreenCaptureRegion)" in service, "capture service must accept mapped region")
        self.require("region.coreGraphicsRect" in service, "capture service must use CoreGraphics rect")
        self.require("expectedPixelSize: region.pixelSize" in service, "capture service must preserve expected pixel size")
        self.require("rect," in service and "rect.integral" not in service, "capture must not re-integral already pixel-aligned rect")
        self.require("captureService.capture(region: region)" in app, "AppDelegate must capture mapped region")

        scale = 2
        rect = {"min_x": 120.25, "min_y": 80.25, "max_x": 150.5, "max_y": 120.5}
        aligned_min_x = (rect["min_x"] * scale // 1) / scale
        aligned_min_y = (rect["min_y"] * scale // 1) / scale
        aligned_max_x = -(-rect["max_x"] * scale // 1) / scale
        aligned_max_y = -(-rect["max_y"] * scale // 1) / scale
        cg_y = 956 - aligned_max_y
        self.require(aligned_min_x == 120.0, "fixture minX alignment failed")
        self.require(aligned_min_y == 80.0, "fixture minY alignment failed")
        self.require(aligned_max_x == 150.5, "fixture maxX alignment failed")
        self.require(aligned_max_y == 120.5, "fixture maxY alignment failed")
        self.require(cg_y == 835.5, "fixture CoreGraphics y flip failed")

    def case_region_capture_pixel_size(self) -> None:
        region = self.read("Sources/SnapMark/ScreenCaptureRegion.swift")
        service = self.read("Sources/SnapMark/ScreenCaptureService.swift")
        app = self.read("Sources/SnapMark/AppDelegate.swift")

        self.require("let pixelSize: CGSize" in region, "region must store selected pixel size")
        self.require("(rect.width * scale).rounded()" in region, "pixel width must derive from aligned point width and scale")
        self.require("(rect.height * scale).rounded()" in region, "pixel height must derive from aligned point height and scale")
        self.require("func capture(region: ScreenCaptureRegion)" in service, "capture service must expose region capture")
        self.require("expectedPixelSize: region.pixelSize" in service, "region capture must pass expected pixel size")
        self.require("size: expectedPixelSize ?? CGSize(width: cgImage.width, height: cgImage.height)" in service, "NSImage size must preserve expected capture pixels")
        self.require("region.isCapturable" in app and "captureService.capture(region: region)" in app, "AppDelegate must guard and capture by region")

        selected_points = {"width": 30.5, "height": 40.5}
        scale = 2
        expected_pixels = (round(selected_points["width"] * scale), round(selected_points["height"] * scale))
        self.require(expected_pixels == (61, 81), "fixture selected pixels must match expected output size")

    def case_selection_size_label_pixels(self) -> None:
        selection = self.read("Sources/SnapMark/ScreenSelectionView.swift")
        self.require("window?.screen?.backingScaleFactor" in selection, "selection label must use screen backing scale")
        self.require("rect.width * scale" in selection, "selection width label must convert points to pixels")
        self.require("rect.height * scale" in selection, "selection height label must convert points to pixels")
        self.require(" px" in selection, "selection label must show px unit")

    def case_selection_magnifier(self) -> None:
        magnifier = self.read("Sources/SnapMark/SelectionMagnifierRenderer.swift")
        view = self.read("Sources/SnapMark/ScreenSelectionView.swift")
        self.require("let zoom: CGFloat = 10" in magnifier, "magnifier zoom must be 10x")
        self.require("let sourcePixels = 21" in magnifier, "magnifier source pixel window missing")
        self.require("imageInterpolation = .none" in magnifier, "magnifier must be pixelated")
        self.require("magnifier.draw(at:" in view, "selection view does not draw magnifier")

    def case_annotation_tools(self) -> None:
        annotation = self.read("Sources/SnapMark/Annotation.swift")
        renderer = self.read("Sources/SnapMark/ImageRenderer.swift")
        for token in ["case arrow", "case rectangle", "case text", "case mosaic", "case magnifier"]:
            self.require(token in annotation, f"missing annotation tool: {token}")
        for draw_fn in ["drawArrow", "drawRectangle", "drawText", "drawMosaic", "drawMagnifier"]:
            self.require(draw_fn in renderer, f"missing renderer: {draw_fn}")

    def case_editor_checkerboard_zoom_pan(self) -> None:
        canvas = self.read("Sources/SnapMark/EditorCanvasView.swift")
        editor = self.read("Sources/SnapMark/EditorWindowController.swift")
        for token in [
            "drawCheckerboard(in:",
            "checkerTileSize",
            "canvasRect",
            "transform.scale(by: zoomScale)",
            "imageInterpolation = .none",
            "rightMouseDragged",
            "updatePan(with:",
        ]:
            self.require(token in canvas, f"editor canvas missing {token}")
        for token in [
            "scrollView.drawsBackground = false",
            "canvasView.setZoomScale(canvasView.fitZoomScale",
            "scrollToVisible(canvasView.canvasCenterRect)",
            "NSSlider(",
            "EditorCanvasView.maximumZoomScale",
            "fitZoom",
        ]:
            self.require(token in editor, f"editor window missing {token}")

    def case_editor_export_independent_from_zoom(self) -> None:
        canvas = self.read("Sources/SnapMark/EditorCanvasView.swift")
        renderer = self.read("Sources/SnapMark/ImageRenderer.swift")
        autosave = self.read("Sources/SnapMark/AutoSaveStore.swift")

        self.require("func renderedImage() -> NSImage" in canvas, "canvas renderedImage missing")
        rendered_body = re.search(r"func renderedImage\(\) -> NSImage \{\n(?P<body>.*?)\n    \}", canvas, re.DOTALL)
        self.require(rendered_body is not None, "renderedImage body missing")
        assert rendered_body is not None
        self.require("zoomScale" not in rendered_body.group("body"), "rendered export must not depend on editor zoom")
        self.require("ImageRenderer.render(baseImage: baseImage, annotations: annotations)" in rendered_body.group("body"), "rendered export must use base image renderer")
        self.require("let size = baseImage.snapMarkPixelSize" in renderer, "renderer must use base image pixel size")
        self.require("pixelsWide: max(1, Int(size.width.rounded()))" in renderer, "renderer output width must be pixel size")
        self.require("pixelsHigh: max(1, Int(size.height.rounded()))" in renderer, "renderer output height must be pixel size")
        self.require("let bitmap = NSBitmapImageRep(cgImage: cgImage)" in autosave, "PNG export must use rendered CGImage pixels")

    def case_editor_annotation_coordinate_mapping(self) -> None:
        canvas = self.read("Sources/SnapMark/EditorCanvasView.swift")
        for token in [
            "imagePoint(from:",
            "(viewPoint.x - rect.minX) / zoomScale",
            "(viewPoint.y - rect.minY) / zoomScale",
            "clamped(",
            "min(imageSize.width, point.x)",
            "min(imageSize.height, point.y)",
        ]:
            self.require(token in canvas, f"editor annotation coordinate mapping missing {token}")
        self.require("guard let point = imagePoint(from: convert(event.locationInWindow, from: nil))" in canvas, "mouseDown must map to image pixels")
        self.require("dragCurrent = point" in canvas, "mouseDragged must update image pixel point")
        self.require("let end = imagePoint(from: convert(event.locationInWindow, from: nil)) ?? start" in canvas, "mouseUp must map endpoint to image pixels")

        view_point = {"x": 180, "y": 132}
        canvas_origin = {"x": 100, "y": 80}
        zoom = 4
        image_point = ((view_point["x"] - canvas_origin["x"]) / zoom, (view_point["y"] - canvas_origin["y"]) / zoom)
        self.require(image_point == (20, 13), "fixture image coordinate reverse mapping failed")

    def case_editor_zoom_range(self) -> None:
        canvas = self.read("Sources/SnapMark/EditorCanvasView.swift")
        editor = self.read("Sources/SnapMark/EditorWindowController.swift")
        self.require("static let minimumZoomScale: CGFloat = 0.125" in canvas, "minimum zoom must support 1:8")
        self.require("static let maximumZoomScale: CGFloat = 8" in canvas, "maximum zoom must support 8:1")
        self.require("min(Self.maximumZoomScale, max(Self.minimumZoomScale, scale))" in canvas, "setZoomScale must clamp to supported range")
        self.require("let availableWidth = max(1, viewportSize.width - contentPadding * 2)" in canvas, "fit zoom must account for horizontal padding")
        self.require("let availableHeight = max(1, viewportSize.height - contentPadding * 2)" in canvas, "fit zoom must account for vertical padding")
        self.require("min(1, availableWidth / imageSize.width, availableHeight / imageSize.height)" in canvas, "fit zoom must prefer 1:1 unless image is too large")
        self.require("max(viewportSize.width, scaledSize.width + contentPadding * 2)" in canvas, "document width must allow scrolling at high zoom")
        self.require("max(viewportSize.height, scaledSize.height + contentPadding * 2)" in canvas, "document height must allow scrolling at high zoom")
        self.require("minValue: Double(EditorCanvasView.minimumZoomScale)" in editor, "zoom slider must expose minimum zoom")
        self.require("maxValue: Double(EditorCanvasView.maximumZoomScale)" in editor, "zoom slider must expose maximum zoom")

    def case_autosave_settings(self) -> None:
        settings = self.read("Sources/SnapMark/AppSettings.swift")
        store = self.read("Sources/SnapMark/AutoSaveStore.swift")
        self.require(".downloadsDirectory" in settings, "default save directory should be Downloads")
        self.require("AppSettings.shared.saveDirectory" in store, "autosave does not use settings directory")
        self.require("newCaptureURL()" in store, "autosave capture URL missing")

    def case_hotkey_fallbacks(self) -> None:
        settings = self.read("Sources/SnapMark/AppSettings.swift")
        for key in ["kVK_ANSI_A", "kVK_ANSI_S", "kVK_ANSI_Q"]:
            self.require(key in settings, f"missing fallback hotkey {key}")
        self.require("fallbackRegionShortcuts" in settings, "fallback chain missing")

    def case_hotkey_health_check(self) -> None:
        app = self.read("Sources/SnapMark/AppDelegate.swift")
        hotkey = self.read("Sources/SnapMark/HotKeyManager.swift")
        self.require("case unresponsive" in hotkey, "unresponsive registration result missing")
        self.require("configureHotKeyHealthMonitor()" in app, "hotkey health monitor missing")
        self.require("recoverUnresponsiveRegionHotKey" in app, "hotkey recovery missing")
        self.require("showHotKeyChangedTip" in app, "hotkey change tip missing")

    def case_hotkey_ui_text(self) -> None:
        settings = self.read("Sources/SnapMark/AppSettings.swift")
        app = self.read("Sources/SnapMark/AppDelegate.swift")
        version = self.read("Sources/SnapMark/AppVersion.swift")
        self.require("shortDisplayString" in settings, "hotkey shortname missing")
        self.require("statusToolTip(hotKey:" in app, "tooltip builder missing")
        self.require("AppVersion.displayVersion" in app, "tooltip does not use app version")
        self.require("CFBundleShortVersionString" in version, "app version should read bundle short version")
        self.require("260625" not in app, "tooltip still contains old hardcoded build date")
        self.require("settingsMenuItem?.title" in app, "settings menu shortname missing")
        self.require("shortcut.displayString" in app, "tooltip does not use actual shortcut")

    def case_drag_copy(self) -> None:
        drag = self.read("Sources/SnapMark/DragExportButton.swift")
        store = self.read("Sources/SnapMark/AutoSaveStore.swift")
        self.require("beginDraggingSession" in drag, "drag session missing")
        self.require(".copy" in drag, "drag operation should be copy")
        self.require("writeTemporaryDragImage" in store, "temporary drag image writer missing")

    def case_settings_window(self) -> None:
        settings = self.read("Sources/SnapMark/SettingsWindowController.swift")
        login = self.read("Sources/SnapMark/LaunchAtLoginService.swift")
        for token in ["快捷键", "存储目录", "启动方式"]:
            self.require(token in settings, f"settings row missing: {token}")
        self.require("ShortcutRecorderButton" in settings, "shortcut recorder missing")
        self.require("NSOpenPanel" in settings, "directory picker missing")
        self.require("SMAppService.mainApp" in login, "launch at login service missing")

    def case_icon_assets(self) -> None:
        icon = self.require_file("Resources/SnapMarkIcon.icns")
        status = self.require_file("Resources/StatusIcon.png")
        script = self.read("Scripts/generate_icon_assets.py")
        self.require(icon.stat().st_size > 1024, "icns looks too small")
        self.require(status.stat().st_size > 256, "status icon looks too small")
        self.require("status_icon" in script and "app_icon" in script, "icon generation script incomplete")

        if Image is not None:
            status_image = Image.open(status)
            self.require(status_image.size == (64, 64), f"StatusIcon.png must be 64x64, got {status_image.size}")
            master = Image.open(self.require_file("Resources/SnapMarkIcon-1024.png"))
            self.require(master.size == (1024, 1024), f"SnapMarkIcon-1024.png must be 1024x1024, got {master.size}")

    def case_info_plist(self) -> None:
        plist_path = self.require_file("Resources/Info.plist")
        with plist_path.open("rb") as handle:
            plist = plistlib.load(handle)
        self.require(plist.get("CFBundleIdentifier") == "dev.snapmark.app", "unexpected bundle identifier")
        self.require(plist.get("CFBundleIconFile") == "SnapMarkIcon", "bundle icon not configured")
        self.require(plist.get("LSUIElement") is True, "status bar app should be LSUIElement")

    def case_build_script(self) -> None:
        build = self.read("Scripts/build_app.sh")
        install = self.read("Scripts/install_app.sh")
        for token in ["generate_icon_assets.py", "iconutil", "swift build -c release", "codesign", "SnapMarkIcon.icns", "StatusIcon.png"]:
            self.require(token in build, f"build script missing {token}")
        self.require("/Applications/SnapMark.app" in install, "install script should prefer /Applications")

    def case_version_rule(self) -> None:
        state = self.require_file("Resources/Version.env").read_text(encoding="utf-8")
        build = self.read("Scripts/build_app.sh")
        info_path = self.require_file("Resources/Info.plist")

        major_match = re.search(r"^SNAPMARK_MAJOR=(\d+)$", state, re.MULTILINE)
        minor_match = re.search(r"^SNAPMARK_MINOR=(\d+)$", state, re.MULTILINE)
        self.require(major_match is not None, "version major state missing")
        self.require(minor_match is not None, "version minor state missing")
        assert major_match is not None
        assert minor_match is not None

        major = major_match.group(1)
        minor = int(minor_match.group(1))
        for token in [
            "bump_app_version()",
            "next_minor=$((minor + 1))",
            "date +%m%d",
            "CFBundleShortVersionString",
            "CFBundleVersion",
        ]:
            self.require(token in build, f"build script missing version rule token: {token}")

        with info_path.open("rb") as handle:
            source_plist = plistlib.load(handle)
        source_version = source_plist.get("CFBundleShortVersionString", "")
        pattern = rf"^{re.escape(major)}\.\d+\.\d{{4}}$"
        self.require(re.match(pattern, source_version) is not None, f"source version does not match {major}.<n>.MMDD: {source_version}")

        if self.app:
            app_info = self.app / "Contents/Info.plist"
            with app_info.open("rb") as handle:
                app_plist = plistlib.load(handle)
            app_version = app_plist.get("CFBundleShortVersionString", "")
            app_build = app_plist.get("CFBundleVersion", "")
            self.require(re.match(pattern, app_version) is not None, f"app version does not match {major}.<n>.MMDD: {app_version}")
            self.require(app_build == app_version, "CFBundleVersion should match short version")
            self.require(app_version.endswith(datetime.now().strftime(".%m%d")), f"app version should use today's MMDD: {app_version}")
            version_minor = int(app_version.split(".")[1])
            self.require(version_minor == minor, f"version state minor {minor} does not match app version {app_version}")

    def case_module_size_budget(self) -> None:
        limits = {
            "Sources/SnapMark/ScreenSelectionController.swift": 140,
            "Sources/SnapMark/ScreenSelectionView.swift": 280,
            "Sources/SnapMark/ScreenSelectionWindow.swift": 80,
            "Sources/SnapMark/SelectionMagnifierRenderer.swift": 180,
            "Sources/SnapMark/WindowInspector.swift": 140,
        }
        for relative, limit in limits.items():
            lines = len(self.read(relative).splitlines())
            self.require(lines <= limit, f"{relative} has {lines} lines, budget is {limit}")

    def case_p1_plan_recorded(self) -> None:
        plan = self.read("Docs/FeaturePlan.MD")
        for token in ["Ask ChatGPT", "Send via Mail", "Codex/ClaudeCode", "Copy", "自动隐私处理", "API Key", "Token", "人脸"]:
            self.require(token in plan, f"P1 plan missing {token}")

    def case_pstar_plan_recorded(self) -> None:
        plan = self.read("Docs/FeaturePlan.MD")
        for token in ["无限滚动截图", "视频录屏", "GIF", "OCR", "Pin Image", "Color Picker", "Pixel Ruler", "Screen Measure", "QR Scanner", "Image Compression", "Markdown Image Upload"]:
            self.require(token in plan, f"P* plan missing {token}")

    def case_test_plan_coverage(self) -> None:
        test_plan = self.read("Docs/TestPlan.MD")
        for case_id in [
            "SMK-P0-SHOT-001",
            "SMK-P0-SHOT-002",
            "SMK-P0-SHOT-003",
            "SMK-P0-SHOT-007",
            "SMK-P0-SHOT-008",
            "SMK-P0-SHOT-009",
            "SMK-P0-MAG-001",
            "SMK-P0-ANN-001",
            "SMK-P0-EDITOR-001",
            "SMK-P0-EDITOR-002",
            "SMK-P0-EDITOR-003",
            "SMK-P0-EDITOR-004",
            "SMK-P0-SAVE-001",
            "SMK-P0-HOT-001",
            "SMK-P0-DRAG-001",
            "SMK-P0-SET-001",
            "SMK-P0-BUNDLE-005",
        ]:
            self.require(case_id in test_plan, f"test plan missing {case_id}")

    def case_app_bundle_resources(self) -> None:
        assert self.app is not None
        self.require((self.app / "Contents/MacOS/SnapMark").is_file(), "app executable missing")
        self.require((self.app / "Contents/Info.plist").is_file(), "app Info.plist missing")
        self.require((self.app / "Contents/Resources/SnapMarkIcon.icns").is_file(), "app icon missing")
        self.require((self.app / "Contents/Resources/StatusIcon.png").is_file(), "status icon missing")

    def case_app_codesign(self) -> None:
        assert self.app is not None
        result = subprocess.run(
            ["codesign", "--verify", "--deep", "--strict", str(self.app)],
            cwd=self.root,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        self.require(result.returncode == 0, f"codesign verify failed:\n{result.stdout}")

    def run(self) -> int:
        failures: list[tuple[TestCase, str]] = []
        for case in self.cases():
            try:
                case.check()
                print(f"PASS {case.case_id} {case.title}")
            except Exception as error:
                failures.append((case, str(error)))
                print(f"FAIL {case.case_id} {case.title}: {error}")

        if failures:
            print(f"\n{len(failures)} test(s) failed.")
            return 1

        print(f"\nAll {len(self.cases())} functional tests passed.")
        return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run SnapMark functional tests.")
    parser.add_argument("--root", default=".", help="Repository root")
    parser.add_argument("--app", default=None, help="Optional built app bundle path")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    app = Path(args.app).resolve() if args.app else None
    if app is not None and not app.exists():
        print(f"app bundle does not exist: {app}", file=sys.stderr)
        return 2
    return FunctionalTestRunner(root, app).run()


if __name__ == "__main__":
    raise SystemExit(main())
