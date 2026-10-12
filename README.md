# fm1-daemon

> 🤖 **本项目由 AI 生成。**
> 代码、文档与安装脚本均由 [OpenCode](https://opencode.ai) 上的 AI 助手（DeepSeek）根据用户需求编写；用户负责提出需求、验证结果与承担使用后果。

一个极简的 `org.freedesktop.FileManager1` D-Bus 守护进程：**常驻抢占这个名字，把"打开所在文件夹"之类的请求转发给你指定的文件管理器**（默认 Thunar）。

---

## 背景：我遇到的问题

> 下面是我（项目发起人）当时遇到的实际情况，也是这个项目存在的原因。

**环境**

- 发行版：Arch Linux
- 窗口管理器：niri
- 文件管理器：Thunar 4.20（已用 `xdg-mime default thunar.desktop inode/directory` 设为默认）
- 系统里同时还装着 Nautilus 51（GNOME Files）—— 它是 `xdg-desktop-portal-gnome` 的依赖（录屏要用），**不能卸载**
- 桌面壳：Noctalia，会随壁纸重新生成 GTK 主题（`~/.config/gtk-*/gtk.css`），所以 Thunar 的颜色要能跟着壁纸变

**现象**

1. 在 Firefox、微信（WeChat）等应用里点"打开所在文件夹 / 在文件夹中显示"，弹出来的却是 **GNOME 的 Nautilus**，不是我设的 Thunar。
2. 可是 `xdg-mime query default inode/directory` 和 `gio mime inode/directory` 都显示默认应用是 Thunar；`xdg-open .` 也确实打开 Thunar。
3. 最迷惑的是它**时好时坏**：有时正常打开 Thunar，过一会儿（或做过某些操作后）又变回 Nautilus。

**排查后的结论**

- 这类"打开所在文件夹"在 Firefox / Chromium 系 / WeChat 里走的是 **D-Bus `org.freedesktop.FileManager1.ShowItems`**，和 `xdg-open` / GIO 默认应用是**两条完全不同的路径**，所以改 `mimeapps.list` 对它没有用。
- 这个 D-Bus 名字是**"先占先得"**：只要系统里有一个 Nautilus 实例在运行，它就会长期霸占这个名字，之后所有应用的请求都归它——直到它退出为止。
- 而 Nautilus 会被这些地方拉起来：
  - WeChat 的兜底逻辑：直接执行 `nautilus --select <文件>`
  - 我自己设的一个"打开 Nautilus"的快捷键
  - 任何一次手动打开 Nautilus

**试过、但都不够好的办法**

| 办法 | 为什么不够用 |
|---|---|
| 把 `~/.local/share/dbus-1/services/org.freedesktop.FileManager1.service` 指向 Thunar | 只在"名字没人占"时决定激活谁；Nautilus 一旦已在跑就完全无效 |
| 让 `thunar --daemon` 常驻抢占名字 | 能占住名字，但 Thunar 是 GTK3、**不热重载主题**，换壁纸后 Thunar 的颜色不会跟着变 |
| 在 PATH 里放一个 `nautilus` 包装脚本（转发给 Thunar） | 只能挡住"命令行启动 nautilus"，挡不住已经跑起来的实例，也不是根本解法 |

**最终解决**

让一个**无界面的常驻守护进程**（就是本项目）占住 `org.freedesktop.FileManager1`，收到请求后按配置去调用 Thunar：

- 守护进程跟 GTK / 主题无关，常驻也不会造成"颜色不更新"；
- Thunar 变成按需启动，每次都是新进程 → 颜色永远跟当前主题一致；
- 名字一直被占着 → Nautilus 再也抢不走。

---

## 它解决什么问题

在 GNOME 之外的桌面环境（niri / Hyprland / i3 / Sway …）上，"打开所在文件夹""在文件夹中显示"这类操作通常有两条路径：

1. **GIO 默认应用**（读 `mimeapps.list` / `xdg-mime`）—— 这条一般能正常改成 Thunar。
2. **D-Bus `org.freedesktop.FileManager1.ShowItems`** —— 很多应用（Firefox、Chromium 系、WeChat…）实际走的是这条。

第二条路径**不看** `mimeapps.list`，而是"**谁先占用 `org.freedesktop.FileManager1` 这个名字，请求就归谁**"。只要系统里装了 Nautilus（GNOME Files），并且有**任意一个** Nautilus 实例在跑，它就会长期霸占这个名字——于是所有应用的"打开所在文件夹"都变成 Nautilus，哪怕你已经把 `inode/directory` 改成了 Thunar。

常见的绕法都有各自的短板：

| 做法 | 短板 |
|---|---|
| 用户级 D-Bus service 覆盖（`~/.local/share/dbus-1/services/org.freedesktop.FileManager1.service`） | 只能决定"名字空闲时激活谁"；Nautilus 已在跑就完全无效 |
| 让 Thunar 自己常驻抢占（`thunar --daemon`） | Thunar 是 GTK3，**不热重载主题**，换壁纸/配色后颜色不会更新 |
| wrapper 脚本拦截 `nautilus` 命令 | 只盖得住"命令行启动 nautilus"，盖不住已经在跑的实例 |

`fm1-daemon` 换了个思路：**占名字的，是一个无界面的纯 D-Bus 守护进程**。

## 原理

```
应用(Firefox / WeChat)
        │  ShowItems(URIs)
        ▼
org.freedesktop.FileManager1        ← 这个名字由 fm1-daemon 持有
        │
        ▼
   fm1-daemon  ──按配置执行──▶  thunar --window <文件...>
```

- 守护进程本身跟 GTK / 主题无关，常驻也**不会**出现"颜色不更新"的问题；
- Thunar 变成**按需启动**，每次都是新进程 → 颜色永远跟随当前主题；
- 因为名字一直被占着，Nautilus 无论怎么启动都**抢不走**。

## 依赖

- `python-dbus`
- `python-gobject`

Arch Linux：

```bash
sudo pacman -S python-dbus python-gobject
```

## 安装

```bash
git clone https://github.com/SoooooUL/fm1-daemon.git
cd fm1-daemon
./install.sh
```

或者手动：

```bash
install -Dm755 fm1-daemon ~/.local/bin/fm1-daemon
install -Dm644 config.example ~/.config/fm1-daemon/command

# D-Bus service（让 dbus 激活时也拉起它）
mkdir -p ~/.local/share/dbus-1/services
sed "s|@HOME@|$HOME|g" dbus/org.freedesktop.FileManager1.service \
    > ~/.local/share/dbus-1/services/org.freedesktop.FileManager1.service

# systemd user service（开机自启）
mkdir -p ~/.config/systemd/user
sed "s|@HOME@|$HOME|g" systemd/fm1-daemon.service \
    > ~/.config/systemd/user/fm1-daemon.service
systemctl --user daemon-reload
systemctl --user enable --now fm1-daemon.service
```

## 配置

编辑 `~/.config/fm1-daemon/command`，**一行一个参数**（也可用环境变量
`FM1_DAEMON_CONFIG` 指定其他路径）。默认内容：

```
/usr/bin/thunar
--window
```

也就是每次执行 `thunar --window <文件路径...>`。

换成别的文件管理器，例如 Nemo：

```
/usr/bin/nemo
```

想在终端里跑 TUI 文件管理器（例：kitty + yazi）：

```
/usr/bin/kitty
-e
yazi
```

改完保存即生效（守护进程会监听配置文件变化自动热重载，
日志里会记一行 `config reloaded: ...`）：

```bash
journalctl --user -u fm1-daemon -f
```

> 注：若配置文件被临时清空或删除，热重载会保留当前生效的旧值，
> 不会回退到默认 Thunar；下次写入有效内容后自动切换。

## 验证

```bash
# 名字归谁？（应显示 fm1-daemon 的 python3 进程）
busctl --user list | grep -i org.freedesktop.FileManager1

# 手动模拟一次"打开所在文件夹"
dbus-send --session --print-reply --dest=org.freedesktop.FileManager1 \
  /org/freedesktop/FileManager1 org.freedesktop.FileManager1.ShowItems \
  array:string:"file:///tmp" string:""

# 实时日志（每次请求都会记一行 "opened: ..."）
journalctl --user -u fm1-daemon -f
```

## 卸载

```bash
systemctl --user disable --now fm1-daemon
rm -f ~/.config/systemd/user/fm1-daemon.service
rm -f ~/.local/bin/fm1-daemon
rm -f ~/.local/share/dbus-1/services/org.freedesktop.FileManager1.service
rm -rf ~/.config/fm1-daemon
systemctl --user daemon-reload
```

## 已知限制

- `ShowItemProperties` 目前只是打开所在目录，没有实现真正的"属性对话框"。
- 目标文件不存在时，会由所选文件管理器自行报错。
- 实现的 D-Bus 方法：`ShowItems`、`ShowFolders`、`ShowItemProperties`、`Exit`。
- 名字靠"先占先得"，所以要在 Nautilus 之前启动它（本仓库用 systemd user service 在登录时启动来保证这点；`Restart=always` 也会在竞争失败后自动重试接管）。

## 许可

MIT —— 见 [LICENSE](LICENSE)。
