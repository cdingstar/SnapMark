# SnapMark Test Plan

本测试计划按功能模块维护。每个功能需求必须至少有一个 testcase；新增功能时需要同步新增 testcase，并让 `Scripts/test.sh` 或对应测试实现覆盖它。

## 执行入口

```bash
Scripts/test.sh
```

构建 app 时会自动执行：

```bash
Scripts/build_app.sh
```

`build_app.sh` 会在 release build、资源复制、签名完成后调用：

```bash
Scripts/test.sh --skip-build --app dist/SnapMark.app
```

## P0 截图

| ID | 类型 | 模块 | 测试点 |
| --- | --- | --- | --- |
| SMK-P0-SHOT-001 | 自动 | 区域截图 | 菜单/快捷键入口进入 `ScreenSelectionResult.region`，拖拽后按区域截图。 |
| SMK-P0-SHOT-002 | 自动 | 全屏截图 | `captureFullScreen()` 聚合所有屏幕 frame 并调用截图服务。 |
| SMK-P0-SHOT-003 | 自动 | 窗口截图 | mouse move 命中 app window，单击走 window id 截图。 |
| SMK-P0-SHOT-004 | 自动 | 状态 reset | 激活截图、编辑窗口、设置窗口状态下 `Esc` 可 reset。 |
| SMK-P0-SHOT-005 | 手动 | 权限 | 首次截图无权限时提示打开系统设置；授权后截图不重复弹窗。 |
| SMK-P0-SHOT-006 | 自动 | 截图遮罩 | 截图遮罩使用可成为 key/main 的 window，并在激活时主动接收 `Esc`。 |
| SMK-P0-SHOT-007 | 自动 | 坐标映射 | 区域选择的 AppKit point 坐标按屏幕和 backing scale 转换为 CoreGraphics 截图坐标，避免截图内容偏移或尺寸错误。 |

## P0 放大镜

| ID | 类型 | 模块 | 测试点 |
| --- | --- | --- | --- |
| SMK-P0-MAG-001 | 自动 | 截图放大镜 | 激活截图时 mouse move 显示 10x 像素化放大，关闭插值。 |
| SMK-P0-MAG-002 | 手动 | 截图放大镜 | 右下角放不下时自动换到其他可完整显示位置。 |

## P0 标注与编辑

| ID | 类型 | 模块 | 测试点 |
| --- | --- | --- | --- |
| SMK-P0-ANN-001 | 自动 | 标注工具 | 箭头、矩形、文字、马赛克、放大镜工具和 renderer 都存在。 |
| SMK-P0-ANN-002 | 手动 | 编辑窗口 | 截图后可添加每类标注，撤销、复制、保存可用。 |
| SMK-P0-EDITOR-001 | 自动 | 编辑窗口 | 截图后窗口使用 Photoshop 风格棋盘底，截图内容居中显示，支持自动 fit、最高 800% 缩放和拖拽/滚动查看。 |

## P0 保存与导出

| ID | 类型 | 模块 | 测试点 |
| --- | --- | --- | --- |
| SMK-P0-SAVE-001 | 自动 | 自动保存 | 保存目录来自设置，默认 Downloads，文件名按时间生成 PNG。 |
| SMK-P0-DRAG-001 | 自动 | 拖拽复制 | 拖拽按钮生成临时 PNG，拖拽操作为 copy。 |
| SMK-P0-DRAG-002 | 手动 | 拖拽复制 | 从编辑窗口拖拽到 Finder/聊天窗口可复制图片。 |

## P0 快捷键

| ID | 类型 | 模块 | 测试点 |
| --- | --- | --- | --- |
| SMK-P0-HOT-001 | 自动 | 快捷键 | 默认 fallback 链为 `Command+Control+A/S/Q`。 |
| SMK-P0-HOT-002 | 自动 | 快捷键 | 快捷键注册成功但按下不触发时，自动重新走 A/S/Q fallback。 |
| SMK-P0-HOT-003 | 自动 | 菜单 UI | tooltip 和设置菜单短名称显示实际使用的快捷键。 |
| SMK-P0-HOT-004 | 手动 | 快捷键 | 设置窗口录制新快捷键，冲突时提示重新选择。 |

## P0 设置

| ID | 类型 | 模块 | 测试点 |
| --- | --- | --- | --- |
| SMK-P0-SET-001 | 自动 | 设置窗口 | 设置窗口包含快捷键、存储目录、开机启动。 |
| SMK-P0-SET-002 | 手动 | 设置窗口 | 修改保存目录后，新截图保存到新目录。 |
| SMK-P0-SET-003 | 手动 | 开机启动 | 从 `.app` 包运行时可开启/关闭登录项。 |

## P0 打包与资源

| ID | 类型 | 模块 | 测试点 |
| --- | --- | --- | --- |
| SMK-P0-ICON-001 | 自动 | 图标 | app icon、status icon 存在且尺寸正确。 |
| SMK-P0-BUNDLE-001 | 自动 | Info.plist | bundle id、icon、LSUIElement 配置正确。 |
| SMK-P0-BUNDLE-002 | 自动 | 构建脚本 | 构建脚本生成图标、release build、复制资源并签名。 |
| SMK-P0-BUNDLE-003 | 自动 | app bundle | app 内含可执行文件、Info.plist、图标资源。 |
| SMK-P0-BUNDLE-004 | 自动 | codesign | app bundle 通过 `codesign --verify --deep --strict`。 |
| SMK-P0-BUNDLE-005 | 自动 | 版本规则 | 每次成功编译 app 自动递增 `1.<auto-minor>.MMDD`，并写入 bundle version。 |

## 架构与资源

| ID | 类型 | 模块 | 测试点 |
| --- | --- | --- | --- |
| SMK-P0-ARCH-001 | 自动 | 模块拆分 | 截图选择、放大镜、窗口探测按模块拆分且文件大小受控。 |
| SMK-P0-PERF-001 | 手动 | 资源 | 进入截图前后观察 Activity Monitor，截图 overlay 关闭后无长期 CPU 占用。 |

## P1 规划

| ID | 类型 | 模块 | 测试点 |
| --- | --- | --- | --- |
| SMK-P1-PLAN-001 | 自动 | 产品规划 | Ask ChatGPT、Mail、Codex/ClaudeCode、Copy、隐私处理规划已记录。 |

## P* 规划

| ID | 类型 | 模块 | 测试点 |
| --- | --- | --- | --- |
| SMK-PSTAR-PLAN-001 | 自动 | 产品规划 | 无限滚动截图、录屏、GIF、OCR、Pin、Color Picker 等规划已记录。 |

## QA Guard

| ID | 类型 | 模块 | 测试点 |
| --- | --- | --- | --- |
| SMK-QA-001 | 自动 | 测试计划 | 测试计划覆盖当前 P0 核心功能 testcase。 |
