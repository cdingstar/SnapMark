# SnapMark

SnapMark 是一个 macOS 状态栏截图和标注工具，使用 Swift + AppKit 开发。

## 功能

- 区域截图
- 全屏截图
- 箭头、矩形、文字标注
- 马赛克
- 放大镜
- 自动保存到 `~/Downloads`，可在设置中修改
- 全局快捷键
- 复制到剪贴板
- 从编辑窗口拖拽 PNG 到其他应用
- 设置窗口：快捷键、存储目录、开机启动

## 快捷键

- `Command + Control + A`: 区域截图
- 启动时如果 `Command + Control + A` 被占用，会自动尝试 `Command + Control + S`，再尝试 `Command + Control + Q`
- 如果三个默认快捷键都不可用，会提示用户到设置中重新选择
- 编辑窗口内 `Command + Z`: 撤销上一个标注

## 开发运行

```bash
swift run SnapMark
```

首次截图时，macOS 会要求屏幕录制权限。如果没有弹出授权，请到：

```text
系统设置 > 隐私与安全性 > 屏幕录制
```

允许 SnapMark 或当前运行它的终端应用。

## 构建 app

```bash
chmod +x Scripts/build_app.sh
Scripts/build_app.sh
open dist/SnapMark.app
```

构建结果位于：

```text
dist/SnapMark.app
```

`Scripts/build_app.sh` 会优先使用本机的 `Apple Development` 证书签名，保持稳定的代码签名身份。这样 macOS 的屏幕录制权限会绑定到同一个 SnapMark app，避免每次重新构建后都被当成新的临时应用。

如果第一次从旧的 ad-hoc 签名切换到开发证书签名，macOS 仍可能需要重新授权一次。授权一次后，后续使用同一个 bundle id 和同一个签名证书构建，一般不需要重复授权。

也可以显式指定签名身份：

```bash
CODE_SIGN_IDENTITY="Apple Development: cdingstar@gmail.com (56CN6FY9NG)" Scripts/build_app.sh
```

## 自动化测试

```bash
chmod +x Scripts/test.sh
Scripts/test.sh
```

功能测试清单见：

```text
Docs/TestPlan.MD
```

`Scripts/build_app.sh` 会在 release build、资源打包和签名完成后自动执行 testcase。新增功能时需要同步更新 `Docs/TestPlan.MD` 和 `Tests/run_functional_tests.py`，保证构建会检查新功能。

## 安装到稳定路径

开发构建产物位于 `dist/SnapMark.app`。如果要让 macOS 隐私授权稳定识别 SnapMark，建议安装到固定路径：

```bash
chmod +x Scripts/install_app.sh
Scripts/install_app.sh
```

默认优先安装到：

```text
/Applications/SnapMark.app
```

如果当前用户没有权限写入 `/Applications`，脚本会回退到：

```text
~/Applications/SnapMark.app
```

之后从安装路径启动 SnapMark，并在第一次区域截图时授权屏幕录制权限。
