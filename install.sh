#!/bin/sh
# fm1-daemon 安装脚本（用户级，无需 root）
set -eu

here=$(cd "$(dirname "$0")" && pwd)

echo "==> 安装脚本到 ~/.local/bin/fm1-daemon"
install -Dm755 "$here/fm1-daemon" "$HOME/.local/bin/fm1-daemon"

echo "==> 安装配置到 ~/.config/fm1-daemon/command"
if [ -e "$HOME/.config/fm1-daemon/command" ]; then
    echo "    (已存在，保留原有配置)"
else
    install -Dm644 "$here/config.example" "$HOME/.config/fm1-daemon/command"
fi

echo "==> 安装 D-Bus service"
mkdir -p "$HOME/.local/share/dbus-1/services"
sed "s|@HOME@|$HOME|g" "$here/dbus/org.freedesktop.FileManager1.service" \
    > "$HOME/.local/share/dbus-1/services/org.freedesktop.FileManager1.service"

echo "==> 安装 systemd user service"
mkdir -p "$HOME/.config/systemd/user"
sed "s|@HOME@|$HOME|g" "$here/systemd/fm1-daemon.service" \
    > "$HOME/.config/systemd/user/fm1-daemon.service"

echo "==> 启动 fm1-daemon"
systemctl --user daemon-reload
systemctl --user enable --now fm1-daemon.service

echo
echo "完成。当前状态："
systemctl --user --no-pager status fm1-daemon.service | head -n 8
