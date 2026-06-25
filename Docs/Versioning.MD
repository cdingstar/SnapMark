# SnapMark Versioning

SnapMark 的 app 版本号使用：

```text
<major>.<auto-minor>.<MMDD>
```

当前规则：

- `major` 默认为 `1`，只允许手动修改。
- `auto-minor` 由 `Scripts/build_app.sh` 在每次成功完成 release app 编译后自动递增一次。
- `MMDD` 为编译当天的月日，例如 6 月 25 日为 `0625`。
- 初始版本为 `1.0.0625`；下一次成功执行 `Scripts/build_app.sh` 后会变成 `1.1.0625`。
- 构建脚本会把版本写入 `Resources/Info.plist` 的 `CFBundleShortVersionString` 和 `CFBundleVersion`，随后复制进 `.app` bundle。

版本状态保存在 `Resources/Version.env`：

```text
SNAPMARK_MAJOR=1
SNAPMARK_MINOR=0
```

如果未来需要手动升级大版本，只修改 `SNAPMARK_MAJOR`，并按需重置 `SNAPMARK_MINOR`。
