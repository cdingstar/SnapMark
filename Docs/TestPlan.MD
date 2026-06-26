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

测试通过后会安装到稳定 app 路径并重启 SnapMark，确保运行中的进程来自最新编译产物。

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
| SMK-P0-SHOT-008 | 自动 | 截图内容 | 实际截图输出尺寸必须与选择区域换算后的像素尺寸一致，避免选区和结果尺寸不一致。 |
| SMK-P0-SHOT-009 | 自动 | 选区提示 | 选择框尺寸提示显示实际像素 `px`，不是 AppKit point。 |
| SMK-P0-SHOT-010 | 自动 | 坐标面板 | 选区时只显示一行简要信息：屏幕起点、屏幕终点和最终 `width x height px`，不显示调试坐标链路。 |
| SMK-P0-SHOT-011 | 自动 | 四方向坐标 | 从左上到右下、右下到左上、右上到左下、左下到右上拖拽时，最终截图像素区域一致，且起点不会向左上多扩 1～2px。 |
| SMK-P0-SHOT-012 | 自动 | 半像素边界 | CoreGraphics 对半 point 截图会在垂直方向少 1px；区域截图必须先取整数 point 外包，再按像素 crop 回目标尺寸。 |

## P0 放大镜

| ID | 类型 | 模块 | 测试点 |
| --- | --- | --- | --- |
| SMK-P0-MAG-001 | 自动 | 截图放大镜 | 激活截图时 mouse move 显示 5x 像素化放大，使用更大的 41px source window，并在放大镜内显示当前倍率。放大镜十字线和实际截图坐标一致。 |
| SMK-P0-MAG-002 | 手动 | 截图放大镜 | 右下角放不下时自动换到其他可完整显示位置。 |

## P0 标注与编辑

| ID | 类型 | 模块 | 测试点 |
| --- | --- | --- | --- |
| SMK-P0-ANN-001 | 自动 | 标注工具 | 箭头、矩形、文字、马赛克、放大镜、Pen工具和 renderer 都存在。 |
| SMK-P0-ANN-002 | 手动 | 编辑窗口 | 截图后可添加每类标注，撤销、复制、保存可用。 |
| SMK-P0-ANN-003 | 自动 | Pen | Pen 以自由路径写字/画线，并支持 `S/M/L` 三种笔触大小；默认 `M`，大小合并到 Pen 工具按钮内，不再占用独立 toolbar 控件。 |
| SMK-P0-ANN-004 | 自动 | Pen | Pen 拖拽路径包含 mouse down、drag、mouse up 终点；预览和导出都按轨迹使用当前颜色绘制，不再沿用旧白底填充逻辑。 |
| SMK-P0-ANN-005 | 自动 | 文字弹窗 | 文字标注使用自定义弹窗，支持多行输入、颜色、字号和实时预览，替代旧的简单 alert。 |
| SMK-P0-ANN-006 | 自动 | 标注变换 | 箭头、矩形、文字、马赛克、放大镜可点击选中、拖动、拖拽手柄缩放；toolbar 色板只影响新建标注，非文字标注创建后不改色，文字可双击编辑内容和颜色。 |
| SMK-P0-EDITOR-001 | 自动 | 编辑窗口 | 截图后窗口使用 Photoshop 风格棋盘底，toolbar 左侧信息块上方显示当前缩放比例、下方显示 `width x height px`，缩放 slider 并入左侧信息块底色且默认近透明，截图内容居中；toolbar 紧凑、操作组右对齐且右侧按钮保持单行整体，默认/最小窗口宽度可完整展开工具条，支持 current、100%、Best Fit、Fit In、最高 800% 缩放和拖拽/滚动查看。 |
| SMK-P0-EDITOR-002 | 自动 | 导出一致性 | 编辑器缩放只影响显示，不影响保存/复制/拖拽导出的原始像素尺寸。 |
| SMK-P0-EDITOR-003 | 自动 | 标注坐标 | 编辑器在任意缩放比例下，将鼠标位置反算到图片像素坐标，标注保存位置不漂移。 |
| SMK-P0-EDITOR-004 | 自动 | 缩放范围 | 编辑器 Best Fit、Fit In 和 slider 覆盖 `1:8` 到 `8:1`，并在高缩放下保持可滚动查看。 |
| SMK-P0-EDITOR-005 | 自动 | toolbar | 左侧信息块按 `zoom` 在上、`width x height px` 在下显示，并承载透明缩放 slider 和相邻的适应按钮；右侧工具、窄色板、操作按钮保持单行整体，Pen 大小显示在 Pen 工具段内。 |
| SMK-P0-EDITOR-006 | 自动 | 文字移动 | 文字标注默认尺寸按内容长度和字号估算；文字工具命中已有文字时可选择并拖动，移动范围限制在图片内。 |

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
| SMK-P0-HOT-004 | 自动 | 快捷键设置 | 设置窗口录制新快捷键时先暂停当前热键；冲突时提示并恢复旧热键；Esc、关闭或未完成选择时恢复设置前热键；成功注册后才保存。 |

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
| SMK-P0-BUNDLE-006 | 自动 | 启动确认 | 编译完成并测试通过后，自动停止旧进程、安装到稳定路径并启动新的 SnapMark app。 |
| SMK-P0-BUNDLE-007 | 自动 | 关于菜单 | 菜单显示 `关于 V<version> <HHMMSS>`，并且构建脚本写入 bundle build time。 |

## 架构与资源

| ID | 类型 | 模块 | 测试点 |
| --- | --- | --- | --- |
| SMK-P0-ARCH-001 | 自动 | 模块拆分 | 截图选择、放大镜、窗口探测按模块拆分且文件大小受控。 |
| SMK-P0-PERF-001 | 手动 | 资源 | 进入截图前后观察 Activity Monitor，截图 overlay 关闭后无长期 CPU 占用。 |

## QA 文档

| ID | 类型 | 模块 | 测试点 |
| --- | --- | --- | --- |
| SMK-QA-001 | 自动 | 测试计划 | 测试计划文档覆盖 P0 自动化功能点。 |
| SMK-QA-002 | 自动 | UI 总览 | `Docs/UIOverview.MD` 包含状态栏菜单、截图选择、编辑窗口、设置窗口、文字弹窗说明，并保存总览截图 `Docs/Images/snapmark-ui-overview.png`。 |

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
