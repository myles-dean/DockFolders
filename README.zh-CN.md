<p align="center">
  <img src="docs/logo.png" width="160" height="160" alt="Dock Folders 应用图标：深色圆角方框中的四个 App 图标">
</p>

<h1 align="center">Dock Folders</h1>

<p align="center">
  <a href="README.md">🌐 English</a>
  &nbsp;·&nbsp; <a href="README.zh-CN.md">🌐 简体中文</a>
</p>

<p align="center">
  <b>为 macOS 程序坞带来 iPhone 风格的 App 文件夹。</b><br>
  直接在程序坞中将 App 分组，点按即可在 Liquid Glass 弹窗中展开，让程序坞保持整洁。<br>
  免费开源，专为 macOS 26 Tahoe 打造。
</p>

<p align="center">
  <a href="https://github.com/myles-dean/DockFolders/releases/latest/download/DockFolders.dmg"><b>⬇︎ 下载 Dock Folders（DMG）</b></a>
  &nbsp;·&nbsp; <a href="#features">功能</a>
  &nbsp;·&nbsp; <a href="#install">安装</a>
  &nbsp;·&nbsp; <a href="#how-to-use-it">使用方法</a>
  &nbsp;·&nbsp; <a href="#faq">常见问题</a>
</p>

<p align="center">
  <img alt="macOS 26 Tahoe 或更新版本" src="https://img.shields.io/badge/macOS-26%20Tahoe%2B-111111?logo=apple&logoColor=white">
  <img alt="原生支持搭载 Apple 芯片的 Mac" src="https://img.shields.io/badge/Apple%20silicon-native-0a84ff">
  <img alt="使用 Swift 编写" src="https://img.shields.io/badge/Swift-SwiftUI%20%2B%20AppKit-f05138?logo=swift&logoColor=white">
  <img alt="MIT 许可证" src="https://img.shields.io/badge/license-MIT-34c759">
  <a href="https://github.com/myles-dean/DockFolders/releases/latest"><img alt="最新版本" src="https://img.shields.io/github/v/release/myles-dean/DockFolders?label=release"></a>
</p>

<p align="center">
  <a href="https://ko-fi.com/mylesdean_"><img alt="在 Ko-fi 上请作者喝杯咖啡" src="https://img.shields.io/badge/Buy%20me%20a%20coffee-FF5E5B?style=for-the-badge&logo=kofi&logoColor=white"></a>
</p>

<p align="center">
  <img src="docs/demo.gif" width="872" alt="Dock Folders 演示：指针移到程序坞，悬停并点按工具文件夹，在其上方的 Liquid Glass 弹窗中展开八个 App">
</p>

---

**Dock Folders** 为 Mac 程序坞加入类似 iPhone 和 iPad 的文件夹功能。将程序坞中的一个 App
拖到另一个 App 上即可创建文件夹；点按文件夹，里面的 App 就会以程序坞的图标大小在
Liquid Glass 弹窗中展开。你可以用它**整理程序坞**、**将程序坞中的 App 分组**，也能找回
**启动台原有的 App 文件夹**：macOS 26 Tahoe 用不支持文件夹的 App 视图替代了启动台。

没有菜单栏图标，不需要录屏权限，也不访问网络。它会安静地在后台运行，并在登录时打开。

<a id="features"></a>

## 功能

- **真正放在程序坞中的文件夹。** 每个文件夹都是一个程序坞图标，以 2×2 布局显示前四个
  App，并使用程序坞的名称标签；只要其中有 App 正在运行，图标下方就会显示运行指示圆点。
- **Liquid Glass 弹窗。** 点按文件夹，即可在 macOS 26 的透明玻璃弹窗中查看 App，图标大小、
  间距和放大效果均与程序坞相近。每页可显示 3、6、9 或 16 个 App，支持双指轻扫和分页圆点。
- **类似 iOS 的拖放操作。**
  - 将一个 App 拖到另一个 App 上并停留，出现**新建文件夹**后松开，按类别自动命名，
    例如“游戏”“效率与财务”“创意”等。
  - 将 App 拖到文件夹上并停留，文件夹会展开，松开即可放入。
  - 将一个文件夹拖到另一个文件夹上，即可**合并**。
  - 将 App 从已展开的文件夹中拖回程序坞，即可放回程序坞。
- **玻璃样式的右键菜单。** 文件夹中的 App 提供类似程序坞的菜单，包括窗口列表、显示所有
  窗口、隐藏、退出和强制退出。文件夹菜单提供重新命名、添加 App、清空文件夹和设置。
- **即时更新程序坞。** 添加和移除文件夹时不需要重新启动程序坞，因此不会闪烁壁纸或菜单栏。
- **可选的悬停打开。** 将指针停留在文件夹上即可打开。在“设置 → 通用”中，可用连续滑动条
  或数值输入分别调整打开、关闭延迟，范围为 0–2 秒，默认均为 0.3 秒。关闭延迟也适用于通过
  点按打开的文件夹；指针回到文件夹或它的程序坞图标上时，会取消待关闭计时。
- **悬停时显示 App 名称。** 将指针移到文件夹中的 App 图标上，即可在其上方显示程序坞风格的
  玻璃名称气泡，图标放大时也能跟随。名称过长时会截断，以适应屏幕可见区域。
- **英文和简体中文。** 首次启动时先选择语言，再设置权限；也可以在“设置 → 通用 → 语言”
  中即时切换。中文操作名称采用 macOS 术语。
- **可选：仅在文件夹中显示打开的 App。** 需要关闭部分系统完整性保护，
  [详见下文](#optional-open-apps-only-in-their-folders)。
- **原生外观与辅助功能支持。** 支持浅色、深色和色调外观；打开“降低透明度”后会使用不透明
  背景。程序坞位于屏幕底部、左侧或右侧，以及是否自动隐藏，均可使用。

<a id="install"></a>

## 安装

1. **[下载 DockFolders.dmg](https://github.com/myles-dean/DockFolders/releases/latest/download/DockFolders.dmg)**，
   将 **Dock Folders** 拖到**应用程序**文件夹。
2. 打开 App 并选择语言。随后，设置窗口会引导你在“系统设置 → 隐私与安全性”中允许两项权限：
   - **辅助功能**：让 App 可以访问程序坞，并在你点按时打开文件夹。
   - **App管理**：程序坞中的每个文件夹都由一个小型 App 表示，Dock Folders 需要创建和更新
     这些 App，而 macOS 要求获得此权限才能让一个 App 修改另一个 App。
3. 将程序坞中的一个 App 拖到另一个 App 上并停留，直到出现**新建文件夹**。

也可以使用 [Homebrew](https://brew.sh)：

```bash
brew tap myles-dean/tap
brew trust myles-dean/tap
brew install --cask dock-folders
```

需要搭载 Apple 芯片的 Mac，运行 **macOS 26 Tahoe** 或更新版本。

<a id="how-to-use-it"></a>

## 使用方法

| 操作 | 方法 |
| --- | --- |
| 创建文件夹 | 将程序坞中的一个 App 拖到另一个 App 上并停留，出现**新建文件夹**后松开；也可以在设置中点按 **+** |
| 将程序坞中的 App 放入文件夹 | 拖到文件夹上并停留，待文件夹展开后松开，可放在图标上或弹窗内。一个 App 同时只能属于一个文件夹，因此会从原文件夹中移出 |
| 将文件夹中的 App 放回程序坞 | 从已展开的文件夹中拖出，放到程序坞中的目标位置 |
| 添加任意 App | 从访达或 App 窗口拖到程序坞中的文件夹上；也可以在设置的 App 列表上方点按 **+** |
| 打开或关闭文件夹 | 点按以打开。移开指针后，会按设定的关闭延迟关闭；点按外部或启动 App 也会关闭 |
| 翻页 | 双指轻扫，或点按分页圆点 |
| 重新排列文件夹中的 App | 拖移图标；在左侧或右侧边缘停留可切换页面 |
| 重新命名文件夹或添加 App | 右键点按文件夹 → **重新命名…**（打开设置并选中名称，方便编辑）或**添加 App…**（打开设置及 App 选择窗口） |
| 将文件夹中的 App 全部放回程序坞 | 右键点按文件夹 → **清空文件夹**。App 会替代文件夹回到程序坞，文件夹随之移除。此操作会刷新一次程序坞，因为未运行的 App 只能通过这种方式重新添加 |
| 移除或重新排列 App、显示或隐藏程序坞中的文件夹、删除文件夹或调整选项 | 右键点按文件夹 → **设置…**，或从聚焦打开 Dock Folders |
| 从文件夹中移出某个 App | 右键点按该 App → 选项 → **从文件夹中移除**或**移到程序坞** |
| 设置每页 App 数量（3、6、9 或 16）、图标下方的名称或运行指示标记、图标大小及放大效果 | 设置 → ⚙︎ 通用 → **文件夹内部** |
| 调整悬停打开及打开、关闭延迟 | 设置 → ⚙︎ 通用 → **悬停时打开文件夹**、**打开延迟**和**关闭延迟** |
| 更改界面语言 | 设置 → ⚙︎ 通用 → **语言**，选择跟随系统、English 或简体中文 |
| 重新排列程序坞中的文件夹 | 像普通程序坞图标一样拖移 |

可以从文件夹的右键菜单打开设置，也可以从聚焦或“应用程序”文件夹再次打开 Dock Folders。
“⚙︎ 通用”中提供语言、每页 App 数量、图标下方的名称或运行指示标记、图标大小、放大、
悬停打开及打开/关闭延迟，以及下方介绍的可选功能。

<a id="faq"></a>

## 常见问题

**Dock Folders 会修改我的 App 吗？**

不会。你的 App 会保持原样。每个文件夹都是一个独立的小型 App，保存在
`~/Library/Application Support/Dock Folders/Folders/`，并以自己的图标出现在程序坞中。

**为什么需要 App管理权限？**

创建、重新命名和移除文件夹，都需要创建或更新对应的小型 App。macOS 会在一个 App 修改
另一个 App 前请求权限。Dock Folders 只会操作它自己创建的文件夹 App。

**为什么 macOS 提示添加了程序坞图标扩展？**

每个文件夹图标都由一个小型程序坞图标插件绘制，macOS 会提示新增的插件。文件夹会复用少量
标识槽位，因此通常只有前几次会看到提示。

**为什么 Mac 锁定时，程序坞有时会刷新？**

程序坞只在启动时读取新名称，以及重新添加的未运行 App。因此，Dock Folders 会将这些更改
留到不易察觉的时候应用：Mac 锁定或显示器进入睡眠时。设置中的**立即更新**可立即应用。

**能否让打开的 App 只显示在文件夹里，不再单独出现在程序坞中？**

macOS 会为每个打开的 App 显示独立的程序坞图标，且只有程序坞自身可以隐藏这些图标。
关闭部分系统完整性保护后，Dock Folders 可以实现此功能，详见下文。

**是否收集数据或使用互联网？**

不会。App 中没有任何网络代码。

**如何卸载？**

右键点按每个文件夹 → **清空文件夹**，将 App 放回程序坞；在设置中退出 Dock Folders，
再将它移到废纸篓，并删除 `~/Library/Application Support/Dock Folders`。如果使用过可选的
程序坞辅助工具，请先在设置中点按**移除辅助工具…**。

<a id="optional-open-apps-only-in-their-folders"></a>

## 可选：仅在文件夹中显示打开的 App

“**设置 → 通用 → 仅在文件夹中显示打开的 App**”可以隐藏文件夹内 App 独立的程序坞图标。
App 只在文件夹中显示，但仍保留菜单栏、⌘-Tab 切换项，以及“强制退出”列表中的项目。
macOS 只允许程序坞自身完成此操作，因此与 [yabai](https://github.com/koekeishiya/yabai) 的
脚本扩展类似，这个功能需要关闭部分系统完整性保护。设置中会提供操作引导：

1. 在“macOS 恢复”中运行 `csrutil enable --without fs --without debug --without nvram`，然后重新启动。
2. 在搭载 Apple 芯片的 Mac 上运行 `sudo nvram boot-args=-arm64e_preview_abi`，然后再次重新启动。
3. 打开此选项。Dock Folders 会请求一次管理员密码，用于安装小型辅助工具
   （`/Library/PrivilegedHelperTools/com.mylesdean.DockFolders.helper`，一个 launchd 守护进程）。

每次程序坞启动时，辅助工具都会将 `DockFoldersHook.dylib` 载入其中。它在程序坞内部阻止为
文件夹中的 App 添加独立图标，并将已有图标交给程序坞原本处理“App 转入后台”的机制。
如果程序坞在载入后连续退出，例如 macOS 更新后发生变化，辅助工具会自行暂停，设置中也会
显示提示。关闭此选项会重新启动程序坞，使其不再载入辅助代码；**移除辅助工具…**会卸载它。
若要重新打开 SIP，请在“macOS 恢复”中运行 `csrutil enable`，并运行 `sudo nvram -d boot-args`。

> [!WARNING]
> SIP 有助于保护 Mac 免受恶意软件侵害，关闭部分保护会降低安全性。此选项属于实验性功能：
> 目前仅通过阅读 macOS 26.6 程序坞的代码进行检查，尚未在关闭 SIP 的 Mac 上实际运行验证。

## 从源码构建

```bash
git clone https://github.com/myles-dean/DockFolders.git
cd DockFolders
./build.sh            # 构建 build/Dock Folders.app
./build.sh install    # 同时拷贝到 /Applications 并打开
./build.sh release    # 生成使用 Developer ID 签名的 build/DockFolders.dmg；设置 NOTARY_PROFILE 可进行公证
```

需要 Xcode 26 命令行工具，没有 Xcode 工程。如果本机存在“Apple Development”签名身份，
开发构建会使用它签名，以便重新构建后保留权限。

<details>
<summary><b>工作原理</b>（技术细节）</summary>

## 工作原理

不截取屏幕；除非打开上述可选功能，否则也不会向程序坞内载入代码，所有操作都使用系统机制。

- **文件夹图标。** 每个文件夹都是保存在 `~/Library/Application Support/Dock Folders/Folders/`
  的小型 App 包，添加到程序坞自己的 App 列表中。它的图标由**程序坞图标插件**
  （`NSDockTilePlugIn`，与“日历”显示日期的机制相同）绘制，因此 2×2 预览可以实时更新。
  后台主程序渲染图像，插件负责显示。macOS 只有在 App 至少启动过一次后，才会载入其第三方
  程序坞插件，因此每个新建的分组小程序都会在不可见状态下带 `--register` 参数启动一次。
- **点按。** Quartz 事件监听器会先于程序坞收到文件夹图标的点按事件，并打开弹窗，而不是
  启动分组小程序。拖移事件会重新发送给程序坞，因此仍可排列图标。如果 Dock Folders 未运行，
  点按文件夹会启动分组小程序，再由它启动 Dock Folders 并打开文件夹。
- **弹窗。** 使用不激活应用的面板，让当前 App 保持在最前面。SwiftUI 的 `glassEffect` 配合
  自定义气泡形状，使其与程序坞的浅色、深色或色调玻璃外观相协调。
- **保持程序坞显示。** 指针位于弹窗中，或正在移向弹窗时，通过辅助功能将程序坞置于键盘
  焦点状态。这样可以让自动隐藏的程序坞继续显示，而无需关闭自动隐藏，避免全屏和平铺窗口
  改变大小。指针回到程序坞后便释放该状态，让程序坞自身的悬停和放大效果继续工作。
- **跟随图标。** 每一帧都会读取文件夹图标的位置，将弹窗箭头放在程序坞原本绘制名称标签的
  位置：箭头高 5 pt，尖端位于图标顶部向内 7.5 pt 处。这样可以避开程序坞，并将原有名称
  标签遮在弹窗后面；玻璃会模糊标签，再用一层淡淡的中性色遮罩减弱残留。
- **空文件夹。** 在文件夹内将最后一个 App 移出，无论是拖出、**移到程序坞**还是**从文件夹中
  移除**，都会像 iOS 一样删除该文件夹。在设置中创建或清空的空文件夹则会保留，但不显示在
  程序坞中；添加第一个 App 后会加入程序坞，除非之前关闭过**在程序坞中保留**，该选项会记住。
- **无需重新启动即可修改程序坞。** 重新启动程序坞会重绘壁纸和菜单栏，因此 Dock Folders 尽量
  避免这种做法，而是通过程序坞自身的右键菜单操作：**选项 → 在程序坞中保留 / 从程序坞中移除**，
  使用辅助功能按 Mac 的语言点按；菜单会短暂显示。添加文件夹时，它的小程序会临时运行，
  程序坞因此将其作为普通运行中的 App 显示，再通过**在程序坞中保留**固定。移除时使用
  **从程序坞中移除**，并显示程序坞原有的消失动画；如果仅退出运行中的图标，反而会先出现
  运行指示圆点。新文件夹会出现在程序坞 App 区域的末尾。
- **将 App 拖入文件夹。** 程序坞负责处理自己图标的拖移，也会挪动其他图标为目标位置留出空间。
  Dock Folders 通过事件监听器跟踪拖移，并记录开始时各文件夹的位置。将 App 停留在文件夹上
  片刻，文件夹就会带着轮廓展开；松开并放在图标上或弹窗内即可加入，程序坞随后移除原图标。
  快速经过不会触发，因此普通排列操作不受影响。
- **通过拖移创建文件夹。** 将 App 拖到另一个 App 上并停留，会在其上方显示与程序坞名称标签
  相同风格的**新建文件夹**提示。松开后，两个 App 的图标会一起离开程序坞，新文件夹出现在
  原来的位置：先运行文件夹小程序，让程序坞像添加普通运行中的 App 一样加入图标，再向程序坞
  单独发送拖移事件，将图标移动到指针下。程序坞会将图标放在真实指针所在位置，所以此时指针
  必须仍在程序坞上。移动运行中的 App 图标也会将其保留在程序坞中，无需打开菜单。
- **文件夹名称。** 类似 iOS，根据 App 声明的 App Store 类别（`LSApplicationCategoryType`）
  自动命名。两个游戏会命名为“游戏”；相关类别使用共同分组名，例如“创意”“效率与财务”
  或“工具”；否则使用被拖到的目标 App 的类别。未声明类别的 App 则使用“文件夹”。
- **将 App 拖出文件夹。** 图标移过文件夹边缘后，会变成与访达拖移 App 相同的真实拖移操作，
  程序坞因此会留出空间，并将它加入松开的位置。只以链接形式提供，且仅在程序坞上接受；
  在其他位置松开会滑回原位。
- **将更改留到不打扰操作时应用。** 少数更改仍需重新启动程序坞，包括新名称，以及将未运行的
  App 放回程序坞。它们会等到 Mac 锁定或显示器进入睡眠时应用，避免看到重新启动过程；设置中
  的**立即更新**可立即应用。如果 Dock Folders 先退出，下次会从程序坞重新找回待更新的名称。
- **玻璃效果。** 弹窗使用透明的 Liquid Glass 显示后方内容，并带有类似程序坞的清晰 1 pt 边缘，
  顶部最亮。深色模式下，标签和菜单也采用程序坞较深的色调。打开**降低透明度**后，所有背景
  都会像 macOS 其他界面一样变为不透明。
- **菜单。** 右键菜单使用 Liquid Glass 自行绘制，而非 `NSMenu`，因为原生菜单会从程序坞
  夺走键盘焦点，导致程序坞自动隐藏。

</details>

## 限制

以下限制来自 macOS 对其他 App 操作程序坞的约束；若要改变，需要在程序坞内部运行代码，
而这需要关闭相应的系统完整性保护：

- **没有图标“抖动”模式。** 程序坞自行绘制图标，其他 App 无法让它们播放动画。创建文件夹
  的方法是将一个 App 拖到另一个 App 上并停留。
- **无法向程序坞原生的 App 右键菜单添加项目。** 文件夹自己的菜单由 Dock Folders 使用玻璃
  效果绘制。
- **首次使用时会出现程序坞图标扩展提示。** 每个文件夹的图标由小型程序坞图标插件绘制，macOS
  会提示新增的插件。文件夹会复用少量标识符槽位，因此只在槽位首次使用时出现提示，大致相当于
  同时保留的文件夹数量，而不是每次创建都提示。
- **打开的 App 也会出现在程序坞中**，除非使用[可选功能](#optional-open-apps-only-in-their-folders)。
  macOS 会显示每个运行中的 App，只有程序坞自身可以隐藏它们。
- **文件夹展开时，其图标会变暗**，仅发生在使用自动隐藏程序坞时。保持程序坞显示需要进入
  键盘操作状态，而该状态总会标记一个项目。标记文件夹图标会使其变暗；标记其他项目则会显示
  不相关的名称标签。
- **只有重新启动程序坞后，新名称才会更新。** 会在 Mac 下次锁定或进入睡眠时自动处理，
  也可以点按设置中的**立即更新**。将未运行的 App 通过**移到程序坞**放回程序坞，也需要
  等待刷新；直接拖到程序坞则不需要。
- **即时修改程序坞时，菜单会短暂显示。** Apple 的添加接口 `CoreDockAddFileToDock` 只允许
  访达和 Safari 使用，因此需通过程序坞自身的**在程序坞中保留 / 从程序坞中移除**操作，
  移除图标时显示程序坞原有的消失动画。
- **无法提供各 App 特有的程序坞菜单项目**，例如“音乐”的播放控制、“备忘录”的新建备忘录。
  这些项目不向其他 App 开放，因此文件夹中只提供标准菜单项目。

## 项目结构

```text
Sources/Agent/       后台主程序：事件监听、弹窗、菜单、程序坞及文件夹管理
Sources/Stub/        放在程序坞中、代表每个文件夹的小型 App
Sources/TilePlugin/  绘制文件夹图标的程序坞插件
Sources/DockHook/    可选的程序坞辅助工具和载入代码，仅用于关闭部分 SIP 保护时
Sources/Shared/      各部分共享的常量
Resources/           Info.plist 与中英文资源
docs/                本页使用的图片
build.sh             构建、签名、安装和打包脚本
```

文件夹数据保存在 `~/Library/Application Support/Dock Folders/folders.json`。

## 参与贡献

欢迎提交 Issue 和 Pull Request。Dock Folders 依赖 macOS 26 程序坞的行为，因此报告问题时，
请尽量提供 macOS 版本和程序坞设置，包括位置、自动隐藏和放大选项。

## 许可证

[MIT](LICENSE) © 2026 Myles Dean。可选程序坞辅助工具的加载器改编自
[yabai](https://github.com/koekeishiya/yabai)（MIT，© Åsmund Vikane），其中 arm64e 路径的实现
参考了 [Jeremy Legendre](https://github.com/jslegendre) 的工作。
