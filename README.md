# LaunchOS

LaunchOS 是一个轻量 macOS 启动台替代品，面向 macOS 26 取消 Launchpad 后的本机应用启动场景。

当前功能：

- 扫描 `/Applications`、`/System/Applications`、`/System/Applications/Utilities` 和 `~/Applications`
- 自动读取旧 Launchpad 数据库：`$(getconf DARWIN_USER_DIR)/com.apple.dock.launchpad/db/db`
- 保留旧页面顺序和文件夹分组，未在旧布局中的新应用会追加到“新增应用”页
- 支持动态自适应网格、搜索、刷新、打开应用、在 Finder 中显示应用

本地运行：

```bash
./script/build_and_run.sh
```

验证构建并确认进程已启动：

```bash
./script/build_and_run.sh --verify
```
