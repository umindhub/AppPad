<p align="center">
  <img src="AppPad/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="AppPad">
</p>

<h1 align="center">AppPad</h1>

<p align="center">
  原汁原味的启动台，重回 macOS 26+ —— 另附剪贴板、工作流、App 快捷键与窗口控制。
</p>

<p align="center">
  <a href="https://apppad.youmindhub.com">官网</a> ·
  <a href="README.md">English</a> · 简体中文
</p>

---

## 功能

### 启动台
- 完整还原经典 macOS 启动台，默认布局与系统顺序一致
- 四指捏合、菜单栏或点击程序坞中的 AppPad 打开（再次点击关闭）
- 文件夹、拖动排序 / 合并成文件夹，长按图标或按住 ⌥ 进入编辑模式
- 内置干净卸载：删除 App 的同时清理残留文件
- 网格搜索、页码指示（圆点 / 数字）、Liquid Glass 控件
- 背景：壁纸 / 白色 / 浅灰 / 深灰 / 自定义颜色，浅色与深色主题分别保存设置

### 剪贴板
- 文字和图片永久保存（原图片文件删除后依然可用）
- 常用收藏库，`⌘1`–`⌘0` 直接粘贴
- 来源 App 筛选和 `App名::` 搜索语法，右侧实时预览

### 工作流
- `⌘Space` 打开工作台：App 与工作流按使用频率统一排序
- 工作流可运行快捷指令、AppleScript 或 Shell 脚本，支持参数（如 `time 10`）
- 内置：清倒废纸篓、设置倒计时、设置闹钟、设置音量、退出所有 App、计算器……
- 权限声明由真实沙盒强制执行（允许一次 / 不允许 / 始终允许）
- 以 JSON 文件或链接导入、分享工作流

### App 快捷键
- 为任意 App 设置全局快捷键，类似 Raycast

### 窗口控制
- 左 / 右分屏（½ → ⅓ → ⅔）、最大化、还原、移到其他显示器，快捷键均可自定义

### 其他
- 只在菜单栏显示（无程序坞图标），支持开机启动
- `⌘⇧J` / `⌘⇧K` 在启动台、剪贴板、工作台之间变形切换
- 10 种语言：德、英、西、法、意、日、韩、荷、简中、繁中

## 系统要求

- macOS 26 或更高版本
- Xcode 27（从源码构建）

## 构建

1. 打开 `AppPad.xcodeproj`
2. 选择 Scheme：`AppPad Dev`、`AppPad Beta` 或 `AppPad`
3. 设置你自己的签名 Team，然后编译运行

依赖由 Swift Package Manager 自动拉取。

## 许可协议

AppPad 采用分层协议：

| 部分 | 协议 |
| --- | --- |
| AppPad 应用源码（下方未列出的全部内容） | [AGPL-3.0](LICENSE) |
| 内置工作流（`AppPad/Workflow/BuiltinWorkflows.swift`、`*.shortcut`） | [MIT](LICENSE-MIT) |
| 工作流格式规范 | [MIT](LICENSE-MIT) |
| 工作流市场中的第三方工作流 | [MIT](LICENSE-MIT)，版权归各作者 |

- **AGPL-3.0**：可以使用、修改和再发布 AppPad，但发布或通过网络提供的衍生作品必须同样以 AGPL-3.0 开放全部源码。
- **商业授权**：如需闭源或专有用途，请通过[官网](https://apppad.youmindhub.com)联系作者获取商业授权。
- **工作流采用 MIT**：任何人都可以自由编写、分享甚至出售工作流，也可以在其他工具中实现该工作流格式，不受 AGPL 约束。
- 你自己编写的工作流归你所有；提交到工作流市场的工作流须采用 MIT 协议。
- “AppPad” 名称与图标不在上述协议授权范围内，分支项目须使用不同的名称和图标。

## 参与贡献

欢迎提交 Issue 和 Pull Request。提交贡献即表示你同意该贡献按所修改部分的协议发布，并授权维护者同时以商业授权分发你的贡献。

## 致谢

- [GRDB.swift](https://github.com/groue/GRDB.swift) —— MIT 协议

---

© 2026 YouMindHub
