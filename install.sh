#!/usr/bin/env bash
# install.sh — vps-toolbox 一键安装脚本
#
# 用法：
#   curl -fsSL https://raw.githubusercontent.com/4258806/vps-toolbox/main/install.sh | sudo bash
#
# 做的事（只装两个文件，不改任何系统配置）：
#   1. 从 GitHub 下载 vps-toolbox.sh 到临时文件，确认非空、语法通过；
#   2. 装到 /usr/local/bin/vps-toolbox，加执行权限；
#   3. 建 /usr/local/bin/tbox 快捷方式，装完直接打 tbox 就能用。
# 重新跑一遍就是更新（会覆盖成最新版）。
# 本脚本不收集、不发送任何信息；零遥测。

set -eu

REPO="4258806/vps-toolbox"
BRANCH="main"
SCRIPT_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/vps-toolbox.sh"
DEST="/usr/local/bin/vps-toolbox"
LINK="/usr/local/bin/tbox"

err() { printf '\033[31m%s\033[0m\n' "$*" >&2; }
ok()  { printf '\033[32m%s\033[0m\n' "$*"; }

# 必须 root（/usr/local/bin 是 root 的）
if [ "$(id -u)" -ne 0 ]; then
    err "请用 root 或 sudo 运行：curl -fsSL ${SCRIPT_URL} | sudo bash"
    exit 1
fi

# 下载到临时文件，确认非空、语法通过再安装，避免装个坏的
tmp="$(mktemp /tmp/vps-toolbox-install.XXXXXX)" || { err "无法创建临时文件。"; exit 1; }
trap 'rm -f -- "$tmp"' EXIT

if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$SCRIPT_URL" -o "$tmp" || { err "下载失败，请检查网络后重试。"; exit 1; }
elif command -v wget >/dev/null 2>&1; then
    wget -q "$SCRIPT_URL" -O "$tmp" || { err "下载失败，请检查网络后重试。"; exit 1; }
else
    err "需要 curl 或 wget，请先安装其中一个。"
    exit 1
fi

[ -s "$tmp" ] || { err "下载的文件是空的，安装中止。"; exit 1; }
bash -n "$tmp" || { err "下载的脚本语法检查未通过，安装中止。"; exit 1; }

install -m 0755 "$tmp" "$DEST"
ln -sf "$DEST" "$LINK"

ok "vps-toolbox 已安装：$DEST"
ok "快捷方式已创建：$LINK"
if "$DEST" help >/dev/null 2>&1; then
    ok "验证通过：tbox help 正常。"
else
    err "安装后验证未通过（tbox help 异常），请检查。"
    exit 1
fi
echo "装完直接运行 tbox 即可（大部分功能需要 root，请用 sudo tbox）。"
