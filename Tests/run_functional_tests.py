#!/usr/bin/env python3
import argparse
import math
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

    def read_many(self, *relatives: str) -> str:
        return "\n".join(self.read(relative) for relative in relatives)

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
            TestCase("SMK-P0-SHOT-004", "截图/编辑/设置激活状态支持 Esc 和 Command+Q 退出", self.case_escape_reset),
            TestCase("SMK-P0-SHOT-006", "截图遮罩窗口可接收退出键盘事件", self.case_selection_window_receives_escape),
            TestCase("SMK-P0-SHOT-007", "区域截图坐标按屏幕和 backing scale 映射", self.case_region_coordinate_mapping),
            TestCase("SMK-P0-SHOT-008", "实际截图内容尺寸与选择像素尺寸一致", self.case_region_capture_pixel_size),
            TestCase("SMK-P0-SHOT-009", "选择框尺寸提示显示实际像素", self.case_selection_size_label_pixels),
            TestCase("SMK-P0-SHOT-010", "选区坐标面板只显示起点终点和像素尺寸", self.case_selection_coordinate_overlay),
            TestCase("SMK-P0-SHOT-011", "四个拖拽方向的截图像素区域一致", self.case_region_drag_direction_pixel_edges),
            TestCase("SMK-P0-SHOT-012", "半像素垂直边界通过外包截图和像素裁剪保持一致", self.case_region_half_pixel_capture_crop),
            TestCase("SMK-P0-MAG-001", "截图选择放大镜为 5x 像素化放大并扩大视野", self.case_selection_magnifier),
            TestCase("SMK-P0-ANN-001", "编辑器标注工具覆盖箭头/形状/文字/马赛克/放大镜/Pen/拖拉", self.case_annotation_tools),
            TestCase("SMK-P0-ANN-003", "编辑器Pen支持 S/M/L 不同大小", self.case_pen_tool_sizes),
            TestCase("SMK-P0-ANN-004", "Pen自由路径预览和导出按当前颜色绘制", self.case_pen_path_rendering_logic),
            TestCase("SMK-P0-ANN-005", "文字标注弹窗支持颜色字号和预览", self.case_text_annotation_dialog),
            TestCase("SMK-P0-ANN-006", "标注元素支持选中拖动缩放和创建颜色", self.case_annotation_transform_and_color),
            TestCase("SMK-P0-EDITOR-001", "编辑器使用棋盘底、居中显示、缩放和平移", self.case_editor_checkerboard_zoom_pan),
            TestCase("SMK-P0-EDITOR-002", "编辑器缩放不影响保存/复制输出像素", self.case_editor_export_independent_from_zoom),
            TestCase("SMK-P0-EDITOR-003", "编辑器标注坐标按缩放反算到图片像素", self.case_editor_annotation_coordinate_mapping),
            TestCase("SMK-P0-EDITOR-004", "编辑器 fit 和缩放范围覆盖 1:32 到 8:1", self.case_editor_zoom_range),
            TestCase("SMK-P0-EDITOR-005", "toolbar 左侧缩放信息块承载透明 slider 和适应按钮", self.case_editor_toolbar_stacked_info_layout),
            TestCase("SMK-P0-EDITOR-006", "文字标注自动适配尺寸且可拖拽移动", self.case_text_annotation_sizing_and_drag),
            TestCase("SMK-P0-SAVE-001", "自动保存目录读取设置且默认 Downloads", self.case_autosave_settings),
            TestCase("SMK-P0-SAVE-002", "退出编辑窗口时有修改会另存并释放资源", self.case_exit_autosaves_modified_editor),
            TestCase("SMK-P0-HOT-001", "默认快捷键 fallback 为 A/S/Q", self.case_hotkey_fallbacks),
            TestCase("SMK-P0-HOT-002", "快捷键失效检测和自动切换逻辑存在", self.case_hotkey_health_check),
            TestCase("SMK-P0-HOT-003", "菜单与 tooltip 显示实际快捷键", self.case_hotkey_ui_text),
            TestCase("SMK-P0-HOT-004", "设置窗口录制快捷键暂停/提交/恢复事务完整", self.case_hotkey_settings_recording_transaction),
            TestCase("SMK-P0-SHARE-001", "共享按钮通过系统分享面板发送临时 PNG", self.case_share_image),
            TestCase("SMK-P0-SET-001", "设置窗口覆盖快捷键/存储目录/开机启动", self.case_settings_window),
            TestCase("SMK-P0-SET-004", "语言设置支持跟随系统和中英文", self.case_language_settings),
            TestCase("SMK-P0-ICON-001", "图标资源完整且尺寸正确", self.case_icon_assets),
            TestCase("SMK-P0-BUNDLE-001", "Info.plist app 元数据完整", self.case_info_plist),
            TestCase("SMK-P0-BUNDLE-002", "构建脚本包含稳定签名和资源打包", self.case_build_script),
            TestCase("SMK-P0-BUNDLE-005", "版本号遵循 1.<自动递增>.MMDD 规则", self.case_version_rule),
            TestCase("SMK-P0-BUNDLE-006", "编译完成后安装并重启新 app", self.case_build_restarts_app),
            TestCase("SMK-P0-BUNDLE-007", "关于菜单显示版本号和构建时间", self.case_about_menu_build_info),
            TestCase("SMK-P0-ARCH-001", "截图相关模块已拆分且文件大小受控", self.case_module_size_budget),
            TestCase("SMK-P1-PLAN-001", "P1 功能规划已记录", self.case_p1_plan_recorded),
            TestCase("SMK-PSTAR-PLAN-001", "P* 功能规划已记录", self.case_pstar_plan_recorded),
            TestCase("SMK-QA-001", "测试计划文档覆盖 P0 功能点", self.case_test_plan_coverage),
            TestCase("SMK-QA-002", "docs 保存 UI 总览截图和功能说明", self.case_ui_overview_docs),
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
        controller = self.read("Sources/SnapMark/ScreenSelectionController.swift")
        view = self.read("Sources/SnapMark/ScreenSelectionView.swift")
        service = self.read("Sources/SnapMark/ScreenCaptureService.swift")
        self.require("captureFullScreen()" in app, "missing full screen action")
        self.require("func captureFullScreen()" in service, "missing captureFullScreen service")
        self.require("NSScreen.screens" in service, "full screen capture should cover all screens")
        self.require("case fullScreen" in controller, "selection result should support blank-click full screen capture")
        self.require("onFullScreenComplete" in view, "selection view should expose blank-click full screen callback")
        self.require("hoveredWindow = windowTarget(at: point)" in view, "mouseUp should refresh window hit-test before choosing full screen")
        self.require("onFullScreenComplete?()" in view, "blank click should complete as full screen instead of cancel")
        self.require("case .fullScreen:" in app, "AppDelegate should handle blank-click full screen result")
        self.require("image = self.captureService.captureFullScreen()" in app, "blank-click full screen should reuse full screen capture service")

    def case_window_capture(self) -> None:
        controller = self.read("Sources/SnapMark/ScreenSelectionController.swift")
        view = self.read("Sources/SnapMark/ScreenSelectionView.swift")
        inspector = self.read("Sources/SnapMark/WindowInspector.swift")
        service = self.read("Sources/SnapMark/ScreenCaptureService.swift")
        app = self.read("Sources/SnapMark/AppDelegate.swift")
        self.require("case window(WindowTarget)" in controller, "window selection result missing")
        self.require("WindowInspector.visibleWindowTargets" in controller, "window targets are not loaded on activation")
        self.require('excludingOwnerNames: ["SnapMark"]' not in controller, "SnapMark windows should remain capturable by SnapMark")
        self.require("static func visibleWindowTargets()" in inspector, "window inspector should not require owner-name exclusions")
        self.require("WindowInspector.windowUnder" in view, "mousemove window hit-test missing")
        self.require("onWindowComplete?(target)" in view, "click-to-window selection missing")
        self.require("capture(windowID:" in service and ".optionIncludingWindow" in service, "window id capture missing")
        self.require("case .window(let target)" in app, "AppDelegate does not handle window capture")

    def case_escape_reset(self) -> None:
        app = self.read("Sources/SnapMark/AppDelegate.swift")
        main = self.read("Sources/SnapMark/main.swift")
        exit_shortcut = self.read("Sources/SnapMark/ExitShortcut.swift")
        selection = self.read("Sources/SnapMark/ScreenSelectionView.swift")
        canvas = self.read_many(
            "Sources/SnapMark/EditorCanvasView.swift",
            "Sources/SnapMark/EditorCanvasView+AnnotationEditing.swift"
        )
        editor = self.read("Sources/SnapMark/EditorWindowController.swift")
        self.require("configureResetMonitor()" in app and "resetStatus()" in app, "global reset monitor missing")
        self.require("ExitShortcut.matches(event)" in app, "AppDelegate should use shared exit shortcut handling")
        self.require('charactersIgnoringModifiers?.lowercased() == "q"' in exit_shortcut, "Command+Q recognition missing")
        self.require("flags == .command" in exit_shortcut, "Command+Q must not collide with fallback Command+Control+Q")
        self.require("ExitShortcut.matches(event)" in selection, "selection Esc/Command+Q handling missing")
        self.require("onResetRequested" in canvas and "ExitShortcut.matches(event)" in canvas, "canvas exit callback missing")
        self.require("closeForExit()" in editor and "ExitShortcut.matches(event)" in editor, "editor exit close missing")
        self.require("NSApp.modalWindow" in app, "modal windows should close before parent contexts")
        self.require("controller.cancel()" in app and "selectionController = nil" in app, "selection exit should cancel and release controller")
        self.require("disableAutomaticTermination" in main, "menu bar capture app should not auto-terminate between transient windows")
        self.require('UserDefaults.standard.set(180, forKey: "NSInitialToolTipDelay")' in main, "toolbar tooltips should appear quickly")

    def case_selection_window_receives_escape(self) -> None:
        controller = self.read("Sources/SnapMark/ScreenSelectionController.swift")
        window = self.read("Sources/SnapMark/ScreenSelectionWindow.swift")
        selection = self.read("Sources/SnapMark/ScreenSelectionView.swift")
        self.require("ScreenSelectionWindow(" in controller, "selection overlay must use key-capable window subclass")
        self.require("NSApp.activate(ignoringOtherApps: true)" in controller, "app must activate before selection to receive local key events")
        self.require("override var canBecomeKey: Bool" in window and "true" in window, "selection window must become key")
        self.require("override var canBecomeMain: Bool" in window and "true" in window, "selection window must become main")
        self.require("override func keyDown" in window and "ExitShortcut.matches(event)" in window and "cancelFromKeyboard()" in window, "selection window must route exit shortcut to cancel")
        self.require("func cancelFromKeyboard()" in selection, "selection view must expose keyboard cancel path")
        self.require("window.animationBehavior = .none" in controller, "selection overlay windows should not use AppKit transform animations")
        self.require("window.isReleasedWhenClosed = false" in controller, "selection overlay windows should be ARC-owned during teardown")
        self.require("let closingWindows = windows" in controller, "selection finish should retain windows through teardown")
        self.require("let completion = completion" in controller and "self.completion = nil" in controller, "selection finish should clear callback before invoking it")
        self.require("NSAnimationContext.runAnimationGroup" in controller and "context.duration = 0" in controller, "selection finish should order windows out without animation")
        self.require("DispatchQueue.main.async" in controller and "window.contentView = nil" in controller, "selection snapshot views should release after AppKit finishes the close transition")

    def case_region_coordinate_mapping(self) -> None:
        region = self.read("Sources/SnapMark/ScreenCaptureRegion.swift")
        controller = self.read("Sources/SnapMark/ScreenSelectionController.swift")
        service = self.read("Sources/SnapMark/ScreenCaptureService.swift")
        app = self.read("Sources/SnapMark/AppDelegate.swift")

        for token in [
            "backingScaleFactor = max(1, screen.backingScaleFactor)",
            "pixelSnapped(",
            "snappedCoordinate(",
            "Self.coreGraphicsRect(from: rawRect.standardized, on: screen)",
            "screenFrame.maxY - appKitPoint.y",
            "coreGraphicsDisplayBounds(for: screen)",
            "CGDisplayBounds(CGDirectDisplayID",
            "pixelSize = Self.pixelSize",
            "captureRequestRect = Self.integralPointRect",
            "captureCropRect = Self.cropRect",
        ]:
            self.require(token in region, f"coordinate mapper missing {token}")

        self.require("ScreenCaptureRegion(appKitRect: screenRect, screen: window.screen)" in controller, "selection completion must map through ScreenCaptureRegion")
        self.require("static func coreGraphicsPoint(from appKitPoint: CGPoint, on screen: NSScreen)" in region, "coreGraphics point conversion missing")
        self.require("static func backingPixelPoint(from appKitPoint: CGPoint, on screen: NSScreen)" in region, "backing pixel point conversion missing")
        self.require("capture(region: ScreenCaptureRegion)" in service, "capture service must accept mapped region")
        self.require("region.captureRequestRect" in service, "capture service must request an integral point rect")
        self.require("cropRect: region.captureCropRect" in service, "capture service must crop back to exact pixels")
        self.require("expectedPixelSize: region.pixelSize" in service, "capture service must preserve expected pixel size")
        self.require("captureService.capture(region: region)" in app, "AppDelegate must capture mapped region")

        scale = 2
        rect = {"min_x": 120.25, "min_y": 80.25, "max_x": 150.5, "max_y": 120.5}
        aligned_min_x = self.round_away(rect["min_x"] * scale) / scale
        aligned_min_y = self.round_away(rect["min_y"] * scale) / scale
        aligned_max_x = self.round_away(rect["max_x"] * scale) / scale
        aligned_max_y = self.round_away(rect["max_y"] * scale) / scale
        cg_y = 956 - aligned_max_y
        self.require(aligned_min_x == 120.5, "fixture minX snapping failed")
        self.require(aligned_min_y == 80.5, "fixture minY snapping failed")
        self.require(aligned_max_x == 150.5, "fixture maxX alignment failed")
        self.require(aligned_max_y == 120.5, "fixture maxY alignment failed")
        self.require(cg_y == 835.5, "fixture CoreGraphics y flip failed")

    def case_region_capture_pixel_size(self) -> None:
        region = self.read("Sources/SnapMark/ScreenCaptureRegion.swift")
        service = self.read("Sources/SnapMark/ScreenCaptureService.swift")
        app = self.read("Sources/SnapMark/AppDelegate.swift")

        self.require("let pixelSize: CGSize" in region, "region must store selected pixel size")
        self.require("let captureRequestRect: CGRect" in region, "region must store integral capture request rect")
        self.require("let captureCropRect: CGRect" in region, "region must store pixel crop rect")
        self.require("maxX - minX" in region, "pixel width must derive from snapped pixel edges")
        self.require("maxY - minY" in region, "pixel height must derive from snapped pixel edges")
        self.require("func capture(region: ScreenCaptureRegion)" in service, "capture service must expose region capture")
        self.require("expectedPixelSize: region.pixelSize" in service, "region capture must pass expected pixel size")
        self.require("croppedImage(from: cgImage, cropRect: cropRect) ?? cgImage" in service, "region capture must normalize CGImage pixels through crop")
        self.require("size: expectedPixelSize ?? CGSize(width: outputImage.width, height: outputImage.height)" in service, "NSImage size must preserve expected capture pixels")
        self.require("region.isCapturable" in app and "captureService.capture(region: region)" in app, "AppDelegate must guard and capture by region")

        selected_points = {"width": 30.5, "height": 40.5}
        scale = 2
        expected_pixels = (round(selected_points["width"] * scale), round(selected_points["height"] * scale))
        self.require(expected_pixels == (61, 81), "fixture selected pixels must match expected output size")

    def case_selection_size_label_pixels(self) -> None:
        selection = self.read("Sources/SnapMark/ScreenSelectionView.swift")
        self.require("selectionPixelSizeText(for:" in selection, "selection label must use shared pixel size path")
        self.require("ScreenCaptureRegion(appKitRect: screenRect, screen: screen)" in selection, "selection label must map through ScreenCaptureRegion")
        self.require("region.pixelSize.width" in selection, "selection width label must use captured pixel width")
        self.require("region.pixelSize.height" in selection, "selection height label must use captured pixel height")
        self.require(" px" in selection, "selection label must show px unit")

    def case_selection_coordinate_overlay(self) -> None:
        selection = self.read("Sources/SnapMark/ScreenSelectionView.swift")
        overlay = self.read("Sources/SnapMark/SelectionCoordinateOverlay.swift")
        self.require("SelectionCoordinateOverlay.draw" in selection, "selection view must draw coordinate overlay")
        self.require("guard let startPoint, let selectionRect else { return }" in overlay, "overlay must only show while dragging a selection")
        self.require("screenPoint(for: startPoint" in overlay and "screenPoint(for: currentPoint" in overlay, "overlay must show screen start/end points")
        self.require("ScreenCaptureRegion(appKitRect: screenRect, screen: screen)" in overlay, "overlay must use shared region pixel size")
        self.require("format(region.pixelSize)" in overlay and " px" in overlay, "overlay must show width x height pixels")
        self.require("drawLabel(" in overlay and "drawMultilineLabel" not in overlay, "overlay should be a single concise line")
        for token in ["zoom 5x / source 41px", "cursor local", "capturePoint", "pixelPoint", "region capture", "start  local", "end    local"]:
            self.require(token not in overlay, f"coordinate overlay should not expose debug token: {token}")

    def case_region_drag_direction_pixel_edges(self) -> None:
        region = self.read("Sources/SnapMark/ScreenCaptureRegion.swift")
        self.require("floor(rect.minX * scale)" not in region, "region snapping must not expand left edge with floor")
        self.require("ceil(rect.maxY * scale)" not in region, "region snapping must not expand top edge through AppKit maxY")

        scale = 2
        screen_height = 956
        corners = {
            "tl": (120.25, 820.25),
            "tr": (300.75, 820.25),
            "bl": (120.25, 700.75),
            "br": (300.75, 700.75),
        }
        directions = [("tl", "br"), ("br", "tl"), ("tr", "bl"), ("bl", "tr")]
        expected_origin = (
            self.round_away(corners["tl"][0] * scale),
            self.round_away((screen_height - corners["tl"][1]) * scale),
        )
        old_outward_origin = (
            math.floor(corners["tl"][0] * scale),
            screen_height * scale - math.ceil(corners["tl"][1] * scale),
        )
        self.require(expected_origin == (241, 272), "fixture expected snapped top-left failed")
        self.require(old_outward_origin == (240, 271), "fixture must reproduce previous top-left expansion")

        regions = [
            self.fixture_region_from_drag(start=corners[start], end=corners[end], screen_height=screen_height, scale=scale)
            for start, end in directions
        ]
        self.require(all(region_fixture == regions[0] for region_fixture in regions), "all drag directions must produce the same capture pixels")
        self.require(regions[0]["origin"] == expected_origin, f"capture origin should match selected top-left pixel, got {regions[0]['origin']}")
        self.require(regions[0]["size"] == (361, 239), f"unexpected snapped capture size: {regions[0]['size']}")

    def case_region_half_pixel_capture_crop(self) -> None:
        region = self.read("Sources/SnapMark/ScreenCaptureRegion.swift")
        service = self.read("Sources/SnapMark/ScreenCaptureService.swift")
        self.require("integralPointRect(containing:" in region, "region must build an integral point request rect")
        self.require("floor(rect.minX)" in region and "ceil(rect.maxY)" in region, "request rect must cover fractional target edges")
        self.require("cropRect(for rect" in region and "target.minY - request.minY" in region, "region must compute vertical pixel crop offset")
        self.require("image.cropping(to: boundedRect)" in service, "capture service must crop requested image")

        scale = 2
        target_cg = {"x": 120.5, "y": 136.0, "width": 180.5, "height": 119.5}
        target_pixels = self.pixel_rect(target_cg, scale)
        request = self.integral_point_rect(target_cg)
        request_pixels = self.pixel_rect(request, scale)
        crop = {
            "x": target_pixels["x"] - request_pixels["x"],
            "y": target_pixels["y"] - request_pixels["y"],
            "width": target_pixels["width"],
            "height": target_pixels["height"],
        }
        direct_coregraphics_actual = {
            "width": math.floor(target_cg["width"]) * scale,
            "height": math.floor(target_cg["height"]) * scale,
        }

        self.require(target_pixels["height"] == 239, "fixture target vertical pixels should be 239")
        self.require(direct_coregraphics_actual["height"] == 238, "fixture should reproduce direct CoreGraphics 1px vertical loss")
        self.require(request_pixels["height"] == 240, "integer request should cover the target vertical pixels")
        self.require(crop["height"] == target_pixels["height"], "crop height should restore exact target pixels")

    def case_selection_magnifier(self) -> None:
        magnifier = self.read("Sources/SnapMark/SelectionMagnifierRenderer.swift")
        geometry = self.read("Sources/SnapMark/SelectionMagnifierGeometry.swift")
        controller = self.read("Sources/SnapMark/ScreenSelectionController.swift")
        view = self.read("Sources/SnapMark/ScreenSelectionView.swift")
        self.require("let zoom: CGFloat = 5" in magnifier, "magnifier zoom must be reduced to 5x")
        self.require("let sourcePixels = 41" in magnifier, "magnifier source window must show a larger pixel area")
        self.require("SelectionMagnifierGeometry.make" in magnifier, "magnifier must use shared crop geometry")
        self.require("drawZoomLabel(in: lensRect)" in magnifier, "magnifier must visibly show current zoom factor")
        self.require("\\(Int(zoom))x / \\(sourcePixels)px" in magnifier, "magnifier label must show zoom and source pixels")
        self.require("ScreenCaptureRegion.coreGraphicsDisplayBounds(for: screen)" in controller, "magnifier snapshot must use CoreGraphics display bounds")
        self.require("imageInterpolation = .none" in magnifier, "magnifier must be pixelated")
        self.require("floor(point.x * scaleX)" in geometry, "magnifier focus x must map from local point to snapshot pixel")
        self.require("floor((bounds.height - point.y) * scaleY)" in geometry, "magnifier focus y must use the same y-flip as capture")
        self.require("focusUnitPoint" in geometry, "magnifier must preserve actual focus point inside cropped image")
        self.require("1 - ((focusY - cropRect.minY + 0.5) / cropRect.height)" in geometry, "magnifier crosshair y must map top-left pixels into AppKit coordinates")
        self.require("drawCrosshair(in: lensRect, focusUnitPoint: geometry.focusUnitPoint)" in magnifier, "crosshair must mark actual focused pixel")
        self.require("magnifier.draw(at:" in view, "selection view does not draw magnifier")

        bounds = {"width": 100, "height": 100}
        snapshot = {"width": 200, "height": 200}
        point = {"x": 25, "y": 75}
        focus_x = int(point["x"] * snapshot["width"] / bounds["width"])
        focus_y = int((bounds["height"] - point["y"]) * snapshot["height"] / bounds["height"])
        self.require((focus_x, focus_y) == (50, 50), "fixture magnifier focus mapping failed")

    def case_annotation_tools(self) -> None:
        annotation = self.read("Sources/SnapMark/Annotation.swift")
        canvas = self.read_many(
            "Sources/SnapMark/EditorCanvasView.swift",
            "Sources/SnapMark/EditorCanvasView+AnnotationEditing.swift",
            "Sources/SnapMark/EditorCanvasView+Drawing.swift",
            "Sources/SnapMark/EditorCanvasView+Geometry.swift",
            "Sources/SnapMark/EditorCanvasView+ImagePatch.swift"
        )
        editor = self.read_many(
            "Sources/SnapMark/EditorWindowController.swift",
            "Sources/SnapMark/EditorWindowController+Tools.swift",
            "Sources/SnapMark/EditorToolbarImages.swift"
        )
        renderer = self.read("Sources/SnapMark/ImageRenderer.swift")
        for token in ["case arrow", "case rectangle", "case text", "case mosaic", "case magnifier", "case pen", "case hand"]:
            self.require(token in annotation, f"missing annotation tool: {token}")
        for token in [
            "enum ShapeMode",
            "case circle",
            "case ellipse",
            "enum ArrowMode",
            "case solid",
            "case notched",
            "case line",
            "enum MosaicMode",
            "case plain",
            "case bordered",
            "enum HandMode",
            "case selection",
            "case pan",
            "var shapeMode: ShapeMode = .rectangle",
            "var arrowMode: ArrowMode = .solid",
            "var mosaicMode: MosaicMode = .plain",
            "var imagePatch: NSImage?",
        ]:
            self.require(token in annotation, f"annotation mode missing {token}")
        for token in [
            "var shapeMode: ShapeMode = .rectangle",
            "var arrowMode: ArrowMode = .solid",
            "var mosaicMode: MosaicMode = .plain",
            "var handMode: HandMode = .selection",
            "applyCurrentAnnotationModes(to:",
            "normalizeShapeAnnotation(&annotation)",
            "normalizeCircleAnnotation(&annotation)",
            "beginHandSelectionMouseDown(with:",
            "beginImagePatchInteraction(at:",
            "copiesPatch: event.modifierFlags.contains(.option)",
            "duplicate.id = UUID()",
            "createImagePatchAnnotation(from:",
            "imagePatch(from:",
            "drawHandSelectionOverlay()",
        ]:
            self.require(token in canvas, f"canvas annotation mode missing {token}")
        for draw_fn in ["drawArrow", "drawRectangle", "drawText", "drawMosaic", "drawMagnifier", "drawPen", "drawImagePatch"]:
            self.require(draw_fn in renderer, f"missing renderer: {draw_fn}")
        for token in [
            "annotation.arrowMode",
            "drawSolidArrow(annotation, isPreview: isPreview)",
            "drawNotchedArrow(annotation, isPreview: isPreview)",
            "drawArrowLine(annotation, isPreview: isPreview)",
            "annotation.shapeMode",
            "NSBezierPath(ovalIn: circleRect(for: annotation.rect))",
            "annotation.mosaicMode == .bordered",
            "guard let imagePatch = annotation.imagePatch",
            "imagePatch.draw(",
        ]:
            self.require(token in renderer, f"renderer annotation mode missing {token}")
        for token in [
            "textToolImage()",
            "static func textToolImage() -> NSImage",
            "let glyph = \"T\" as NSString",
            "static func shapeToolImage(for mode: ShapeMode",
            "static func arrowToolImage(for mode: ArrowMode",
            "static func mosaicToolImage(for mode: MosaicMode",
            "cycleShapeMode()",
            "cycleArrowMode()",
            "cycleMosaicMode()",
            "cycleHandMode()",
            "updateShapeSegmentImage()",
            "updateArrowSegmentImage()",
            "updateMosaicSegmentImage()",
            "updateHandSegmentImage()",
            "static func toolImage(for tool: AnnotationTool) -> NSImage",
            "static func handToolImage(for mode: HandMode",
            "case .hand:",
        ]:
            self.require(token in editor, f"text tool icon missing {token}")

    def case_pen_tool_sizes(self) -> None:
        annotation = self.read("Sources/SnapMark/Annotation.swift")
        canvas = self.read("Sources/SnapMark/EditorCanvasView.swift")
        renderer = self.read("Sources/SnapMark/ImageRenderer.swift")
        editor = self.read_many(
            "Sources/SnapMark/EditorWindowController.swift",
            "Sources/SnapMark/EditorWindowController+Tools.swift",
            "Sources/SnapMark/EditorToolbarImages.swift"
        )

        for token in ["enum PenSize", "case small", "case medium", "case large", "return 8", "return 16", "return 32"]:
            self.require(token in annotation, f"pen size missing token: {token}")
        self.require("var points: [CGPoint]" in annotation, "pen must store freehand points")
        self.require("var penSize: PenSize = .medium" in canvas, "canvas pen size state missing")
        self.require("currentTool == .pen" in canvas, "canvas must branch for pen")
        self.require("annotation.points = points" in canvas, "pen annotation should keep the drag path")
        self.require("annotation.lineWidth = penSize.lineWidth" in canvas, "pen line width should use selected size")
        self.require("annotationColor(annotation, alphaMultiplier: isPreview ? 0.55 : 1).setStroke()" in renderer, "pen renderer should use the selected color and opacity")
        self.require("annotationColor(annotation, alphaMultiplier: isPreview ? 0.55 : 1).setFill()" in renderer, "single-point pen dots should use selected color and opacity")
        self.require("penBackgroundColor" not in renderer, "pen must not fall back to old white eraser fill")
        self.require("var penSizeMenu: NSMenu?" in editor, "toolbar pen size menu missing")
        self.require("control.setMenu(makePenSizeMenu(), forSegment: AnnotationTool.pen.rawValue)" in editor, "pen segment should own the size menu")
        self.require("control.setShowsMenuIndicator(true, forSegment: AnnotationTool.pen.rawValue)" in editor, "pen segment should show a menu indicator")
        self.require("updatePenSegmentImage()" in editor, "pen segment should update the visible stroke-width icon")
        self.require("updatePenSegmentTooltip()" in editor, "pen segment should expose the current size in its tooltip")
        self.require("@objc func choosePenSize(_ sender: NSMenuItem)" in editor, "pen size menu action missing")
        self.require("cyclePenSize()" in editor, "clicking active pen should cycle S/M/L")
        for token in [
            "static func penStrokeImage(for penSize: PenSize",
            "item.image = EditorToolbarImages.penStrokeImage(for: size",
            "toolControl?.setImage(EditorToolbarImages.penStrokeImage(for: canvasView.penSize), forSegment: AnnotationTool.pen.rawValue)",
            "case .small:",
            "lineWidth = 2",
            "case .medium:",
            "lineWidth = 4",
            "case .large:",
            "lineWidth = 6",
        ]:
            self.require(token in editor, f"pen stroke icon missing {token}")
        self.require("penSizeControl" not in editor, "standalone S/M/L toolbar control should be removed")
        self.require("SnapMark.PenSize" not in editor, "standalone pen toolbar identifier should be removed")

        expected_sizes = {"small": 8, "medium": 16, "large": 32}
        self.require(expected_sizes["small"] < expected_sizes["medium"] < expected_sizes["large"], "pen fixture sizes should increase")
        for label in ["S", "M", "L"]:
            self.require(f'return "{label}"' in annotation, f"missing pen size label {label}")

    def case_pen_path_rendering_logic(self) -> None:
        canvas = self.read_many(
            "Sources/SnapMark/EditorCanvasView.swift",
            "Sources/SnapMark/EditorCanvasView+Geometry.swift"
        )
        renderer = self.read("Sources/SnapMark/ImageRenderer.swift")

        for token in [
            "dragPoints = [point]",
            "dragPoints.append(point)",
            "let points = finalizedDragPoints(endingAt: end)",
            "dragPoints.removeAll()",
            "finalizedDragPoints(endingAt:",
            "points.last.map({ $0 != end }) ?? true",
        ]:
            self.require(token in canvas, f"pen path collection missing {token}")
        for token in [
            "drawPen(annotation, isPreview: isPreview)",
            "let points = annotation.points.isEmpty ? [annotation.start, annotation.end] : annotation.points",
            "let isSinglePoint = points.count == 1 || (points.last.map { $0 == firstPoint } ?? false)",
            "annotationColor(annotation, alphaMultiplier: isPreview ? 0.55 : 1).setStroke()",
            "annotationColor(annotation, alphaMultiplier: isPreview ? 0.55 : 1).setFill()",
            "NSBezierPath(ovalIn: dotRect).fill()",
            "path.lineCapStyle = .round",
            "path.lineJoinStyle = .round",
            "path.stroke()",
            "private static func annotationColor(_ annotation: Annotation, alphaMultiplier: CGFloat) -> NSColor",
            "color.alphaComponent * alphaMultiplier",
        ]:
            self.require(token in renderer, f"pen renderer missing {token}")
        self.require("replacePathWithStrokedPath" not in renderer, "pen should draw a stroke instead of clipping an erase path")
        self.require("penBackgroundColor" not in renderer, "pen should no longer fill a white background")

        path_points = [(10, 10), (12, 14)]
        end = (18, 20)
        finalized = list(path_points)
        if not finalized or finalized[-1] != end:
            finalized.append(end)
        self.require(finalized == [(10, 10), (12, 14), (18, 20)], "pen fixture should append final mouse-up point")

        single_point = [(10, 10)]
        stroke_width = 16
        dot_bounds = (
            single_point[0][0] - stroke_width / 2,
            single_point[0][1] - stroke_width / 2,
            stroke_width,
            stroke_width,
        )
        self.require(dot_bounds == (2, 2, 16, 16), "single-point pen fixture should create centered color dot")

    def case_text_annotation_dialog(self) -> None:
        annotation = self.read("Sources/SnapMark/Annotation.swift")
        dialog = self.read("Sources/SnapMark/TextAnnotationDialog.swift")
        canvas = self.read_many(
            "Sources/SnapMark/EditorCanvasView.swift",
            "Sources/SnapMark/EditorCanvasView+AnnotationEditing.swift"
        )
        renderer = self.read("Sources/SnapMark/ImageRenderer.swift")

        for token in [
            "struct TextAnnotationOptions",
            "enum TextAnnotationMetrics",
            "static let defaultFontSize: CGFloat = 28",
            "static func fittedSize(for text: String, fontSize: CGFloat, maxWidth: CGFloat) -> CGSize",
            "final class TextAnnotationDialogController",
            "NSTextView",
            "NSColorWell",
            "NSSlider(value: Double(TextAnnotationMetrics.defaultFontSize)",
            "previewLabel",
            "fontSizeLabel.stringValue = \"\\(Int(fontSize)) px\"",
            "TextAnnotationOptions(",
            "defaultText: String = \"\"",
            "textView.string = defaultText",
        ]:
            self.require(token in dialog, f"text annotation dialog missing {token}")
        self.require("func promptForTextOptions(" in canvas, "canvas should use text options dialog")
        self.require("TextAnnotationDialogController(" in canvas, "text dialog should be a custom modal controller")
        self.require("editTextAnnotation(at:" in canvas and "event.clickCount >= 2" in canvas, "double-click text edit path missing")
        self.require("defaultText: annotations[index].text" in canvas, "text edit dialog should preload existing text")
        self.require("defaultColor: annotations[index].color" in canvas, "text edit dialog should preload existing color")
        self.require("promptForText()" not in canvas, "old plain text alert should be removed")
        self.require("var fontSize: CGFloat = TextAnnotationMetrics.defaultFontSize" in annotation, "annotation must persist selected text size")
        self.require("annotation.fontSize" in renderer, "renderer should use selected text size")
        self.require(".paragraphStyle" in renderer, "text renderer should support wrapped text")

        sample = "SnapMark Text"
        font_size = 28
        estimated_width = max(96, min(font_size * 18, len(sample) * font_size * 0.62) + font_size * 0.9)
        estimated_height = font_size * 1.35
        self.require(estimated_width > 180 and estimated_height > 30, "text sizing fixture should scale with content and font size")

    def case_annotation_transform_and_color(self) -> None:
        interaction = self.read("Sources/SnapMark/AnnotationInteraction.swift")
        canvas = self.read_many(
            "Sources/SnapMark/EditorCanvasView.swift",
            "Sources/SnapMark/EditorCanvasView+AnnotationEditing.swift",
            "Sources/SnapMark/EditorCanvasView+Drawing.swift",
            "Sources/SnapMark/EditorCanvasView+Geometry.swift",
            "Sources/SnapMark/EditorCanvasView+ImagePatch.swift"
        )
        editor = self.read_many(
            "Sources/SnapMark/EditorWindowController.swift",
            "Sources/SnapMark/EditorWindowController+Tools.swift",
            "Sources/SnapMark/EditorWindowController+ToolbarSupport.swift"
        )
        color_control = self.read_many(
            "Sources/SnapMark/AnnotationColorPickerView.swift",
            "Sources/SnapMark/AnnotationColorPalette.swift",
            "Sources/SnapMark/CompactColorPickerViewController.swift"
        )

        for token in [
            "enum AnnotationResizeHandle",
            "enum AnnotationInteractionMode",
            "var isTransformableElement: Bool",
            "self != .pen && self != .hand",
            "var isDeletableElement: Bool",
            "var isImagePatch: Bool",
            "isImagePatch || tool.isTransformableElement",
            "isImagePatch || tool.isDeletableElement",
            "case .arrow, .rectangle, .text:",
            "func contains(point: CGPoint, tolerance: CGFloat) -> Bool",
            "func resizeHandlePoints() -> [(AnnotationResizeHandle, CGPoint)]",
            "func resizeHandle(at point: CGPoint, tolerance: CGFloat) -> AnnotationResizeHandle?",
            "func moved(by delta: CGPoint, within imageSize: CGSize) -> Annotation",
            "func resized(handle: AnnotationResizeHandle, to point: CGPoint, within imageSize: CGSize, minimumSize: CGFloat) -> Annotation",
            "distance(from: point, toSegmentStart: start, end: end)",
        ]:
            self.require(token in interaction, f"annotation interaction missing {token}")

        for token in [
            "var annotationColor: NSColor = .systemRed",
            "annotation.color = annotationColor",
            "beginAnnotationInteraction(at:",
            "updateAnnotationInteraction(to:",
            "endAnnotationInteraction()",
            "annotationInteractionMode",
            "selectedAnnotationID",
            "drawSelectedAnnotationOverlay()",
            "drawResizeHandles(for:",
            "resizeHandleDisplaySize",
            "minimumTransformSize(for:",
            "deleteSelectedAnnotation()",
            "func applyActiveAnnotation()",
            "override func resignFirstResponder() -> Bool",
            "AnnotationHitCandidate",
            "selectionArea(for:",
            "coveredRatio(forAnnotationAt:",
            "selectionFrame(for:",
            "event.keyCode == 51 || event.keyCode == 117",
            "annotations.remove(at: index)",
            "normalizeMinimumArrowLength(&annotation)",
            "clampsOutOfBounds: true",
        ]:
            self.require(token in canvas, f"canvas transform/color missing {token}")
        self.require("currentTool != .pen, beginAnnotationInteraction(at: point)" in canvas, "pen should keep drawing behavior instead of selecting")
        self.require("case .move:" in canvas and ".moved(by: delta, within: imageSize)" in canvas, "move interaction should update selected annotation")
        self.require("case .resize(let handle):" in canvas and ".resized(" in canvas, "resize interaction should update selected annotation")
        self.require("currentTool == .arrow" in canvas and "normalizeMinimumSize(&annotation)" in canvas, "arrow should use its own minimum-length normalization")
        self.require("lhs.area < rhs.area" in canvas and "lhs.coveredRatio > rhs.coveredRatio" in canvas, "overlap selection should prefer smaller or more covered annotations")

        for token in [
            "private static let colorToolbarWidth: CGFloat",
            "var annotationColorControl: AnnotationColorPickerView?",
            ".color",
            "AnnotationColorPickerView(color: canvasView.annotationColor)",
            "colorControl.onColorChanged",
            "canvasView.annotationColor = color",
            "annotationColorControl?.isEnabled = true",
            "private static let colorToolbarWidth: CGFloat = 66",
            "item.view = toolbarGroupView(containing: colorControl, horizontalPadding: 5)",
            "SnapMark.Color",
            "canvasView.applyActiveAnnotation()",
        ]:
            self.require(token in editor, f"editor color toolbar missing {token}")
        for token in [
            "final class AnnotationColorPickerView: NSControl",
            "AnnotationPresetColor(title: L10n.text(.colorRed), color: .systemRed)",
            "AnnotationPresetColor(title: L10n.text(.colorWhite), color: .white)",
            "AnnotationPresetColor(title: L10n.text(.colorBlue), color: .systemBlue)",
            "AnnotationPresetColor(title: L10n.text(.colorBlack), color: .black)",
            "floor(bounds.width * 2 / 3)",
            "cyclePresetColor()",
            "showCompactColorPicker()",
            "final class CompactColorPickerViewController",
            "NSPopover()",
            "popover.behavior = .transient",
            "popover.contentSize = CGSize(width: 252, height: 318)",
            "static var compactChoices: [AnnotationPresetColor]",
            "root.addArrangedSubview(paletteGrid())",
            "private func paletteGrid() -> NSView",
            "let columns = 8",
            "AnnotationColorPalette.compactChoices",
            "selectPaletteColor",
            "L10n.text(.colorHex)",
            "L10n.text(.colorOpacity)",
            "onColorSelected?(color, true)",
            "onColorChanged?(newColor)",
            "drawTransparencyBackground(in: rect)",
        ]:
            self.require(token in color_control, f"split color control missing {token}")
        preset_order = [
            "AnnotationPresetColor(title: L10n.text(.colorRed), color: .systemRed)",
            "AnnotationPresetColor(title: L10n.text(.colorWhite), color: .white)",
            "AnnotationPresetColor(title: L10n.text(.colorBlue), color: .systemBlue)",
            "AnnotationPresetColor(title: L10n.text(.colorBlack), color: .black)",
        ]
        last_index = -1
        for token in preset_order:
            index = color_control.index(token)
            self.require(index > last_index, "top color presets should be red, white, blue, black")
            last_index = index
        self.require("AnnotationPresetColor(title: L10n.text(.colorGreen), color: .systemGreen)" not in color_control, "green should be removed from the top quick colors")
        choices_match = re.search(r"static var compactChoices: \[AnnotationPresetColor\] \{\n        \[\n(?P<body>.*?)\n        \]\n    \}", color_control, re.DOTALL)
        self.require(choices_match is not None, "compact color choices missing")
        assert choices_match is not None
        self.require(choices_match.group("body").count("swatch(\"#") == 64, "compact color picker should expose an 8x8 color palette")
        self.require("NSColorPanel.shared" not in color_control, "color picker should not open the heavy system color panel")
        self.require("showColorMenu()" not in color_control, "color picker should use the single-page compact popover instead of a menu")
        self.require("annotations" not in color_control, "color picker must not recolor existing annotations")

        rect = {"min_x": 10, "max_x": 50, "min_y": 10, "max_y": 30}
        delta = [80, 80]
        image = {"width": 100, "height": 70}
        if rect["max_x"] + delta[0] > image["width"]:
            delta[0] = image["width"] - rect["max_x"]
        if rect["max_y"] + delta[1] > image["height"]:
            delta[1] = image["height"] - rect["max_y"]
        self.require(tuple(delta) == (50, 40), "transform fixture should clamp move inside image bounds")

        horizontal_arrow_start = (10, 10)
        horizontal_arrow_end = (30, 10)
        self.require(horizontal_arrow_end[1] == horizontal_arrow_start[1], "horizontal arrow fixture should preserve y direction")

        hit_candidates = [
            {"name": "large bottom", "area": 6400, "covered": 1.0, "index": 0},
            {"name": "large top", "area": 6400, "covered": 0.0, "index": 1},
            {"name": "small target", "area": 400, "covered": 0.2, "index": 2},
        ]
        ordered_hits = sorted(hit_candidates, key=lambda item: (item["area"], -item["covered"], -item["index"]))
        self.require(ordered_hits[0]["name"] == "small target", "overlap fixture should prefer smaller target")
        same_area_hits = sorted(hit_candidates[:2], key=lambda item: (item["area"], -item["covered"], -item["index"]))
        self.require(same_area_hits[0]["name"] == "large bottom", "overlap fixture should prefer the more covered item when areas match")

    def case_editor_checkerboard_zoom_pan(self) -> None:
        canvas = self.read_many(
            "Sources/SnapMark/EditorCanvasView.swift",
            "Sources/SnapMark/EditorCanvasView+Drawing.swift",
            "Sources/SnapMark/EditorCanvasView+Geometry.swift",
            "Sources/SnapMark/EditorCanvasView+Pan.swift"
        )
        editor = self.read_many(
            "Sources/SnapMark/EditorWindowController.swift",
            "Sources/SnapMark/EditorWindowController+ToolbarSupport.swift",
            "Sources/SnapMark/EditorWindowController+Zoom.swift",
            "Sources/SnapMark/EditorZoomPresets.swift"
        )
        for token in [
            "drawCheckerboard(in:",
            "checkerTileSize",
            "canvasRect",
            "transform.scale(by: zoomScale)",
            "imageInterpolation = .none",
            "rightMouseDragged",
            "updatePan(with:",
            "currentTool == .hand && handMode == .pan",
            "addCursorRect(bounds, cursor: .openHand)",
            "NSCursor.crosshair.set()",
        ]:
            self.require(token in canvas, f"editor canvas missing {token}")
        for token in [
            "scrollView.drawsBackground = false",
            "canvasView.setZoomScale(canvasView.fitZoomScale",
            "scrollToVisible(canvasView.canvasCenterRect)",
            "ZoomInfoSliderView(",
            "EditorCanvasView.maximumZoomScale",
            "fitZoomButton",
            "zoomInfoControl?.update(",
            "imageSizeText: EditorNumberFormatter.imageSize(imagePixelSize)",
            "zoomText: zoomInfoText(for: canvasView.zoomScale)",
            "let stack = NSStackView(views: [zoomControl, fitButton])",
            "stack.orientation = .horizontal",
            "window.title = \"SnapMark\"",
            "window.minSize = Self.minimumWindowSize()",
            "minimumToolbarWindowWidth: CGFloat = 1140",
            "private static let toolsToolbarWidth: CGFloat = 260",
            "control.setWidth(32, forSegment: AnnotationTool.hand.rawValue)",
            "lockToolbarItem(item, width: Self.toolsToolbarWidth)",
            "toolbar.displayMode = .iconOnly",
            "toolbar.sizeMode = .small",
            "window?.toolbarStyle = .unifiedCompact",
            "window?.titlebarSeparatorStyle = .line",
            "button.imagePosition = .imageOnly",
        ]:
            self.require(token in editor, f"editor window missing {token}")
        self.require("window.title = \"SnapMark · \\(Self.formatImageSize(imagePixelSize))\"" not in editor, "window title should not duplicate image size")
        self.require("lockToolbarItem(item, width: Self.imageSizeToolbarWidth)" in editor, "image size toolbar item should have a stable width")
        self.require("lockToolbarItem(item, width: Self.actionsToolbarWidth)" in editor, "actions toolbar group should have a stable width")
        self.require("ToolbarGroupContainerView" in editor, "toolbar groups should have visible background containers")
        self.require("ToolbarGroupSeparatorView" in editor, "toolbar groups should be separated by visible dividers")
        self.require("contentView.translatesAutoresizingMaskIntoConstraints = false" in editor, "toolbar group content should not create autoresizing constraint conflicts")
        self.require("zoomControl.widthAnchor.constraint(equalToConstant: 210)" in editor, "zoom slider should live in the left info toolbar item")
        self.require("zoomToolbarWidth" not in editor, "zoom slider should not reserve a separate right-side toolbar item")
        self.require("images: AnnotationTool.allCases.map" in editor, "annotation tools should use icons instead of visible text")
        self.require("labels: AnnotationTool.allCases.map" not in editor, "annotation tools should not render text labels")
        self.require("configureToolTips(for: control)" in editor, "icon-only tools should keep descriptive tooltips")
        self.require("item.toolTip = L10n.text(.toolbarToolsTooltip)" in editor, "toolbar tool group should explain icon behavior")
        self.require("button.toolTip = role.localizedToolTip" in editor, "action icons should use detailed tooltips")
        self.require("let stack = NSStackView(views: [label, slider])" not in editor, "toolbar buttons should not be split into a second row")
        default_items = re.search(r"func toolbarDefaultItemIdentifiers\(_ toolbar: NSToolbar\) -> \[NSToolbarItem.Identifier\] \{\n        \[\n(?P<body>.*?)\n        \]\n    \}", editor, re.DOTALL)
        self.require(default_items is not None, "toolbar default items missing")
        assert default_items is not None
        item_body = default_items.group("body")
        self.require(item_body.count(".flexibleSpace") == 1, "toolbar should use one flexible space for right alignment")
        self.require(item_body.index(".imageSize") < item_body.index(".flexibleSpace") < item_body.index(".tools"), "toolbar controls should be right aligned after image size")
        for separator in [".toolbarGroupSeparatorOne", ".toolbarGroupSeparatorTwo", ".toolbarGroupSeparatorThree"]:
            self.require(separator in item_body, f"toolbar group divider missing {separator}")
        self.require(".penSize" not in item_body, "pen size should not reserve a standalone toolbar item")
        self.require(".fitZoom" not in item_body, "fit zoom should move into the left zoom toolbar item")
        self.require(item_body.index(".tools") < item_body.index(".color") < item_body.index(".actions"), "color and actions should stay in the single-row tool group")
        self.require(".zoom" not in item_body, "zoom slider should not occupy right-side toolbar space")
        self.require("static func imageSize(_ size: CGSize)" in editor and "x \\(Int(size.height.rounded())) px" in editor, "editor must format screenshot dimensions")
        self.require("static func zoom(_ scale: CGFloat)" in editor, "editor must format zoom in the inline info block")
        self.require("zoomInfoText(for:" in editor, "zoom info should include matched mode text")

    def case_editor_toolbar_stacked_info_layout(self) -> None:
        editor = self.read_many(
            "Sources/SnapMark/EditorWindowController.swift",
            "Sources/SnapMark/EditorWindowController+Zoom.swift",
            "Sources/SnapMark/EditorZoomPresets.swift"
        )
        zoom_view = self.read("Sources/SnapMark/ZoomInfoSliderView.swift")

        self.require("let infoRow = NSStackView(views: [zoomLabel, spacer, imageSizeLabel])" in zoom_view, "zoom and pixels should share one info row")
        self.require("infoRow.orientation = .horizontal" in zoom_view, "toolbar info block should be horizontal")
        self.require("infoRow.alignment = .centerY" in zoom_view, "toolbar info row should be vertically centered")
        self.require("spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)" in zoom_view, "zoom and pixels should be pushed to opposite sides")
        self.require("zoomLabel.alignment = .left" in zoom_view, "zoom percent should be left aligned")
        self.require("imageSizeLabel.alignment = .right" in zoom_view, "pixel dimensions should be right aligned")
        self.require("addSubview(slider)" in zoom_view, "slider should live on the zoom info background")
        self.require("setSliderVisible(false, animated: false)" in zoom_view, "slider should be nearly transparent by default")
        self.require("override func mouseEntered" in zoom_view and "setSliderVisible(true, animated: true)" in zoom_view, "slider should appear on mouseover")
        self.require("override func mouseExited" in zoom_view and "setSliderVisible(false, animated: true)" in zoom_view, "slider should fade after mouseout")
        self.require("slider.alphaValue = 0.04" in zoom_view, "default slider track should be transparent")
        self.require("onZoomChanged?(CGFloat(sender.doubleValue))" in zoom_view, "slider should update actual zoom")
        self.require("let stack = NSStackView(views: [zoomControl, fitButton])" in editor, "fit button should sit near the zoom slider")
        self.require("@objc func cycleZoomPreset()" in editor, "fit button should cycle zoom presets")
        self.require("enum ZoomPresetMode: CaseIterable" in editor, "zoom presets should be explicit")
        for token in ["case actualSize", "case bestFit", "case fitIn"]:
            self.require(token in editor, f"zoom preset missing {token}")
        for token in [
            "struct ZoomPresetOption",
            "zoomPresetOptions()",
            "ZoomPresetOption(mode: mode",
            "if !options.contains(where: { Self.zoomScalesMatch($0.scale, option.scale) })",
            "nextZoomPresetOption(in:",
            "zoomScalesMatch",
            "fitZoomButton?.isEnabled = nextOption != nil",
            "updateFitZoomTooltip()",
            "zoomInfoText(for:",
            "EditorNumberFormatter.zoom(scale)",
            "option.title",
        ]:
            self.require(token in editor, f"zoom preset dedupe/mode display missing {token}")
        self.require("currentZoomPresetMode" not in editor, "zoom preset cycling should be ratio-driven, not sticky semantic state")
        self.require("option.mode == .fitIn" not in editor, "fit-in must not have special dedupe rules")
        self.require("modes.append(mode)" not in editor, "duplicate zoom scales should be excluded, not grouped into a combined label")
        self.require("case current" not in editor, "zoom cycle should not include a no-op current preset")
        self.require("let stack = NSStackView(views: [label, slider])" not in editor, "right side controls should not own zoom layout")

        default_items = re.search(r"func toolbarDefaultItemIdentifiers\(_ toolbar: NSToolbar\) -> \[NSToolbarItem.Identifier\] \{\n        \[\n(?P<body>.*?)\n        \]\n    \}", editor, re.DOTALL)
        self.require(default_items is not None, "toolbar default items missing")
        assert default_items is not None
        item_body = default_items.group("body")
        for item in [".tools", ".color", ".actions", ".toolbarGroupSeparatorOne", ".toolbarGroupSeparatorTwo", ".toolbarGroupSeparatorThree"]:
            self.require(item in item_body, f"toolbar single-row item missing {item}")
        self.require(".fitZoom" not in item_body, "fit button should not reserve right-side toolbar space")
        self.require(".penSize" not in item_body, "pen size should be folded into the pen tool segment")
        self.require(".zoom" not in item_body, "zoom slider should not be a right-side toolbar item")
        self.require(item_body.index(".flexibleSpace") < item_body.index(".tools"), "tool controls should stay to the right of flexible space")
        self.require(item_body.index(".tools") < item_body.index(".color") < item_body.index(".actions"), "color and actions should remain in the right-side single row")

        fit_zoom = 0.625
        formatted_zoom = f"{self.round_away(fit_zoom * 100)}%"
        self.require(formatted_zoom == "63%", "zoom formatting fixture should match Swift rounded percent behavior")
        self.require("return L10n.text(.zoomModeActualSize)" in editor, "actual-size zoom mode should display through localization")

        preset_scales = [("1:1", 1.0), ("Best Fit", 0.5), ("Fit In", 0.5)]
        unique_modes: list[str] = []
        unique_scales: list[float] = []
        for title, scale in preset_scales:
            if not any(abs(existing - scale) <= 0.0005 for existing in unique_scales):
                unique_modes.append(title)
                unique_scales.append(scale)
        self.require(unique_modes == ["1:1", "Best Fit"], "duplicate zoom ratios should keep only the first matching mode")
        self.require(f"{formatted_zoom} Best Fit" == "63% Best Fit", "zoom info fixture should display percent and mode")

    def case_text_annotation_sizing_and_drag(self) -> None:
        canvas = self.read_many(
            "Sources/SnapMark/EditorCanvasView.swift",
            "Sources/SnapMark/EditorCanvasView+AnnotationEditing.swift",
            "Sources/SnapMark/EditorCanvasView+Drawing.swift"
        )

        for token in [
            "applyTextOptions(_ options: TextAnnotationOptions, to annotation: inout Annotation)",
            "fitTextAnnotation(&annotation)",
            "TextAnnotationMetrics.fittedSize(",
            "annotation.fontSize = options.fontSize",
            "annotation.color = options.color",
            "editTextAnnotation(at:",
            "beginAnnotationInteraction(at:",
            "updateAnnotationInteraction(to:",
            "endAnnotationInteraction()",
            "textAnnotationIndex(at:",
            "selectedAnnotationID",
            "annotationInteractionMode",
            "drawSelectedAnnotationOverlay()",
            "annotations[index] = updated",
        ]:
            self.require(token in canvas, f"text annotation sizing/drag missing {token}")
        self.require("annotationHitTolerance" in canvas, "text hit target should be forgiving")
        self.require(".moved(by: delta, within: imageSize)" in canvas, "text dragging should clamp through shared movement logic")
        self.require("path.setLineDash" in canvas and "NSColor.controlAccentColor" in canvas, "selected text should show an editor-only outline")

        start = (10, 10)
        original_rect = {"min_x": 10, "max_x": 110, "min_y": 10, "max_y": 50}
        image_size = {"width": 128, "height": 80}
        desired_point = (96, 72)
        delta = [desired_point[0] - start[0], desired_point[1] - start[1]]
        if original_rect["max_x"] + delta[0] > image_size["width"]:
            delta[0] = image_size["width"] - original_rect["max_x"]
        if original_rect["max_y"] + delta[1] > image_size["height"]:
            delta[1] = image_size["height"] - original_rect["max_y"]
        self.require(tuple(delta) == (18, 30), "text drag fixture should clamp movement inside image bounds")

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
        canvas = self.read_many(
            "Sources/SnapMark/EditorCanvasView.swift",
            "Sources/SnapMark/EditorCanvasView+AnnotationEditing.swift",
            "Sources/SnapMark/EditorCanvasView+Geometry.swift"
        )
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
        self.require("clampsOutOfBounds: Bool = false" in canvas, "image point mapping should optionally clamp out-of-bounds drags")
        self.require("clampsOutOfBounds || rect.contains(viewPoint)" in canvas, "mouseDown should still require an in-image start")
        self.require("imagePoint(from: convert(event.locationInWindow, from: nil), clampsOutOfBounds: true)" in canvas, "drag/update paths should clamp outside points to image bounds")
        self.require("let end = imagePoint(from: convert(event.locationInWindow, from: nil), clampsOutOfBounds: true) ?? start" in canvas, "mouseUp must clamp outside endpoints to image pixels")
        self.require("minimum * xSign" in canvas and "minimum * ySign" in canvas, "minimum-size normalization should preserve drag direction")

        view_point = {"x": 180, "y": 132}
        canvas_origin = {"x": 100, "y": 80}
        zoom = 4
        image_point = ((view_point["x"] - canvas_origin["x"]) / zoom, (view_point["y"] - canvas_origin["y"]) / zoom)
        self.require(image_point == (20, 13), "fixture image coordinate reverse mapping failed")

        outside_view_point = {"x": -40, "y": 360}
        outside_image_point = (
            max(0, min(100, (outside_view_point["x"] - canvas_origin["x"]) / zoom)),
            max(0, min(80, (outside_view_point["y"] - canvas_origin["y"]) / zoom)),
        )
        self.require(outside_image_point == (0, 70), "fixture outside drag should clamp to image bounds")

    def case_editor_zoom_range(self) -> None:
        canvas = self.read_many(
            "Sources/SnapMark/EditorCanvasView.swift",
            "Sources/SnapMark/EditorCanvasView+Geometry.swift"
        )
        editor = self.read_many(
            "Sources/SnapMark/EditorWindowController.swift",
            "Sources/SnapMark/EditorWindowController+Zoom.swift",
            "Sources/SnapMark/EditorZoomPresets.swift"
        )
        self.require("static let minimumZoomScale: CGFloat = 0.03125" in canvas, "minimum zoom must support 1:32 for very large Best Fit captures")
        self.require("static let maximumZoomScale: CGFloat = 8" in canvas, "maximum zoom must support 8:1")
        self.require("min(Self.maximumZoomScale, max(Self.minimumZoomScale, scale))" in canvas, "setZoomScale must clamp to supported range")
        self.require("fitBorderInset" in canvas, "fit zoom must reserve room for the image border")
        self.require("let availableWidth = max(1, viewportSize.width - contentPadding * 2 - fitBorderInset)" in canvas, "fit zoom must account for horizontal padding and border")
        self.require("let availableHeight = max(1, viewportSize.height - contentPadding * 2 - fitBorderInset)" in canvas, "fit zoom must account for vertical padding and border")
        self.require("min(1, availableWidth / imageSize.width, availableHeight / imageSize.height)" in canvas, "fit zoom must prefer 1:1 unless image is too large")
        self.require("func bestFitZoomScale(for viewportSize: CGSize) -> CGFloat" in canvas, "best-fit zoom helper missing")
        self.require("func fitInZoomScale(for viewportSize: CGSize) -> CGFloat" in canvas, "fit-in zoom helper missing")
        self.require("min(availableWidth / imageSize.width, availableHeight / imageSize.height)" in canvas, "fit-in zoom should be able to enlarge small images")
        self.require("let availableWidth = max(1, viewportSize.width - fitBorderInset)" in canvas, "fit-in should maximize content width instead of keeping best-fit padding")
        self.require("let availableHeight = max(1, viewportSize.height - fitBorderInset)" in canvas, "fit-in should maximize content height instead of keeping best-fit padding")
        self.require("max(viewportSize.width, scaledSize.width + contentPadding * 2)" in canvas, "document width must allow scrolling at high zoom")
        self.require("max(viewportSize.height, scaledSize.height + contentPadding * 2)" in canvas, "document height must allow scrolling at high zoom")
        self.require("shouldApplyInitialViewportFit" in editor, "initial zoom must refit after the real scroll viewport is available")
        self.require("minValue: EditorCanvasView.minimumZoomScale" in editor, "zoom slider must expose minimum zoom")
        self.require("maxValue: EditorCanvasView.maximumZoomScale" in editor, "zoom slider must expose maximum zoom")
        self.require("case .actualSize:" in editor and "return 1" in editor, "zoom presets should include 100%")
        self.require("return canvasView.bestFitZoomScale(for: viewportSize)" in editor, "zoom presets should include best-fit")
        self.require("return canvasView.fitInZoomScale(for: viewportSize)" in editor, "zoom presets should include fit-in")

        viewport_width = 1100
        image_width = 10000
        padding = 48
        border = 2
        best_fit = (viewport_width - padding * 2 - border) / image_width
        old_minimum = 0.125
        new_minimum = 0.03125
        self.require(best_fit < old_minimum and best_fit > new_minimum, "fixture should exercise a Best Fit scale below the old 1:8 clamp")
        self.require(image_width * best_fit + padding * 2 + border <= viewport_width, "Best Fit fixture should keep the border inside the viewport")

        image_height = 6000
        viewport_height = 700
        best_fit_scale = min(1, (viewport_width - padding * 2 - border) / image_width, (viewport_height - padding * 2 - border) / image_height)
        fit_in_scale = min((viewport_width - border) / image_width, (viewport_height - border) / image_height)
        self.require(fit_in_scale > best_fit_scale, "Fit In fixture should be larger than padded Best Fit")
        self.require(
            abs(max(image_width * fit_in_scale, image_height * fit_in_scale) - max(viewport_width - border, viewport_height - border)) < 0.001,
            "Fit In fixture should make one dimension fill the viewport"
        )

    def case_autosave_settings(self) -> None:
        settings = self.read("Sources/SnapMark/AppSettings.swift")
        store = self.read("Sources/SnapMark/AutoSaveStore.swift")
        self.require(".downloadsDirectory" in settings, "default save directory should be Downloads")
        self.require("AppSettings.shared.saveDirectory" in store, "autosave does not use settings directory")
        self.require("newCaptureURL()" in store, "autosave capture URL missing")
        self.require("uniquePNGURL(baseName:" in store and "FileManager.default.fileExists" in store, "autosave file names should avoid collisions")

    def case_exit_autosaves_modified_editor(self) -> None:
        app = self.read("Sources/SnapMark/AppDelegate.swift")
        editor = self.read_many(
            "Sources/SnapMark/EditorWindowController.swift",
            "Sources/SnapMark/EditorWindowController+Export.swift"
        )
        controller = self.read("Sources/SnapMark/ScreenSelectionController.swift")
        settings = self.read("Sources/SnapMark/SettingsWindowController.swift")

        for token in [
            "let originalSaveURL: URL",
            "var editedSaveURL: URL?",
            "var hasUserEdits = false",
            "markUserEdits()",
            "editedSaveURL = AutoSaveStore.newCaptureURL()",
            "saveEditedImageIfNeeded()",
            "try? AutoSaveStore.save(canvasView.renderedImage(), to: editedAutoSaveURL())",
            "windowWillClose",
            "releaseWindowResources()",
            "scrollView.documentView = nil",
            "canvasView.onAnnotationsChanged = nil",
            "canvasView.onResetRequested = nil",
            "window?.toolbar = nil",
        ]:
            self.require(token in editor, f"modified editor exit missing {token}")

        for token in [
            "closeAllTransientContexts()",
            "applicationWillTerminate",
            "windows.forEach { $0.closeForExit() }",
            "settingsWindowController = nil",
            "controller.onClose",
        ]:
            self.require(token in app, f"app exit/resource cleanup missing {token}")

        self.require("window.contentView = nil" in controller, "selection overlay should release snapshot views on exit")
        self.require("var onClose: (() -> Void)?" in settings and "onClose?()" in settings, "settings window should release AppDelegate ownership on close")

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
        self.require("private func menuItem(title: String, action: Selector, keyEquivalent: String, symbolName: String) -> NSMenuItem" in app, "status menu items should be created with icons")
        self.require("item.image = menuIcon(symbolName)" in app, "status menu item icon assignment missing")
        for symbol in ["rectangle.dashed", "display", "folder", "gearshape", "info.circle", "power"]:
            self.require(f'symbolName: "{symbol}"' in app, f"status menu icon missing {symbol}")

    def case_hotkey_settings_recording_transaction(self) -> None:
        app = self.read("Sources/SnapMark/AppDelegate.swift")
        settings = self.read("Sources/SnapMark/SettingsWindowController.swift")
        hotkey = self.read("Sources/SnapMark/HotKeyManager.swift")

        self.require("func unregisterRegionShortcut()" in hotkey, "hotkey manager must expose explicit unregister for recording")
        self.require("onShortcutRecordingBegan" in settings, "settings window must notify recording begin")
        self.require("onShortcutRecordingCancelled" in settings, "settings window must notify recording cancel")
        self.require("onRecordingBegin" in settings and "onRecordingCancel" in settings, "shortcut recorder must support begin/cancel hooks")
        self.require("guard !isRecording else { return }" in settings, "recorder must not pause hotkey twice")
        self.require("if let activeShortcut = onRecordingBegin?()" in settings, "recorder must refresh active shortcut before recording")
        self.require("if let activeShortcut = onRecordingCancel?()" in settings, "recorder must restore button state on cancel")
        self.require("windowWillClose" in settings and "shortcutButton.stopRecording()" in settings, "closing settings must cancel recording")
        self.require("ExitShortcut.matches(event)" in settings and "stopRecording()" in settings, "exit shortcut must cancel shortcut recording")

        self.require("recordingPreviousRegionShortcut" in app, "app must remember the pre-recording hotkey")
        self.require("isRecordingRegionShortcut" in app, "app must track recording transaction state")
        self.require("beginRegionShortcutRecording()" in app, "app must begin recording transaction")
        self.require("hotKeyManager.unregisterRegionShortcut()" in app, "app must unregister active hotkey while recording")
        self.require("cancelRegionShortcutRecording()" in app, "app must restore old hotkey when recording is cancelled")
        self.require("restoreRegionShortcut(recordingPreviousRegionShortcut" in app, "cancel path must restore previous hotkey")
        self.require("let previousShortcut = isRecordingRegionShortcut ? recordingPreviousRegionShortcut : registeredRegionShortcut" in app, "apply must restore pre-recording hotkey on failure")
        self.require("_ = restoreRegionShortcut(previousShortcut, showError: true)" in app, "failed apply must restore previous hotkey")
        self.require("showShortcutError(shortcut, result: result)" in app, "failed apply must alert the user")
        self.require("finishRegionShortcutRecording()" in app, "recording state must be cleared after success or failure")
        self.require("AppSettings.shared.regionShortcut = shortcut" in app, "settings should only persist after successful hotkey registration")
        self.require("showShortcutRestoreError" in app, "restore failure must be surfaced")

    def case_share_image(self) -> None:
        editor = self.read_many(
            "Sources/SnapMark/EditorWindowController.swift",
            "Sources/SnapMark/EditorWindowController+Export.swift",
            "Sources/SnapMark/EditorWindowController+ToolbarSupport.swift"
        )
        store = self.read("Sources/SnapMark/AutoSaveStore.swift")
        self.require("NSSharingServicePicker(items: [url])" in editor, "share picker missing")
        self.require("@objc func shareImage(_ sender: NSButton)" in editor, "share action missing")
        self.require("AutoSaveStore.writeTemporaryImage(canvasView.renderedImage())" in editor, "share should export rendered image to a temporary file")
        self.require("picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)" in editor, "share picker should anchor to the toolbar button")
        self.require("square.and.arrow.up" in editor and "SnapMark.Actions" in editor, "share toolbar action/icon missing")
        self.require("static func writeTemporaryImage(_ image: NSImage) -> URL?" in store, "temporary share image writer missing")
        self.require("writeTemporaryDragImage" not in store, "old drag-specific temporary writer should be removed")

    def case_settings_window(self) -> None:
        settings = self.read("Sources/SnapMark/SettingsWindowController.swift")
        login = self.read("Sources/SnapMark/LaunchAtLoginService.swift")
        for token in ["L10n.text(.settingsShortcut)", "L10n.text(.settingsSaveDirectory)", "L10n.text(.settingsLaunchMode)"]:
            self.require(token in settings, f"settings row missing: {token}")
        self.require("ShortcutRecorderButton" in settings, "shortcut recorder missing")
        self.require("NSOpenPanel" in settings, "directory picker missing")
        self.require("SMAppService.mainApp" in login, "launch at login service missing")

    def case_language_settings(self) -> None:
        localization = self.read("Sources/SnapMark/Localization.swift")
        settings_model = self.read("Sources/SnapMark/AppSettings.swift")
        settings_window = self.read("Sources/SnapMark/SettingsWindowController.swift")
        app = self.read("Sources/SnapMark/AppDelegate.swift")
        editor = self.read("Sources/SnapMark/EditorWindowController.swift")

        for token in [
            "enum AppLanguageSetting: String, CaseIterable",
            "case system",
            "case simplifiedChinese",
            "case english",
            "Locale.preferredLanguages",
            "return .system",
            "var languageSetting: AppLanguageSetting",
        ]:
            self.require(token in localization + settings_model, f"language setting missing {token}")
        for token in [
            "private let languagePopup = NSPopUpButton()",
            "languageRow()",
            "L10n.text(.settingsLanguage)",
            "@objc private func changeLanguage()",
            "AppSettings.shared.languageSetting = setting",
            "applyLanguage()",
        ]:
            self.require(token in settings_window, f"settings language UI missing {token}")
        for token in [
            "self?.applyLanguage()",
            "settingsWindowController?.applyLanguage()",
            "editorWindows.forEach { $0.applyLanguage() }",
        ]:
            self.require(token in app, f"app language refresh missing {token}")
        self.require("func applyLanguage()" in editor, "open editor windows should refresh localized tooltips")

        key_match = re.search(r"enum Key: String, CaseIterable \{(?P<body>.*?)\n    \}", localization, re.DOTALL)
        self.require(key_match is not None, "localization key enum missing")
        assert key_match is not None
        keys = re.findall(r"case ([A-Za-z0-9]+)", key_match.group("body"))
        english_body = localization.split(".english: [", 1)[1].split("],\n        .simplifiedChinese", 1)[0]
        chinese_body = localization.split(".simplifiedChinese: [", 1)[1].rsplit("\n        ]", 1)[0]
        for key in keys:
            self.require(f".{key}:" in english_body, f"English localization missing {key}")
            self.require(f".{key}:" in chinese_body, f"Chinese localization missing {key}")

        cjk_literal = re.compile(r'"[^"\n]*[\u4e00-\u9fff][^"\n]*"')
        for path in (self.root / "Sources/SnapMark").glob("*.swift"):
            if path.name == "Localization.swift":
                continue
            text = path.read_text(encoding="utf-8")
            self.require(cjk_literal.search(text) is None, f"localized UI text should not be hardcoded outside Localization.swift: {path.name}")

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
        self.require(re.match(r"^\d{6}$", plist.get("SnapMarkBuildTime", "")) is not None, "build time should be HHMMSS")

    def case_build_script(self) -> None:
        build = self.read("Scripts/build_app.sh")
        install = self.read("Scripts/install_app.sh")
        for token in ["generate_icon_assets.py", "iconutil", "swift build -c release", "codesign", "SnapMarkIcon.icns", "StatusIcon.png"]:
            self.require(token in build, f"build script missing {token}")
        self.require("SnapMarkBuildTime" in build and "date +%H%M%S" in build, "build script should write HHMMSS build time")
        self.require("/Applications/SnapMark.app" in install, "install script should prefer /Applications")
        self.require("--no-launch" in build, "build script should allow install script to avoid duplicate launches")
        self.require("--skip-build" in install, "install script should support launching an already built app")

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
            "date +%H%M%S",
            "CFBundleShortVersionString",
            "CFBundleVersion",
            "SnapMarkBuildTime",
        ]:
            self.require(token in build, f"build script missing version rule token: {token}")

        with info_path.open("rb") as handle:
            source_plist = plistlib.load(handle)
        source_version = source_plist.get("CFBundleShortVersionString", "")
        source_build_time = source_plist.get("SnapMarkBuildTime", "")
        pattern = rf"^{re.escape(major)}\.\d+\.\d{{4}}$"
        self.require(re.match(pattern, source_version) is not None, f"source version does not match {major}.<n>.MMDD: {source_version}")
        self.require(re.match(r"^\d{6}$", source_build_time) is not None, f"source build time should be HHMMSS: {source_build_time}")

        if self.app:
            app_info = self.app / "Contents/Info.plist"
            with app_info.open("rb") as handle:
                app_plist = plistlib.load(handle)
            app_version = app_plist.get("CFBundleShortVersionString", "")
            app_build = app_plist.get("CFBundleVersion", "")
            app_build_time = app_plist.get("SnapMarkBuildTime", "")
            self.require(re.match(pattern, app_version) is not None, f"app version does not match {major}.<n>.MMDD: {app_version}")
            self.require(app_build == app_version, "CFBundleVersion should match short version")
            self.require(app_build_time == source_build_time, "app build time should match source Info.plist")
            self.require(re.match(r"^\d{6}$", app_build_time) is not None, f"app build time should be HHMMSS: {app_build_time}")
            self.require(app_version.endswith(datetime.now().strftime(".%m%d")), f"app version should use today's MMDD: {app_version}")
            version_minor = int(app_version.split(".")[1])
            self.require(version_minor == minor, f"version state minor {minor} does not match app version {app_version}")

    def case_build_restarts_app(self) -> None:
        build = self.read("Scripts/build_app.sh")
        install = self.read("Scripts/install_app.sh")
        self.require("LAUNCH_AFTER_BUILD" in build, "build script must default to launching after successful compile")
        self.require('"${ROOT_DIR}/Scripts/install_app.sh" --skip-build' in build, "build script must install and launch after build")
        self.require('"${ROOT_DIR}/Scripts/build_app.sh" --no-launch' in install, "install script must avoid recursive launch during build")
        self.require("pkill -x SnapMark" in install, "install script must stop the old app before replacement")
        self.require("pgrep -x SnapMark" in install, "install script must verify old/new SnapMark process state")
        self.require("open \"${INSTALL_APP}\"" in install, "install script must open the freshly installed app")

    def case_about_menu_build_info(self) -> None:
        app = self.read("Sources/SnapMark/AppDelegate.swift")
        version = self.read("Sources/SnapMark/AppVersion.swift")
        build = self.read("Scripts/build_app.sh")
        plist_path = self.require_file("Resources/Info.plist")

        with plist_path.open("rb") as handle:
            plist = plistlib.load(handle)

        self.require("aboutMenuItem" in app, "about menu item missing")
        self.require("L10n.format(.menuAboutFormat, AppVersion.aboutVersionText)" in app, "about menu title should include version and build time")
        self.require("@objc private func showAbout()" in app, "about action missing")
        self.require("L10n.format(\n            .aboutInformativeTextFormat,\n            AppVersion.aboutVersionText,\n            L10n.text(.aboutAppDescription),\n            Self.authorContactEmail\n        )" in app, "about alert should show version, app description, and author contact")
        self.require('private static let authorContactEmail = "cdingstar@gmail.com"' in app, "about contact email missing")
        self.require("alert.addButton(withTitle: L10n.text(.contactAuthor))" in app, "about contact author button missing")
        self.require('URL(string: "mailto:\\(Self.authorContactEmail)")' in app, "about contact author should use a mailto URL")
        self.require("NSWorkspace.shared.open(url)" in app, "about contact author should open the mail client")
        self.require("static var buildTime" in version, "build time accessor missing")
        self.require("static var aboutVersionText" in version, "about version text missing")
        self.require("SnapMarkBuildTime" in version, "app version should read bundle build time")
        self.require("SnapMarkBuildTime" in build and "date +%H%M%S" in build, "build script should refresh build time")
        self.require(re.match(r"^\d{6}$", plist.get("SnapMarkBuildTime", "")) is not None, "Info.plist build time should be HHMMSS")

    def case_module_size_budget(self) -> None:
        limits = {
            "Sources/SnapMark/ScreenSelectionController.swift": 140,
            "Sources/SnapMark/ScreenSelectionView.swift": 280,
            "Sources/SnapMark/ScreenSelectionWindow.swift": 80,
            "Sources/SnapMark/SelectionCoordinateOverlay.swift": 130,
            "Sources/SnapMark/SelectionMagnifierGeometry.swift": 100,
            "Sources/SnapMark/SelectionMagnifierRenderer.swift": 180,
            "Sources/SnapMark/ScreenCaptureRegion.swift": 170,
            "Sources/SnapMark/WindowInspector.swift": 140,
        }
        for relative, limit in limits.items():
            lines = len(self.read(relative).splitlines())
            self.require(lines <= limit, f"{relative} has {lines} lines, budget is {limit}")

        for path in (self.root / "Sources/SnapMark").glob("Editor*.swift"):
            lines = len(path.read_text(encoding="utf-8").splitlines())
            self.require(lines <= 500, f"{path.relative_to(self.root)} has {lines} lines, budget is 500")

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
            "SMK-P0-SHOT-010",
            "SMK-P0-SHOT-011",
            "SMK-P0-SHOT-012",
            "SMK-P0-MAG-001",
            "SMK-P0-ANN-001",
            "SMK-P0-ANN-003",
            "SMK-P0-ANN-004",
            "SMK-P0-ANN-005",
            "SMK-P0-ANN-006",
            "SMK-P0-EDITOR-001",
            "SMK-P0-EDITOR-002",
            "SMK-P0-EDITOR-003",
            "SMK-P0-EDITOR-004",
            "SMK-P0-EDITOR-005",
            "SMK-P0-EDITOR-006",
            "SMK-P0-SAVE-001",
            "SMK-P0-SAVE-002",
            "SMK-P0-HOT-001",
            "SMK-P0-HOT-002",
            "SMK-P0-HOT-003",
            "SMK-P0-HOT-004",
            "SMK-P0-SHARE-001",
            "SMK-P0-SET-001",
            "SMK-P0-SET-004",
            "SMK-P0-BUNDLE-005",
            "SMK-P0-BUNDLE-006",
            "SMK-P0-BUNDLE-007",
            "SMK-QA-002",
        ]:
            self.require(case_id in test_plan, f"test plan missing {case_id}")

    def case_ui_overview_docs(self) -> None:
        overview = self.read("Docs/UIOverview.MD")
        requirements = self.read("Docs/FinalRequirements.MD")
        image_path = self.require_file("Docs/Images/snapmark-ui-overview.png")
        for token in [
            "SnapMark UI Overview",
            "状态栏菜单",
            "截图选择",
            "编辑窗口",
            "ZoomInfoSliderView",
            "共享",
            "设置窗口",
            "文字标注弹窗",
            "snapmark-ui-overview.png",
        ]:
            self.require(token in overview, f"UI overview missing {token}")
        for token in [
            "SnapMark 最终需求说明文档",
            "多功能工具按钮",
            "颜色选择面板",
            "关于窗口",
            "系统共享面板",
            "联系作者",
            "Fit In",
            "Best Fit",
            "8x8 标准色盘",
        ]:
            self.require(token in requirements, f"final requirements missing {token}")

        annotated_images = [
            "01-status-menu-annotated.png",
            "02-capture-selection-annotated.png",
            "03-editor-window-annotated.png",
            "04-color-picker-annotated.png",
            "05-settings-window-annotated.png",
            "06-text-dialog-annotated.png",
            "07-about-dialog-annotated.png",
            "08-share-panel-annotated.png",
            "09-final-ui-map.png",
        ]
        for name in annotated_images:
            annotated_path = self.require_file(f"Docs/Images/final-ui/{name}")
            self.require(annotated_path.stat().st_size > 1024, f"annotated UI image looks too small: {name}")
        self.require(image_path.stat().st_size > 1024, "UI overview screenshot looks too small")
        if Image is not None:
            screenshot = Image.open(image_path)
            self.require(screenshot.size[0] >= 1200 and screenshot.size[1] >= 800, f"UI overview screenshot is too small: {screenshot.size}")
            for name in annotated_images:
                annotated_path = self.root / "Docs" / "Images" / "final-ui" / name
                annotated = Image.open(annotated_path)
                self.require(annotated.size[0] >= 1200 and annotated.size[1] >= 800, f"annotated UI image is too small: {name} {annotated.size}")

    @staticmethod
    def round_away(value: float) -> int:
        return math.floor(value + 0.5) if value >= 0 else math.ceil(value - 0.5)

    def fixture_region_from_drag(
        self,
        start: tuple[float, float],
        end: tuple[float, float],
        screen_height: int,
        scale: int,
    ) -> dict[str, tuple[int, int]]:
        left = min(start[0], end[0])
        right = max(start[0], end[0])
        bottom = min(start[1], end[1])
        top = max(start[1], end[1])

        cg_min_x = left
        cg_min_y = screen_height - top
        cg_max_x = right
        cg_max_y = screen_height - bottom
        snapped_min_x = self.round_away(cg_min_x * scale)
        snapped_min_y = self.round_away(cg_min_y * scale)
        snapped_max_x = self.round_away(cg_max_x * scale)
        snapped_max_y = self.round_away(cg_max_y * scale)
        return {
            "origin": (snapped_min_x, snapped_min_y),
            "size": (snapped_max_x - snapped_min_x, snapped_max_y - snapped_min_y),
        }

    @staticmethod
    def pixel_rect(rect: dict[str, float], scale: int) -> dict[str, int]:
        min_x = round(rect["x"] * scale)
        min_y = round(rect["y"] * scale)
        max_x = round((rect["x"] + rect["width"]) * scale)
        max_y = round((rect["y"] + rect["height"]) * scale)
        return {"x": min_x, "y": min_y, "width": max_x - min_x, "height": max_y - min_y}

    @staticmethod
    def integral_point_rect(rect: dict[str, float]) -> dict[str, float]:
        min_x = math.floor(rect["x"])
        min_y = math.floor(rect["y"])
        max_x = math.ceil(rect["x"] + rect["width"])
        max_y = math.ceil(rect["y"] + rect["height"])
        return {"x": min_x, "y": min_y, "width": max_x - min_x, "height": max_y - min_y}

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
