#!/usr/bin/env bash
#
# vps-toolbox.sh — VPS 工具箱（精简自研版）v1.0.4
#
# 来源：参考 kejilion/sh（Apache 2.0）的功能与实现，自行重写，只保留
#       真正用得上的部分；与 vps-tune 是分工关系，不是重复：
#       工具箱负责新机基线/设置（给初始值），vps-tune 负责实测调优
#       （按实测给最终值）。调好后不要再用工具箱重写那批参数。
#
# 适用：仅 Debian / Ubuntu（x86_64 与 ARM64 均可，XanMod 内核安装仅限 x86_64）。
# 用法：交互菜单直接运行 ./vps-toolbox.sh；也可以带子命令：
#       tbox info | update | clean | bbr | warp | settings | help
# 快捷命令：首次运行后用「系统工具 → 1 设置脚本启动快捷键」创建，默认名 tbox。
#
# 隐私：本脚本零遥测、零对外上报、不查询 IP。
#       不向任何外部服务发送系统信息、IP 或使用记录。
#       例外只有两处用户批准的第三方脚本（执行前都会先警告并要确认）：
#       ① WARP 管理：fscarmen 的 warp 脚本（GitLab）
#       ② 一键重装：leitbogioro / bin456789 的重装脚本（GitHub）
#       另有一处可选第三方：切换更新源用的 linuxmirrors 脚本，执行前
#       也会警告并要确认，默认源正常时不要用。
#
# 安全：破坏性操作（重装、改 SSH 端口、重建 swap、装内核、重启、
#       卸载）一律要确认；不使用 eval；不以管道方式执行远程脚本。
#
set -u

VERSION="1.0.7"
SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"

# ── 颜色 ──────────────────────────────────────────────────────────
# 用 $'' 存真实 ESC 字节（不是字面 \033），这样 printf '%s' 能直接
# 输出、dwidth 的 sed 也能正确去掉颜色码再量宽度。
C_RESET=$'\033[0m'
C_RED=$'\033[31m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_CYAN=$'\033[36m'
C_BOLD=$'\033[1m'

# ── 通用小函数 ────────────────────────────────────────────────────
ok()   { echo -e "${C_GREEN}$*${C_RESET}"; }
warn() { echo -e "${C_YELLOW}$*${C_RESET}"; }
err()  { echo -e "${C_RED}$*${C_RESET}" >&2; }
info() { echo -e "${C_CYAN}$*${C_RESET}"; }

# ── 框线 ──────────────────────────────────────────────────────────
# 框线风格：Unicode 框线 + 青色边框。中文算 2 列，ASCII 与 2 字节
# 符号算 1 列。内容行里不要用 3 字节的非中文符号（→ ⚠ ✓ 等），
# 宽度会算多 1 列、框对不齐。
# 显示宽度：先去掉 ANSI 颜色码再量；wc -m 量字符数必须用 UTF-8
# locale，否则在 POSIX locale 下会按字节数、中文就被算宽了、框会撑大。
dwidth() {
    local s="$1" chars bytes
    s=$(printf '%s' "$s" | sed 's/\x1b\[[0-9;]*m//g')
    chars=$(printf '%s' "$s" | LC_ALL=C.UTF-8 wc -m 2>/dev/null || printf '%s' "$s" | wc -c)
    bytes=$(printf '%s' "$s" | wc -c)
    echo $(( chars + (bytes - chars) / 2 ))
}
repeat_char() {
    local c="$1" n="$2" i out=""
    for ((i=0; i<n; i++)); do out+="$c"; done
    printf '%s' "$out"
}
pad_to() {
    local s="$1" w="$2" dw n
    dw=$(dwidth "$s")
    n=$(( w - dw ))
    [ "$n" -lt 0 ] && n=0
    printf '%s%*s' "$s" "$n" ""
}
max_width() {
    local m=0 w line
    for line in "$@"; do
        [ "$line" = "---" ] && continue
        w=$(dwidth "$line")
        [ "$w" -gt "$m" ] && m=$w
    done
    echo "$m"
}
# box <内宽> <行...>
# "---" 表示横分隔线，"" 表示空行；内宽由调用方用 max_width 算好。
box() {
    local w="$1"; shift
    local line
    printf "${C_CYAN}┌%s┐${C_RESET}\n" "$(repeat_char '─' $(( w + 2 )))"
    for line in "$@"; do
        if [ "$line" = "---" ]; then
            printf "${C_CYAN}├%s┤${C_RESET}\n" "$(repeat_char '─' $(( w + 2 )))"
        elif [ "$line" = "" ]; then
            printf "${C_CYAN}│${C_RESET} %s ${C_CYAN}│${C_RESET}\n" "$(repeat_char ' ' "$w")"
        else
            printf "${C_CYAN}│${C_RESET} %s ${C_CYAN}│${C_RESET}\n" "$(pad_to "$line" "$w")"
        fi
    done
    printf "${C_CYAN}└%s┘${C_RESET}\n" "$(repeat_char '─' $(( w + 2 )))"
}
# 只给标题画个小框：box_title "系统更新"
box_title() {
    local title="$1" w
    w=$(dwidth "  $title")
    printf "${C_CYAN}┌%s┐${C_RESET}\n" "$(repeat_char '─' $(( w + 2 )))"
    printf "${C_CYAN}│${C_RESET} %s ${C_CYAN}│${C_RESET}\n" "$(pad_to "  ${C_BOLD}${C_CYAN}$title${C_RESET}" "$w")"
    printf "${C_CYAN}└%s┘${C_RESET}\n" "$(repeat_char '─' $(( w + 2 )))"
}

# Y/N 确认，默认否；返回 0 表示确认
confirm() {
    local prompt="$1"
    local ans=""
    read -r -p "$(echo -e "${C_YELLOW}提示：${C_RESET}${prompt} [y/N]: ")" ans
    case "$ans" in
        [Yy]*) return 0 ;;
        *)     return 1 ;;
    esac
}

# 只在交互终端时清屏（管道/重定向运行时不清，避免 TERM 报错）
cls() { [ -t 1 ] && clear; }

pause() {
    local _dummy=""
    read -r -p "按回车返回..." _dummy || true
}

need_root() {
    if [ "$EUID" -ne 0 ]; then
        err "错误：此操作需要 root 权限，请以 root 运行。"
        return 1
    fi
    return 0
}

# 只支持 Debian / Ubuntu，其他发行版明确拒绝
require_debian_ubuntu() {
    local os_id=""
    if [ -r /etc/os-release ]; then
        os_id="$(. /etc/os-release; printf '%s' "${ID:-}")"
    fi
    case "$os_id" in
        debian|ubuntu) return 0 ;;
        *)
            err "错误：本工具箱只支持 Debian / Ubuntu，当前系统：${os_id:-未知}。"
            return 1
            ;;
    esac
}

# 安装缺失的软件包（Debian/Ubuntu，apt）
apt_install() {
    local pkg="" missing=()
    for pkg in "$@"; do
        if ! dpkg -s "$pkg" >/dev/null 2>&1; then
            missing+=("$pkg")
        fi
    done
    if [ "${#missing[@]}" -eq 0 ]; then
        return 0
    fi
    echo "正在安装：${missing[*]} ..."
    DEBIAN_FRONTEND=noninteractive apt-get update -y >/dev/null 2>&1 || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}" || {
        err "安装失败：${missing[*]}"
        return 1
    }
    return 0
}

# 检查是否有 apt/dpkg 正在运行（不像 kejilion 的 fix_dpkg 那样 pkill -9）
check_apt_free() {
    if pgrep -x apt >/dev/null 2>&1 || pgrep -x apt-get >/dev/null 2>&1 \
        || pgrep -x dpkg >/dev/null 2>&1; then
        err "检测到 apt/dpkg 正在运行，请等它结束后再试。"
        return 1
    fi
    if [ -e /var/lib/dpkg/lock-frontend ] && command -v fuser >/dev/null 2>&1 \
        && fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then
        err "检测到 dpkg 锁被占用（/var/lib/dpkg/lock-frontend），请等它结束后再试。"
        return 1
    fi
    return 0
}

get_mem_mb() {
    awk '/MemTotal/{printf "%d", $2/1024; found=1} END {if (!found) print 0}' /proc/meminfo 2>/dev/null
}

# 检查根分区可用空间是否 >= N GB；不够则拒绝
check_disk_space() {
    local required_gb="$1"
    local path="${2:-/}"
    local required_mb=$((required_gb * 1024))
    local available_mb=0
    available_mb="$(df -m "$path" | awk 'NR==2 {print $4}')"
    if [[ ! "$available_mb" =~ ^[0-9]+$ ]]; then
        err "无法读取磁盘空间，请检查磁盘状态。"
        return 1
    fi
    if [ "$available_mb" -lt "$required_mb" ]; then
        err "磁盘空间不足：当前可用 $((available_mb / 1024))G，至少需要 ${required_gb}G。"
        return 1
    fi
    return 0
}

# 只保留最新的 3 份时间戳备份，删掉第 4 个及以后的。
# 用法：prune_backups <目录> <文件名 glob>，如 prune_backups /etc/ssh "sshd_config.bak.*"
prune_backups() {
    local dir="$1" pattern="$2"
    local count=0 f=""
    # shellcheck disable=SC2045,SC2086
    for f in $(ls -t "$dir"/$pattern 2>/dev/null); do
        count=$((count + 1))
        if [ "$count" -gt 3 ]; then
            rm -f -- "$f"
        fi
    done
}

# 无 swap 时自动建 1GB swap（XanMod 安装前的门槛检查用）
check_swap() {
    local swap_total=0
    swap_total="$(free -m | awk 'NR==3{print $2}')"
    if [ "$swap_total" -gt 0 ]; then
        return 0
    fi
    echo "未检测到 swap，自动创建一个 1GB swapfile ..."
    add_swap 1024
}

# ── 1. 系统信息查询 ───────────────────────────────────────────────
# 照 kejilion 的 linux_info 的展示项，但删掉了 send_stats 遥测和
# ipinfo.io 查询（出口 IP 不再发给外部服务）；IP 只显示本机地址。
sys_info() {
    cls
    info "正在查询系统信息..."
    sleep 1

    local hostname="" os_info="" kernel_version="" cpu_arch=""
    local cpu_info="" cpu_cores="" cpu_freq="" cpu_usage_percent=""
    local mem_info="" swap_info="" disk_info="" load="" dns_addresses=""
    local congestion_algorithm="" queue_algorithm="" timezone=""
    local current_time="" runtime="" tcp_count="" udp_count=""
    local rx="" tx="" ipv4_list="" ipv6_list=""

    hostname="$(uname -n)"
    os_info="$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d '=' -f2 | tr -d '"')"
    kernel_version="$(uname -r)"
    cpu_arch="$(uname -m)"
    if command -v lscpu >/dev/null 2>&1; then
        cpu_info="$(lscpu | awk -F': +' '/Model name:/ {print $2; exit}')"
    else
        cpu_info="$(awk -F': ' '/model name/ {print $2; exit}' /proc/cpuinfo 2>/dev/null)"
    fi
    cpu_cores="$(nproc)"
    cpu_freq="$(awk -F': ' '/MHz/ {printf "%.1f GHz", $2/1000; exit}' /proc/cpuinfo 2>/dev/null)"
    # CPU 占用：两次 /proc/stat 采样，间隔 1 秒（瞬时值）
    cpu_usage_percent="$(awk '{u=$2+$4; t=$2+$4+$5; if (NR==1){u1=u; t1=t;} else printf "%.0f", (($2+$4-u1) * 100 / (t-t1))}' \
        <(grep 'cpu ' /proc/stat) <(sleep 1; grep 'cpu ' /proc/stat))"
    mem_info="$(free -b | awk 'NR==2{printf "%.2f/%.2fM (%.2f%%)", $3/1024/1024, $2/1024/1024, $3*100/$2}')"
    swap_info="$(free -m | awk 'NR==3{used=$3; total=$2; if (total == 0) {percentage=0} else {percentage=used*100/total}; printf "%dM/%dM (%d%%)", used, total, percentage}')"
    disk_info="$(df -h / | awk 'NR==2{printf "%s/%s (%s)", $3, $2, $5}')"
    load="$(uptime | awk '{print $(NF-2), $(NF-1), $NF}')"
    dns_addresses="$(awk '/^nameserver/{printf "%s ", $2} END {print ""}' /etc/resolv.conf 2>/dev/null)"
    congestion_algorithm="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "未知")"
    queue_algorithm="$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "未知")"
    # 总接收/总发送：读 /proc/net/dev，自开机累计值，不是速率
    local traffic=""
    traffic="$(awk 'BEGIN { rx_total = 0; tx_total = 0 }
        $1 ~ /^(eth|ens|enp|eno)[0-9]+/ { rx_total += $2; tx_total += $10 }
        END {
            rx_units = "B"; tx_units = "B";
            if (rx_total > 1024) { rx_total /= 1024; rx_units = "K"; }
            if (rx_total > 1024) { rx_total /= 1024; rx_units = "M"; }
            if (rx_total > 1024) { rx_total /= 1024; rx_units = "G"; }
            if (tx_total > 1024) { tx_total /= 1024; tx_units = "K"; }
            if (tx_total > 1024) { tx_total /= 1024; tx_units = "M"; }
            if (tx_total > 1024) { tx_total /= 1024; tx_units = "G"; }
            printf("%.2f%s %.2f%s", rx_total, rx_units, tx_total, tx_units);
        }' /proc/net/dev)"
    rx="$(printf '%s' "$traffic" | awk '{print $1}')"
    tx="$(printf '%s' "$traffic" | awk '{print $2}')"
    # 本机 IP（只读本地网卡，不对外查询）
    if command -v ip >/dev/null 2>&1; then
        ipv4_list="$(ip -4 addr show scope global 2>/dev/null | awk '/inet /{print $2}' | tr '\n' ' ')"
        ipv6_list="$(ip -6 addr show scope global 2>/dev/null | awk '/inet6 /{print $2}' | tr '\n' ' ')"
    fi
    timezone="$(timedatectl 2>/dev/null | grep "Time zone" | awk '{print $3}')"
    [ -z "$timezone" ] && timezone="$(date +%Z)"
    current_time="$(date "+%Y-%m-%d %H:%M")"
    runtime="$(awk -F. '{run_days=int($1 / 86400);run_hours=int(($1 % 86400) / 3600);run_minutes=int(($1 % 3600) / 60); if (run_days > 0) printf("%d天 ", run_days); if (run_hours > 0) printf("%d时 ", run_hours); printf("%d分", run_minutes)}' /proc/uptime)"
    tcp_count="$(ss -t 2>/dev/null | tail -n +2 | wc -l)"
    udp_count="$(ss -u 2>/dev/null | tail -n +2 | wc -l)"

    cls
    box_title "系统信息查询"
    echo "主机名：        $hostname"
    echo "系统版本：      $os_info"
    echo "Linux 版本：    $kernel_version"
    echo "-------------"
    echo "CPU 架构：      $cpu_arch"
    echo "CPU 型号：      $cpu_info"
    echo "CPU 核心数：    $cpu_cores"
    [ -n "$cpu_freq" ] && echo "CPU 频率：      $cpu_freq"
    echo "-------------"
    echo "CPU 占用：      ${cpu_usage_percent}%（1 秒瞬时采样）"
    echo "系统负载：      $load"
    echo "TCP|UDP 连接数：$tcp_count|$udp_count"
    echo "物理内存：      $mem_info"
    echo "虚拟内存：      $swap_info"
    echo "硬盘占用：      $disk_info"
    echo "-------------"
    echo "总接收：        $rx（自开机累计）"
    echo "总发送：        $tx（自开机累计）"
    echo "-------------"
    echo "网络算法：      $congestion_algorithm $queue_algorithm"
    echo "-------------"
    [ -n "$ipv4_list" ] && echo "本机 IPv4：     $ipv4_list"
    [ -n "$ipv6_list" ] && echo "本机 IPv6：     $ipv6_list"
    echo "DNS 地址：      $dns_addresses"
    echo "系统时间：      $timezone $current_time"
    echo "-------------"
    echo "运行时长：      $runtime"
    echo
    pause
}

# ── 2. 系统更新 ───────────────────────────────────────────────────
# 照 kejilion 的 linux_update（Debian/Ubuntu 分支），改了三处：
# ① 加确认；② 去掉 pkill -9 杀 apt/dpkg（只检查是否有人在跑）；
# ③ full-upgrade 前提示会装新内核，装完对照内核清单并提示重启。
sys_update() {
    need_root || return 1
    require_debian_ubuntu || return 1

    box_title "系统更新"
    warn "将执行 apt update + apt full-upgrade。"
    warn "full-upgrade 会安装新内核（linux-image），可能改变默认启动内核；"
    warn "已装 XanMod 的机器，重启后默认启动项可能变回官方内核，BBRv3 会失效。"
    warn "生产节点请先确认当前内核 / BBR 状态再继续。"
    confirm "确定现在更新系统吗？" || { echo "已取消。"; pause; return 0; }
    check_apt_free || { pause; return 1; }

    # 记录更新前的内核清单，装完对照
    local kernel_before="" kernel_after=""
    kernel_before="$(dpkg -l 'linux-image-*' 2>/dev/null | awk '$1=="ii"{print $2" "$3}' | sort)"

    echo "正在更新软件包列表..."
    DEBIAN_FRONTEND=noninteractive apt-get update -y || {
        err "apt update 失败。"
        pause; return 1
    }
    # 先处理可能中断的 dpkg 配置（不杀进程）
    DEBIAN_FRONTEND=noninteractive dpkg --configure -a || true
    echo "正在执行 full-upgrade..."
    DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y || {
        err "full-upgrade 失败，请查看上面的报错。"
        pause; return 1
    }
    ok "系统更新完成。"
    kernel_after="$(dpkg -l 'linux-image-*' 2>/dev/null | awk '$1=="ii"{print $2" "$3}' | sort)"
    if [ "$kernel_before" != "$kernel_after" ]; then
        warn "本次更新安装/升级了内核："
        diff <(printf '%s\n' "$kernel_before") <(printf '%s\n' "$kernel_after") | grep '^[<>]' || true
        warn "新内核要重启后才生效；重启后请用 uname -r 核对，并检查 grub 默认启动项。"
    fi
    if [ -f /var/run/reboot-required ]; then
        warn "系统提示需要重启：$(cat /var/run/reboot-required.pkgs 2>/dev/null | head -3 | tr '\n' ' ')"
    fi
    echo "当前运行内核：$(uname -r)"
    pause
}

# ── 3. 系统清理 ───────────────────────────────────────────────────
# 只取 kejilion 的 linux_clean 的 Debian/Ubuntu 分支；改了一处：
# journal 清理从 --vacuum-time=1s（等于全清日志）改成 7 天，
# 再加 --vacuum-size=500M 上限。其他发行版的 rm -rf 分支不要。
sys_clean() {
    need_root || return 1
    require_debian_ubuntu || return 1

    local df_before="" df_after="" j_before="" j_after="" freed=0
    box_title "系统清理"
    echo "将执行：apt autoremove --purge、apt clean、apt autoclean，"
    echo "再清理 journal 日志（保留最近 7 天，且总量不超过 500M）。"
    confirm "确定清理吗？" || { echo "已取消。"; pause; return 0; }
    check_apt_free || { pause; return 1; }

    df_before="$(df -m / 2>/dev/null | awk 'NR==2 {print $4}')"
    j_before="$(journalctl --disk-usage 2>/dev/null | awk '{print $7}')"
    DEBIAN_FRONTEND=noninteractive dpkg --configure -a || true
    DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y
    DEBIAN_FRONTEND=noninteractive apt-get clean -y
    DEBIAN_FRONTEND=noninteractive apt-get autoclean -y
    journalctl --rotate 2>/dev/null || true
    journalctl --vacuum-time=7d 2>/dev/null || true
    journalctl --vacuum-size=500M 2>/dev/null || true
    df_after="$(df -m / 2>/dev/null | awk 'NR==2 {print $4}')"
    j_after="$(journalctl --disk-usage 2>/dev/null | awk '{print $7}')"
    echo "------------------------"
    echo "清理小结："
    if [[ "$df_before" =~ ^[0-9]+$ ]] && [[ "$df_after" =~ ^[0-9]+$ ]]; then
        freed=$((df_after - df_before))
        if [ "$freed" -ge 0 ]; then
            echo "  磁盘可用（/）：${df_before} MB → ${df_after} MB，释放约 ${freed} MB"
        else
            echo "  磁盘可用（/）：${df_before} MB → ${df_after} MB（清理期间有其他写入，净减少 $((-freed)) MB）"
        fi
    fi
    if [ -n "$j_before" ] && [ -n "$j_after" ]; then
        echo "  journal 占用：${j_before} → ${j_after}"
    fi
    ok "系统清理完成。"
    pause
}

# ── 5. BBR 管理（只做基线开启） ────────────────────────────────────
# kejilion 的 linux_bbr 在 Debian/Ubuntu 上根本没有菜单，只是下载执行
# 第三方 tcpx.sh——不要。本项只做基线开启，照 bbr_on 的两行：
#   net.core.default_qdisc=fq
#   net.ipv4.tcp_congestion_control=bbr
# 写到 /etc/sysctl.d/99-vps-toolbox-bbr.conf 并立即生效。
# 注意分工：这里只给初始值；跑完 vps-tune 调优后不要再点本项，
# 否则会把 vps-tune 按实测给的最终值重写回初始值。
# BBR 版本判定（与 vps-tune 同一套办法）：内核名含 xanmod/bbrv3 → v3；
# modinfo tcp_bbr 的 version 字段 → v3/v1；都读不到时主线默认 v1
# （BBR 自 4.9 合入主线，一直是 v1）。
bbr_version() {
    local krel="" ver=""
    krel="$(uname -r 2>/dev/null)"
    if printf '%s' "$krel" | grep -qiE 'xanmod|bbrv3'; then
        echo "v3"
        return 0
    fi
    ver="$(modinfo tcp_bbr 2>/dev/null | awk -F': *' '/^version:/ {print $2; exit}')"
    if [ -n "$ver" ]; then
        if printf '%s' "$ver" | grep -q '^3'; then
            echo "v3"
        else
            echo "v1"
        fi
        return 0
    fi
    echo "v1"
}

bbr_enable() {
    need_root || return 1
    require_debian_ubuntu || return 1

    local conf="/etc/sysctl.d/99-vps-toolbox-bbr.conf"
    local cur_cc cur_qdisc w kernel bbr_ver
    local lines=()
    cur_cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
    cur_qdisc="$(sysctl -n net.core.default_qdisc 2>/dev/null)"
    kernel="$(uname -r 2>/dev/null)"
    bbr_ver="$(bbr_version)"

    # 已经是 bbr+fq：直接提示已开启，不再问，避免在已调优的机器上误点重写。
    if [ "$cur_cc" = "bbr" ] && [ "$cur_qdisc" = "fq" ]; then
        lines=(
            "  ${C_BOLD}${C_CYAN}BBR 管理（基线开启）${C_RESET}"
            "---"
            "  拥塞算法： ${C_GREEN}${cur_cc}${C_RESET}"
            "  队列算法： ${C_GREEN}${cur_qdisc}${C_RESET}"
            "  内核版本： ${kernel}"
            "  BBR 版本： ${C_GREEN}${bbr_ver}${C_RESET}"
            ""
            "  ${C_GREEN}BBR 已开启，无需重复开启。${C_RESET}"
            ""
            "  ${C_YELLOW}分工提醒：跑完 vps-tune 调优后不要点本项，${C_RESET}"
            "  ${C_YELLOW}会重写调优结果。${C_RESET}"
        )
        w=$(max_width "${lines[@]}")
        box "$w" "${lines[@]}"
        pause; return 0
    fi

    # 内核是否支持 BBR：先查可用算法列表，没有 bbr 就明说并跳过，
    # 不要先写配置再报“应用参数失败”（微虚拟机等宿主机内核无 tcp_bbr 时会走到这里）。
    # 读不到列表时（键不存在）不拦截，走老路、由后面的应用步骤兜底。
    local avail
    avail="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)"
    if [ -n "$avail" ] && ! printf '%s' "$avail" | grep -qw "bbr"; then
        lines=(
            "  ${C_BOLD}${C_CYAN}BBR 管理（基线开启）${C_RESET}"
            "---"
            "  ${C_RED}当前内核不支持 BBR。${C_RESET}"
            "  内核版本： ${kernel}"
            "  可用拥塞算法：$avail"
            "  没有 bbr，通常是微虚拟机（宿主机内核无 tcp_bbr）"
            "  或内核太旧。"
            "  如果刚装了 XanMod 内核，请重启后再试；"
            "  微虚拟机装新内核也不生效，无法开启 BBR。"
        )
        w=$(max_width "${lines[@]}")
        box "$w" "${lines[@]}"
        pause; return 0
    fi

    lines=(
        "  ${C_BOLD}${C_CYAN}BBR 管理（基线开启）${C_RESET}"
        "---"
        "  拥塞算法： ${C_GREEN}${cur_cc}${C_RESET}"
        "  队列算法： ${C_GREEN}${cur_qdisc}${C_RESET}"
        "  内核版本： ${kernel}"
        "  BBR 版本： ${C_GREEN}${bbr_ver}${C_RESET}"
        ""
        "  本项只写两个基线参数到"
        "  $conf："
        "    net.core.default_qdisc=fq"
        "    net.ipv4.tcp_congestion_control=bbr"
        ""
        "  BBRv3 需 XanMod 内核，用系统工具 16 设置 BBR3 加速安装；"
        "  没有 XanMod 内核时，这里开启的是 BBRv1。"
        ""
        "  ${C_YELLOW}分工提醒：跑完 vps-tune 调优后不要点本项，${C_RESET}"
        "  ${C_YELLOW}会重写调优结果。${C_RESET}"
    )
    w=$(max_width "${lines[@]}")
    box "$w" "${lines[@]}"
    confirm "确定开启 BBR 吗？" || { echo "已取消。"; pause; return 0; }

    mkdir -p /etc/sysctl.d
    {
        echo "# vps-toolbox BBR 基线参数（初始值，vps-tune 调优后不要再改）"
        echo "net.core.default_qdisc=fq"
        echo "net.ipv4.tcp_congestion_control=bbr"
    } > "$conf"
    # 清理 /etc/sysctl.conf 里同名旧残留，避免冲突
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf 2>/dev/null || true
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf 2>/dev/null || true
    sysctl -p "$conf" >/dev/null 2>&1 || sysctl --system >/dev/null 2>&1 || {
        err "应用参数失败。"
        pause; return 1
    }
    ok "BBR 已开启。"
    echo "拥塞算法：$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
    echo "队列算法：$(sysctl -n net.core.default_qdisc 2>/dev/null)"
    echo "内核版本：$(uname -r 2>/dev/null)"
    echo "BBR 版本：$(bbr_version)"
    pause
}

# ── 7. WARP 管理 ──────────────────────────────────────────────────
# 本脚本不实现 WARP，只下载执行 fscarmen 的 warp 脚本（GitLab 直链），
# 这是用户批准的第三方。执行前先打印三条警告并要确认。
warp_manage() {
    need_root || return 1
    require_debian_ubuntu || return 1

    box_title "WARP 管理"
    err "警告（执行前请看清）："
    err "  1. WARP 会把 /etc/resolv.conf 重写成 1.1.1.1 / 8.8.8.8，"
    err "     与国内 DNS 基线（223.5.5.5 / 183.60.83.19）冲突，"
    err "     用完请用「系统工具 → 7 优化 DNS 地址」改回国内 DNS。"
    err "  2. WARP 会改变出口 IP，不要在主力节点 / 代理节点上常驻。"
    err "  3. WARP 菜单里的 warp b 藏着 DD 重装，别误点。"
    echo
    echo "将从 GitLab 下载 fscarmen 的 warp 脚本并执行（第三方脚本）。"
    echo "进去后先选语言：选 2 是简体中文（默认是英文）。"
    confirm "确定继续吗？" || { echo "已取消。"; pause; return 0; }

    local tmp_script=""
    tmp_script="$(mktemp /tmp/warp-menu.XXXXXX.sh)" || {
        err "无法创建临时文件。"; pause; return 1
    }
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --max-time 60 "https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh" -o "$tmp_script" || {
            err "下载失败，请检查网络后重试。"
            rm -f -- "$tmp_script"; pause; return 1
        }
    elif command -v wget >/dev/null 2>&1; then
        wget -q --timeout=60 "https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh" -O "$tmp_script" || {
            err "下载失败，请检查网络后重试。"
            rm -f -- "$tmp_script"; pause; return 1
        }
    else
        err "需要 curl 或 wget，请先安装。"
        rm -f -- "$tmp_script"; pause; return 1
    fi
    if [ ! -s "$tmp_script" ]; then
        err "下载的文件为空，已取消。"
        rm -f -- "$tmp_script"; pause; return 1
    fi
    echo "已下载 warp 脚本（$(wc -c < "$tmp_script") 字节），现在执行..."
    bash "$tmp_script"
    local rc=$?
    rm -f -- "$tmp_script"
    echo
    warn "提醒：如需恢复国内 DNS，请用「系统工具 → 7 优化 DNS 地址」选 2。"
    pause
    return "$rc"
}

# ══════════════════════════════════════════════════════════════════
# 13. 系统工具（子菜单，只保留用户筛过的编号）
# ══════════════════════════════════════════════════════════════════

# ── 13-1. 设置脚本启动快捷键 ──────────────────────────────────────
settings_shortcut() {
    need_root || return 1
    local name="" target="" shadow=""
    box_title "设置脚本启动快捷键"
    echo "将在 /usr/local/bin 下创建一个指向本脚本的软链。"
    read -r -p "快捷键名 [默认 tbox]: " name
    name="${name:-tbox}"
    if [[ ! "$name" =~ ^[A-Za-z0-9_.-]+$ ]]; then
        err "快捷键名只能用字母、数字、下划线、点、横线。"
        pause; return 1
    fi
    if [ "$name" = "." ] || [ "$name" = ".." ] || [[ "$name" =~ ^[-.] ]]; then
        err "快捷键名不能是 .、..，也不能以 - 或 . 开头。"
        pause; return 1
    fi
    target="/usr/local/bin/$name"
    shadow="$(command -v "$name" 2>/dev/null || true)"
    if [ -n "$shadow" ]; then
        # 同名命令已存在：除非目标软链本来就指向本脚本（重建自己的快捷键），否则拒绝遮蔽
        if ! [ -L "$target" ] || [ "$(readlink -f "$target" 2>/dev/null)" != "$SCRIPT_PATH" ]; then
            err "已存在同名命令：$name（$shadow），建同名快捷键会遮蔽它，请换个名字。"
            pause; return 1
        fi
    fi
    if [ -e "$target" ] && [ ! -L "$target" ]; then
        err "$target 已存在且不是软链，不覆盖。"
        pause; return 1
    fi
    ln -sf "$SCRIPT_PATH" "$target"
    chmod +x "$SCRIPT_PATH"
    if [ "$(readlink -f "$(command -v "$name" 2>/dev/null)" 2>/dev/null)" != "$SCRIPT_PATH" ]; then
        err "快捷键创建失败：$name 未解析到本脚本，请检查 /usr/local/bin 的写权限。"
        pause; return 1
    fi
    ok "快捷键已创建：$name → $SCRIPT_PATH"
    echo "以后直接输入 $name 即可打开工具箱。"
    pause
}

# ── 13-2. 修改登录密码 ────────────────────────────────────────────
settings_passwd() {
    need_root || return 1
    box_title "修改登录密码"
    echo "将修改 root 的登录密码。改完请自己记好，不要贴到别处。"
    confirm "确定修改密码吗？" || { echo "已取消。"; pause; return 0; }
    if passwd; then
        ok "登录密码已修改。"
    else
        err "密码修改失败，请重试。"
        pause; return 1
    fi
    pause
}

# ── 13-6. 修改 SSH 连接端口 ───────────────────────────────────────
# 照 kejilion 的 new_ssh_port 思路，改了三处：
# ① 不删 /etc/ssh/sshd_config.d/*（kejilion 的 correct_ssh_config
#    会清空这些配置）；② 改前先 sshd -t 校验，改后回读验证并确认
#    新端口在监听；③ 不卸载 ufw/firewalld，改后尽量放行新端口。
settings_ssh_port() {
    need_root || return 1
    require_debian_ubuntu || return 1

    local current_port="" new_port="" backup="" d_backups="" conf_file="" d_bak="" d_restore=""
    box_title "修改 SSH 连接端口"
    # 当前端口优先读 sshd_config（ss 的第一个监听端口未必是 SSH）
    current_port="$(grep -E '^[[:space:]]*Port[[:space:]]+[0-9]+' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -1)"
    if [ -z "$current_port" ]; then
        current_port="$(grep -E '^[[:space:]]*Port[[:space:]]+[0-9]+' /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{print $2}' | head -1)"
    fi
    [ -z "$current_port" ] && current_port="22"
    echo "当前 SSH 端口：$current_port"
    warn "改端口会立刻断开当前 SSH 会话；改完要重新连接，"
    warn "Komari、1Panel、面板里的连接记录也要同步改。"
    read -r -p "请输入新端口（1-65535）: " new_port
    if [[ ! "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
        err "端口号无效：$new_port"
        pause; return 1
    fi
    if [ "$new_port" = "$current_port" ]; then
        echo "新端口与当前端口相同，无需修改。"
        pause; return 0
    fi
    confirm "确定把 SSH 端口从 $current_port 改为 $new_port 吗？" || { echo "已取消。"; pause; return 0; }

    backup="/etc/ssh/sshd_config.bak.$(date +%Y%m%d%H%M%S)"
    cp /etc/ssh/sshd_config "$backup"
    prune_backups /etc/ssh "sshd_config.bak.*"
    # /etc/ssh/sshd_config.d/*.conf 里含 Port 的行也要处理，否则旧端口仍在监听；
    # 涉及的文件各备一份，校验/重启失败时与 sshd_config 一起恢复
    for conf_file in /etc/ssh/sshd_config.d/*.conf; do
        [ -f "$conf_file" ] || continue
        grep -qE '^[[:space:]]*#?[[:space:]]*Port[[:space:]]' "$conf_file" || continue
        d_bak="${conf_file}.bak.$(date +%Y%m%d%H%M%S)"
        cp "$conf_file" "$d_bak"
        d_backups="$d_backups $d_bak"
        sed -i '/^[[:space:]]*#\?[[:space:]]*Port[[:space:]]/d' "$conf_file"
    done
    # 删掉现有的 Port 行，在文件首行插入新端口
    sed -i '/^[[:space:]]*#\?[[:space:]]*Port[[:space:]]/d' /etc/ssh/sshd_config
    sed -i "1i Port $new_port" /etc/ssh/sshd_config
    if ! sshd -t 2>/dev/null; then
        cp "$backup" /etc/ssh/sshd_config
        # shellcheck disable=SC2086
        for d_restore in $d_backups; do
            [ -f "$d_restore" ] && cp "$d_restore" "${d_restore%.bak.*}"
        done
        err "配置校验失败（sshd -t），已恢复备份，未重启 sshd；备份在 $backup"
        pause; return 1
    fi
    # 尽量放行新端口（按本机已有的防火墙工具）
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
        if ufw allow "$new_port/tcp" >/dev/null 2>&1; then
            echo "已在 ufw 放行 $new_port/tcp。"
        else
            warn "ufw 放行失败，请手工放行 $new_port/tcp。"
        fi
    elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port="$new_port/tcp" >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1 && echo "已在 firewalld 放行 $new_port/tcp。"
    else
        warn "未检测到已启用的 ufw/firewalld，如有防火墙请自行放行 $new_port/tcp。"
    fi
    # 重启 sshd；失败时先恢复备份再试一次，仍失败才报错
    local restart_ok=0
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || restart_ok=1
        if [ "$restart_ok" -eq 1 ]; then
            cp "$backup" /etc/ssh/sshd_config
            # shellcheck disable=SC2086
            for d_restore in $d_backups; do
                [ -f "$d_restore" ] && cp "$d_restore" "${d_restore%.bak.*}"
            done
            if systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null; then
                warn "sshd 重启失败一次，已恢复备份并重启成功，端口仍为 $current_port。"
            else
                err "sshd 重启失败，已恢复备份（端口仍为 $current_port）；备份在 $backup"
                pause; return 1
            fi
        fi
    else
        service ssh restart 2>/dev/null || service sshd restart 2>/dev/null || restart_ok=1
        if [ "$restart_ok" -eq 1 ]; then
            cp "$backup" /etc/ssh/sshd_config
            # shellcheck disable=SC2086
            for d_restore in $d_backups; do
                [ -f "$d_restore" ] && cp "$d_restore" "${d_restore%.bak.*}"
            done
            if service ssh restart 2>/dev/null || service sshd restart 2>/dev/null; then
                warn "sshd 重启失败一次，已恢复备份并重启成功，端口仍为 $current_port。"
            else
                err "sshd 重启失败，已恢复备份（端口仍为 $current_port）；备份在 $backup"
                pause; return 1
            fi
        fi
    fi
    sleep 1
    if ! command -v ss >/dev/null 2>&1; then
        warn "未安装 ss，无法确认新端口是否监听，请手工用新端口连接测试。"
    elif ss -H -ltn 2>/dev/null | awk '{print $4}' | grep -qE ":${new_port}$"; then
        ok "SSH 端口已改为 $new_port，且新端口正在监听。"
    else
        warn "sshd 已重启，但未检测到 $new_port 在监听，请检查。"
    fi
    warn "请用新端口重新连接；记得同步改 Komari、1Panel、面板的连接记录。"
    pause
}

# 写完 DNS 后做一次解析测试（只提示，不影响返回码）
dns_resolve_test() {
    if getent hosts www.baidu.com >/dev/null 2>&1; then
        ok "DNS 解析测试通过。"
    else
        warn "DNS 解析测试失败，请检查网络与 DNS 是否生效。"
    fi
}

# ── 13-7. 优化 DNS 地址 ───────────────────────────────────────────
# 照 kejilion 的 set_dns_ui / set_dns：重写 /etc/resolv.conf 后
# chattr +i 加锁。v6 DNS 只在有全局 IPv6 时才写。
set_dns_write() {
    # 参数：$1 $2 为 v4 的两个 DNS，$3 $4 为 v6 的两个 DNS
    local dns1_ipv4="$1" dns2_ipv4="$2" dns1_ipv6="$3" dns2_ipv6="$4"
    local has_ipv6=0
    if command -v ip >/dev/null 2>&1 && ip -6 addr show scope global 2>/dev/null | grep -q 'inet6'; then
        has_ipv6=1
    fi
    # /etc/resolv.conf 是软链（systemd-resolved）时先处理
    if [ -L /etc/resolv.conf ]; then
        warn "/etc/resolv.conf 是软链（systemd-resolved 接管），直接写会被覆盖。"
        confirm "把它换成真实文件再继续吗？" || { echo "已取消。"; return 1; }
        cp -a /etc/resolv.conf "/etc/resolv.conf.bak.$(date +%Y%m%d%H%M%S)"
        rm -f /etc/resolv.conf
    fi
    chattr -i /etc/resolv.conf 2>/dev/null || true
    {
        echo "nameserver $dns1_ipv4"
        echo "nameserver $dns2_ipv4"
        if [ "$has_ipv6" -eq 1 ]; then
            echo "nameserver $dns1_ipv6"
            echo "nameserver $dns2_ipv6"
        fi
    } > /etc/resolv.conf
    if chattr +i /etc/resolv.conf 2>/dev/null; then
        ok "DNS 已写入 /etc/resolv.conf 并加锁（chattr +i）。"
        echo "以后如需再改 DNS，请先执行 chattr -i /etc/resolv.conf 解锁。"
    else
        ok "DNS 已写入（加锁失败，文件系统可能不支持 chattr，未加锁）。"
        warn "以后改 DNS 不用先解锁（本次未加锁）。"
    fi
    cat /etc/resolv.conf
    dns_resolve_test
}

settings_dns() {
    need_root || return 1
    local choice=""
    while true; do
        cls
        box_title "优化 DNS 地址"
        echo "当前 DNS："
        cat /etc/resolv.conf 2>/dev/null || echo "（无法读取）"
        echo "------------------------"
        echo "1. 国外 DNS：v4 1.1.1.1 / 8.8.8.8；v6 2606:4700:4700::1111 / 2001:4860:4860::8888"
        echo "2. 国内 DNS：v4 223.5.5.5 / 183.60.83.19；v6 2400:3200::1 / 2400:da00::6666"
        echo "3. 手动编辑 DNS 配置"
        echo "------------------------"
        echo "0. 返回上一级选单"
        echo "------------------------"
        read -r -p "请输入你的选择: " choice
        case "$choice" in
            1)
                set_dns_write "1.1.1.1" "8.8.8.8" "2606:4700:4700::1111" "2001:4860:4860::8888" || { pause; continue; }
                pause
                ;;
            2)
                set_dns_write "223.5.5.5" "183.60.83.19" "2400:3200::1" "2400:da00::6666" || { pause; continue; }
                pause
                ;;
            3)
                apt_install nano || { pause; continue; }
                chattr -i /etc/resolv.conf 2>/dev/null || true
                nano /etc/resolv.conf
                if chattr +i /etc/resolv.conf 2>/dev/null; then
                    echo "已保存并重新加锁。"
                else
                    echo "已保存（加锁失败，文件系统可能不支持 chattr，未加锁）。"
                    warn "以后改 DNS 不用先解锁（本次未加锁）。"
                fi
                dns_resolve_test
                pause
                ;;
            0|"") break ;;
            *) echo "无效的选择。"; pause ;;
        esac
    done
}

# ── 13-8. 一键重装系统（仅空机器） ────────────────────────────────
# 照 kejilion 的 dd_xitong：Linux 走 bin456789 的 reinstall.sh，
# Windows 走 leitbogioro 的 InstallNET.sh。改了三处：
# ① 只保留常用系统；② 必须输入确认口令才执行；③ 下载时不加
# --no-check-certificate，保持 TLS 校验。
dd_download() {
    # $1 = URL，$2 = 保存路径
    local url="$1" dest="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --max-time 60 "$url" -o "$dest" || return 1
    elif command -v wget >/dev/null 2>&1; then
        wget -q --timeout=60 "$url" -O "$dest" || return 1
    else
        err "需要 curl 或 wget。"
        return 1
    fi
    [ -s "$dest" ] || return 1
    return 0
}

settings_dd() {
    need_root || return 1
    require_debian_ubuntu || return 1

    local choice="" phrase="" installer="" run_args=() rc=""
    while true; do
        cls
        box_title "一键重装系统"
        echo
        err "只适合空机器！重装会清空整台机器，面板、Komari、1Panel、"
        err "下载站等全部消失。甲骨文机器重装请走控制台重建，不要用 DD。"
        echo "------------------------"
        echo "Linux（bin456789 reinstall.sh，默认 root / 123@@@，端口 22）："
        echo "  1. Debian 13      2. Debian 12      3. Debian 11"
        echo "  4. Ubuntu 24.04   5. Ubuntu 22.04"
        echo "Windows（leitbogioro InstallNET.sh，默认 Administrator / Teddysun.com，端口 3389）："
        echo "  6. Windows 11     7. Windows 10"
        echo "------------------------"
        echo "0. 返回上一级选单"
        echo "------------------------"
        read -r -p "请选择要重装的系统: " choice
        case "$choice" in
            1) installer="bin456789"; run_args=(debian 13);;
            2) installer="bin456789"; run_args=(debian 12);;
            3) installer="bin456789"; run_args=(debian 11);;
            4) installer="bin456789"; run_args=(ubuntu 24.04);;
            5) installer="bin456789"; run_args=(ubuntu 22.04);;
            6) installer="leitbogioro"; run_args=(-windows 11 -lang "cn");;
            7) installer="leitbogioro"; run_args=(-windows 10 -lang "cn");;
            0|"") return 0 ;;
            *) echo "无效的选择。"; pause; continue ;;
        esac
        break
    done

    echo
    err "重装后默认密码是公开的（Linux：root / 123@@@；Windows：Administrator / Teddysun.com），"
    err "装完必须立刻改密码，否则会被暴力破解。"
    echo "这是毁灭性操作，请输入确认口令继续。"
    read -r -p "输入「重装系统」确认（其他任意输入取消）: " phrase
    if [ "$phrase" != "重装系统" ]; then
        echo "口令不符，已取消。"
        pause; return 0
    fi
    apt_install wget curl || { pause; return 1; }

    if [ "$installer" = "bin456789" ]; then
        installer="/tmp/reinstall.sh"
        echo "正在下载 bin456789 reinstall.sh ..."
        dd_download "https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh" "$installer" || {
            err "下载失败。"; pause; return 1
        }
        echo "下载完成，开始重装：${run_args[*]}"
        bash "$installer" "${run_args[@]}"
        rc=$?
        rm -f -- "$installer"
        if [ "$rc" -ne 0 ]; then
            err "重装脚本执行失败（退出码 $rc），未重启。"
            pause; return 1
        fi
    else
        installer="/tmp/InstallNET.sh"
        echo "正在下载 leitbogioro InstallNET.sh ..."
        dd_download "https://raw.githubusercontent.com/leitbogioro/Tools/master/Linux_reinstall/InstallNET.sh" "$installer" || {
            err "下载失败。"; pause; return 1
        }
        chmod +x "$installer"
        echo "下载完成，开始重装：${run_args[*]}"
        bash "$installer" "${run_args[@]}"
        rc=$?
        rm -f -- "$installer"
        if [ "$rc" -ne 0 ]; then
            err "重装脚本执行失败（退出码 $rc），未重启。"
            pause; return 1
        fi
    fi
    echo
    warn "重装脚本已执行完毕，机器将重启。"
    confirm "现在重启吗？" && reboot
}

# ── 13-10. 切换优先 ipv4/ipv6（只做 IPv4 优先） ────────────────────
# 照 kejilion 的 prefer_ipv4：往 /etc/gai.conf 写
# precedence ::ffff:0:0/96  100。子项 2（删整个 gai.conf）和
# 子项 3（第三方 v6.sh 管道执行）都不要。
settings_ipv4_first() {
    need_root || return 1
    box_title "切换优先 IPv4"
    if grep -q '^precedence ::ffff:0:0/96' /etc/gai.conf 2>/dev/null; then
        if grep -q '^precedence ::ffff:0:0/96[[:space:]]\+100[[:space:]]*$' /etc/gai.conf 2>/dev/null; then
            echo "已是 IPv4 优先（/etc/gai.conf 里已有该规则），无需重复设置。"
        else
            sed -i 's|^precedence ::ffff:0:0/96.*|precedence ::ffff:0:0/96  100|' /etc/gai.conf
            ok "已修正为 100。"
        fi
    else
        if ! echo 'precedence ::ffff:0:0/96  100' >> /etc/gai.conf; then
            err "写入 /etc/gai.conf 失败。"
            pause; return 1
        fi
        ok "已切换为 IPv4 优先（已写入 /etc/gai.conf）。"
    fi
    echo "当前规则："
    grep '^precedence' /etc/gai.conf 2>/dev/null || echo "（无）"
    pause
}

# ── 13-11. 查看端口占用状态（只读） ──────────────────────────────
settings_ports() {
    box_title "端口占用状态（只读）"
    ss -tulnp 2>/dev/null || ss -tuln 2>/dev/null || {
        err "ss 不可用。"
        pause; return 1
    }
    echo
    pause
}

# ── 13-12. 修改虚拟内存大小 ──────────────────────────────────────
# 照 kejilion 的 add_swap，改了三处：
# ① 不用 wipefs 销毁 swap 分区，只 swapoff 停用、删 /swapfile、
#    只清 fstab 里 /swapfile 的行（swap 分区行保留）；
# ② fallocate 失败时回退 dd 创建；
# ③ 先建新文件再停旧的，新的起不来就恢复旧 swap。
add_swap() {
    local new_swap="$1"
    echo "正在重建 swapfile（${new_swap}M）..."
    # 先建新文件，旧 swap 一点不动；建失败直接返回，旧 swap 还在。
    if ! fallocate -l "${new_swap}M" /swapfile.new 2>/dev/null; then
        echo "fallocate 不可用，改用 dd 创建（会慢一些）..."
        dd if=/dev/zero of=/swapfile.new bs=1M count="$new_swap" status=none || {
            err "创建 swapfile 失败，旧 swap 未动。"
            rm -f /swapfile.new
            return 1
        }
    fi
    chmod 600 /swapfile.new
    mkswap /swapfile.new >/dev/null || {
        err "mkswap 失败，旧 swap 未动。"
        rm -f /swapfile.new
        return 1
    }
    # 新文件就绪，再停旧 swap 并把旧文件备份
    swapoff /swapfile 2>/dev/null || true
    [ -f /swapfile ] && mv /swapfile /swapfile.old
    mv /swapfile.new /swapfile
    if swapon /swapfile; then
        rm -f /swapfile.old
        # 只删 fstab 里 /swapfile 的行，swap 分区行保留
        sed -i '\|^[[:space:]]*/swapfile[[:space:]]|d' /etc/fstab
        echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
        ok "虚拟内存大小已调整为 ${new_swap}M。"
        return 0
    fi
    err "swapon 失败，正在恢复旧 swap..."
    rm -f /swapfile
    if [ -f /swapfile.old ]; then
        mv /swapfile.old /swapfile
        swapon /swapfile 2>/dev/null || true
        err "新 swap 未能启用，已恢复旧 swap。"
    else
        err "新 swap 未能启用（之前没有旧 swap）。"
    fi
    return 1
}

settings_swap() {
    need_root || return 1
    local choice="" new_swap="" avail_mb=""
    box_title "修改虚拟内存大小"
    echo "当前 swap："
    free -m | awk 'NR==1 || NR==3'
    echo "当前 swap 设备："
    cat /proc/swaps
    echo "------------------------"
    echo "1. 1024M   2. 2048M（用户基线）   3. 4096M   4. 自定义"
    echo "------------------------"
    echo "0. 返回上一级选单"
    echo "------------------------"
    read -r -p "请输入你的选择: " choice
    case "$choice" in
        1) new_swap=1024 ;;
        2) new_swap=2048 ;;
        3) new_swap=4096 ;;
        4)
            read -r -p "请输入 swap 大小（MB，如 2048）: " new_swap
            if [[ ! "$new_swap" =~ ^[0-9]+$ ]] || [ "$new_swap" -lt 128 ]; then
                err "大小无效（至少 128M）。"
                pause; return 1
            fi
            if [ "$new_swap" -gt 16384 ]; then
                err "大小无效：最大 16384M（16G）。"
                pause; return 1
            fi
            ;;
        0|"") return 0 ;;
        *) echo "无效的选择。"; pause; return 1 ;;
    esac
    # 预设档位也要先查磁盘空间，不要等 fallocate/dd 失败才报错
    avail_mb="$(df -m / 2>/dev/null | awk 'NR==2 {print $4}')"
    if [[ "$avail_mb" =~ ^[0-9]+$ ]] && [ "$new_swap" -gt "$avail_mb" ]; then
        err "大小无效：根分区可用空间只有 ${avail_mb}M，不够建 ${new_swap}M 的 swap。"
        pause; return 1
    fi
    warn "将先建新 swapfile，确认可用后再替换旧 swap，旧 swap 在新 swap 启用前一直保留，重建为 ${new_swap}M。"
    warn "注意：本项只改 swap 大小，不改 vm.swappiness。"
    confirm "确定继续吗？" || { echo "已取消。"; pause; return 0; }
    add_swap "$new_swap" || { pause; return 1; }
    echo "重建后 swap："
    free -m | awk 'NR==1 || NR==3'
    pause
}

# ── 13-15. 系统时区调整 ──────────────────────────────────────────
settings_timezone() {
    need_root || return 1
    local choice="" zone="" cur_zone=""
    box_title "系统时区调整"
    echo "当前时区：$(timedatectl 2>/dev/null | grep "Time zone" | awk '{print $3}')"
    echo "------------------------"
    echo "1. Asia/Shanghai（上海）   2. Asia/Hong_Kong（香港）"
    echo "3. Asia/Tokyo（东京）      4. Asia/Seoul（首尔）"
    echo "5. UTC                     6. 自定义输入"
    echo "------------------------"
    echo "0. 返回上一级选单"
    echo "------------------------"
    read -r -p "请输入你的选择: " choice
    case "$choice" in
        1) zone="Asia/Shanghai" ;;
        2) zone="Asia/Hong_Kong" ;;
        3) zone="Asia/Tokyo" ;;
        4) zone="Asia/Seoul" ;;
        5) zone="UTC" ;;
        6)
            read -r -p "请输入时区（如 Europe/London）: " zone
            [ -n "$zone" ] || { echo "已取消。"; pause; return 0; }
            ;;
        0|"") return 0 ;;
        *) echo "无效的选择。"; pause; return 1 ;;
    esac
    if [ ! -f "/usr/share/zoneinfo/$zone" ]; then
        err "时区不存在：$zone"
        pause; return 1
    fi
    if ! timedatectl set-timezone "$zone" 2>/dev/null; then
        warn "timedatectl 设置失败，改用直接写 /etc/timezone 的方式设置时区。"
        if ! { echo "$zone" > /etc/timezone 2>/dev/null && ln -sf "/usr/share/zoneinfo/$zone" /etc/localtime 2>/dev/null; }; then
            err "设置时区失败。"
            pause; return 1
        fi
    fi
    ok "时区已改为 $zone。"
    # 改完重读一次确认：timedatectl 能读就读它；否则读 /etc/localtime
    # 软链目标（date +%Z 只给缩写如 CST，永远对不上区域名，会误报）。
    cur_zone="$(timedatectl 2>/dev/null | grep "Time zone" | awk '{print $3}')"
    if [ -z "$cur_zone" ] && [ -L /etc/localtime ]; then
        cur_zone="$(readlink /etc/localtime 2>/dev/null | sed 's|^.*/zoneinfo/||')"
    fi
    if [ -n "$cur_zone" ] && [ "$cur_zone" != "$zone" ]; then
        warn "当前时区显示为 $cur_zone，与目标 $zone 不一致，请检查。"
    fi
    date
    pause
}

# ── 13-16. 设置 BBR3 加速（XanMod 内核，仅 x86_64） ────────────────
# 照 kejilion 的 bbrv3() 的 x86_64 路径，改了两处：
# ① ARM64 不再走 jhb.ovh 第三方管道脚本，直接拒绝并说明；
# ② XanMod 密钥只从官方 dl.xanmod.org 拉，失败就报错退出，
#    不再回退到 kejilion 仓库里的 key。
# 门槛：根分区可用空间 >= 3GB；无 swap 时自动建 1GB swap。
# 支持的系统代号（XanMod 官方 APT 源）：bookworm trixie forky sid
# noble plucky questing resolute；
# Ubuntu 22.04（jammy）及更老系统官方已停支持，直接拒绝。
xanmod_add_repo() {
    local keyring="/usr/share/keyrings/xanmod-archive-keyring.gpg"
    local list_file="/etc/apt/sources.list.d/xanmod-release.list"
    local key_url="https://dl.xanmod.org/archive.key"
    local os_codename=""

    if command -v lsb_release >/dev/null 2>&1; then
        os_codename="$(lsb_release -sc)"
    elif [ -r /etc/os-release ]; then
        os_codename="$(. /etc/os-release; printf '%s' "${VERSION_CODENAME:-}")"
    fi
    if [ -z "$os_codename" ]; then
        err "无法获取系统代号，无法配置 XanMod 源。"
        return 1
    fi
    case "$os_codename" in
        bookworm|trixie|forky|sid|noble|plucky|questing|resolute)
            ;;
        jammy|focal|bullseye|buster)
            err "XanMod 官方已停止对当前系统（$os_codename）的 APT 源支持，请升级至 Debian 12 / Ubuntu 24 或更高版本。"
            return 1
            ;;
        *)
            err "当前系统代号（$os_codename）不在 XanMod 官方支持列表里。"
            return 1
            ;;
    esac

    apt_install wget gnupg ca-certificates || return 1
    mkdir -p /usr/share/keyrings /etc/apt/sources.list.d
    if ! wget --timeout=60 -qO - "$key_url" | gpg --dearmor -o "$keyring" --yes; then
        err "XanMod 官方密钥下载失败，请检查网络后重试。"
        return 1
    fi
    chmod 644 "$keyring"
    echo "deb [signed-by=$keyring] http://deb.xanmod.org $os_codename main" > "$list_file"
    ok "XanMod 源已配置（$os_codename）。"
}

# 读 /proc/cpuinfo 的 flags 判 x86-64 PSABI 等级 1-4（封顶按 3 取）
xanmod_detect_psabi_level() {
    local psabi_output=""
    psabi_output="$(awk 'BEGIN {
        while (!/flags/) if (getline < "/proc/cpuinfo" != 1) exit 1
        if (/lm/&&/cmov/&&/cx8/&&/fpu/&&/fxsr/&&/mmx/&&/syscall/&&/sse2/) level = 1
        if (level == 1 && /cx16/&&/lahf/&&/popcnt/&&/sse4_1/&&/sse4_2/&&/ssse3/) level = 2
        if (level == 2 && /avx/&&/avx2/&&/bmi1/&&/bmi2/&&/f16c/&&/fma/&&/abm/&&/movbe/&&/xsave/) level = 3
        if (level == 3 && /avx512f/&&/avx512bw/&&/avx512cd/&&/avx512dq/&&/avx512vl/) level = 4
        if (level > 0) { print level; exit }
        exit 1
    }' /proc/cpuinfo 2>/dev/null)" || return 1
    printf '%s' "$psabi_output" | tr -dc '0-9' | head -c 1
}

xanmod_package_available() {
    local package="$1"
    apt-cache policy "$package" 2>/dev/null | grep -q 'Candidate: [^ ]'
}

xanmod_detect_package() {
    local psabi_level="" level="" package="" prefix=""
    psabi_level="$(xanmod_detect_psabi_level)" || return 1
    [ -n "$psabi_level" ] || return 1
    [ "$psabi_level" -gt 3 ] && psabi_level=3

    apt-get update -y >/dev/null 2>&1 || warn "apt update 失败，将用现有软件源缓存继续匹配。"
    for prefix in linux-xanmod linux-xanmod-lts; do
        level="$psabi_level"
        while [ "$level" -ge 1 ]; do
            package="${prefix}-x64v${level}"
            if xanmod_package_available "$package"; then
                if [ "$level" != "$psabi_level" ] || [ "$prefix" = "linux-xanmod-lts" ]; then
                    echo "已自动匹配合适安装包：$package" >&2
                fi
                printf '%s\n' "$package"
                return 0
            fi
            level=$((level - 1))
        done
    done
    err "软件源中未找到适配此 CPU 的 XanMod 内核包。"
    return 1
}

xanmod_installed() {
    dpkg-query -W -f='${Package}\n' 'linux-*xanmod*' 2>/dev/null | grep -q '^linux-.*xanmod'
}

xanmod_install_or_update() {
    local action="$1"
    local package=""

    check_disk_space 3 || return 1
    check_swap || return 1
    xanmod_add_repo || return 1
    package="$(xanmod_detect_package)" || {
        err "无法识别当前 CPU 或找不到匹配内核包，已取消安装。"
        return 1
    }

    echo "将安装/更新内核包：$package"
    apt-get update -y || { err "apt update 失败。"; return 1; }
    if [ "$action" = "update" ]; then
        apt-get install -y --only-upgrade "$package" || apt-get install -y "$package" || {
            err "XanMod 内核更新失败，请检查软件源或稍后重试。"
            return 1
        }
    else
        apt-get install -y "$package" || {
            err "XanMod 内核安装失败，请检查软件源或稍后重试。"
            return 1
        }
    fi
    bbr_enable_nopause || {
        err "BBR 参数写入失败，请检查系统配置。"
        return 1
    }
    ok "XanMod BBRv3 内核处理完成，重启后生效。"
    echo "当前运行内核：$(uname -r)（重启后才会变）"
    echo "重启后请用 uname -r 核对，并确认 grub 默认启动项是 XanMod 内核。"
    if confirm "现在重启服务器吗？"; then
        reboot
    fi
}

# BBR 基线开启的不暂停版本（供 XanMod 安装流程内部调用）
bbr_enable_nopause() {
    local conf="/etc/sysctl.d/99-vps-toolbox-bbr.conf"
    mkdir -p /etc/sysctl.d
    {
        echo "# vps-toolbox BBR 基线参数（初始值，vps-tune 调优后不要再改）"
        echo "net.core.default_qdisc=fq"
        echo "net.ipv4.tcp_congestion_control=bbr"
    } > "$conf"
    if [ ! -s "$conf" ]; then
        err "写入 BBR 配置失败。"
        return 1
    fi
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf 2>/dev/null || true
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf 2>/dev/null || true
    # 新内核未重启时 sysctl 应用失败是预期内的（bbr 模块还没加载），忽略。
    sysctl -p "$conf" >/dev/null 2>&1 || sysctl --system >/dev/null 2>&1 || true
    return 0
}

xanmod_uninstall() {
    warn "将卸载全部 XanMod 内核并删除 XanMod 软件源。"
    confirm "确定卸载吗？" || { echo "已取消。"; return 0; }
    if ! dpkg -l 'linux-image-*' 2>/dev/null | awk '$1=="ii" && $2 !~ /xanmod/ {print $2}' | grep -q .; then
        err "未检测到非 XanMod 内核，卸载后可能无内核可启动，已取消。"
        return 1
    fi
    apt-get purge -y 'linux-*xanmod*' || true
    DEBIAN_FRONTEND=noninteractive apt-get autoremove -y || true
    update-grub 2>/dev/null || true
    rm -f /etc/apt/sources.list.d/xanmod-release.list
    rm -f /usr/share/keyrings/xanmod-archive-keyring.gpg
    ok "XanMod 内核已卸载，重启后生效。"
    if confirm "现在重启服务器吗？"; then
        reboot
    fi
}

settings_bbr3() {
    need_root || return 1
    require_debian_ubuntu || return 1

    local cpu_arch="" sub_choice=""
    cpu_arch="$(uname -m)"
    if [ "$cpu_arch" = "aarch64" ] || [ "$cpu_arch" = "arm64" ]; then
        err "ARM64 机器没有可信的 XanMod 官方 APT 路径，kejilion 的 ARM 分支"
        err "是执行第三方个人脚本（jhb.ovh），本工具箱不提供，请勿使用。"
        pause; return 1
    fi
    if [ "$cpu_arch" != "x86_64" ]; then
        err "不支持的 CPU 架构：$cpu_arch（仅支持 x86_64）。"
        pause; return 1
    fi

    if xanmod_installed; then
        while true; do
            cls
            box_title "您已安装 XanMod 的 BBRv3 内核"
            echo "运行中内核：$(uname -r)"
            echo "已安装 XanMod：$(dpkg-query -W -f='${Package} ${Version}\n' 'linux-*xanmod*' 2>/dev/null | head -1 || echo 未知)"
            echo "------------------------"
            echo "1. 更新 BBRv3 内核    2. 卸载 BBRv3 内核"
            echo "------------------------"
            echo "0. 返回上一级选单"
            echo "------------------------"
            read -r -p "请输入你的选择: " sub_choice
            case "$sub_choice" in
                1) xanmod_install_or_update update; pause ;;
                2) xanmod_uninstall; pause ;;
                0|"") break ;;
                *) echo "无效的选择。"; pause ;;
            esac
        done
    else
        cls
        box_title "设置 BBR3 加速"
        echo
        echo "仅支持 Debian/Ubuntu（x86_64）。"
        echo "将安装 XanMod 内核并开启 BBRv3，装完需重启。"
        warn "注意：/ 根分区至少需要 3GB 可用空间；装完请用 uname -r 核对。"
        echo "------------------------"
        confirm "确定继续吗？" || { echo "已取消。"; pause; return 0; }
        xanmod_install_or_update install
        pause
    fi
}

# ── 13-18. 修改主机名 ─────────────────────────────────────────────
# hostnamectl 改名 + 同步 /etc/hostname；/etc/hosts 里 127.0.0.1 与
# ::1 两行的旧主机名替换成新的（只换主机名本身，保留 localhost
# 等其他别名，改前备份）。
settings_hostname() {
    need_root || return 1
    local old_name="" new_name="" hosts_bak=""
    old_name="$(hostname)"
    box_title "修改主机名"
    echo "当前主机名：$old_name"
    read -r -p "请输入新主机名: " new_name
    if [[ ! "$new_name" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]]; then
        err "主机名无效：只能用字母、数字、横线，首尾不能是横线，最长 63 字符。"
        pause; return 1
    fi
    if [ "$new_name" = "$old_name" ]; then
        echo "新主机名与当前相同，无需修改。"
        pause; return 0
    fi
    confirm "确定把主机名从 $old_name 改为 $new_name 吗？" || { echo "已取消。"; pause; return 0; }

    if ! hostnamectl set-hostname "$new_name" 2>/dev/null; then
        warn "hostnamectl 失败，改用 hostname 命令 + 写 /etc/hostname。"
        hostname "$new_name" 2>/dev/null || { err "修改主机名失败。"; pause; return 1; }
        echo "$new_name" > /etc/hostname 2>/dev/null || { err "写入 /etc/hostname 失败。"; pause; return 1; }
    else
        echo "$new_name" > /etc/hostname
    fi
    hosts_bak="/etc/hosts.bak.$(date +%Y%m%d%H%M%S)"
    cp /etc/hosts "$hosts_bak"
    prune_backups /etc "hosts.bak.*"
    # 127.0.0.1 行：有旧主机名就替换，没有就追加
    if grep -q "^127\.0\.0\.1" /etc/hosts; then
        if grep -q "^127\.0\.0\.1.*\b${old_name}\b" /etc/hosts; then
            sed -i "/^127\.0\.0\.1[[:space:]]/ s/\b${old_name}\b/${new_name}/g" /etc/hosts
        else
            sed -i "s/^\(127\.0\.0\.1[[:space:]]\+.*\)$/\1 ${new_name}/" /etc/hosts
        fi
    else
        echo "127.0.0.1 localhost $new_name" >> /etc/hosts
    fi
    # ::1 行同理
    if grep -q "^::1" /etc/hosts; then
        if grep -q "^::1.*\b${old_name}\b" /etc/hosts; then
            sed -i "/^::1[[:space:]]/ s/\b${old_name}\b/${new_name}/g" /etc/hosts
        else
            sed -i "s/^\(::1[[:space:]]\+.*\)$/\1 ${new_name}/" /etc/hosts
        fi
    else
        echo "::1 localhost $new_name" >> /etc/hosts
    fi
    ok "主机名已改为 $new_name（/etc/hosts 已备份到 $hosts_bak）。"
    hostname
    pause
}

# ── 13-19. 切换系统更新源 ─────────────────────────────────────────
# 用 linuxmirrors 脚本换源（第三方脚本，执行前会警告并要确认）。
# 与 kejilion 不同：不自动查 ipinfo.io 判断国家，由用户自己选。
# 换源前先下载到临时文件，打印大小与 SHA-256，确认后再执行；
# 参数固定 --backup true（换源前备份原配置）。
settings_mirror() {
    need_root || return 1
    require_debian_ubuntu || return 1

    local choice="" source_args=() tmp_script=""
    box_title "切换系统更新源"
    warn "本质是下载执行第三方换源脚本（linuxmirrors.cn/main.sh），"
    warn "只有默认源慢或坏时才用；正常情况不要切。"
    echo "------------------------"
    echo "1. 国内镜像（华为云）"
    echo "2. 海外镜像（xtom）"
    echo "3. 官方源"
    echo "------------------------"
    echo "0. 返回上一级选单"
    echo "------------------------"
    read -r -p "请输入你的选择: " choice
    case "$choice" in
        1) source_args=(--source mirrors.huaweicloud.com) ;;
        2) source_args=(--source mirrors.xtom.com) ;;
        3) source_args=(--use-official-source true) ;;
        0|"") return 0 ;;
        *) echo "无效的选择。"; pause; return 1 ;;
    esac
    confirm "确定换源吗？（换源前会备份原配置）" || { echo "已取消。"; pause; return 0; }

    tmp_script="$(mktemp /tmp/linuxmirrors-main.XXXXXX.sh)" || {
        err "无法创建临时文件。"; pause; return 1
    }
    echo "正在下载 linuxmirrors 换源脚本..."
    if ! curl -fsSL --max-time 60 "https://linuxmirrors.cn/main.sh" -o "$tmp_script"; then
        err "下载失败，请检查网络后重试。"
        rm -f -- "$tmp_script"; pause; return 1
    fi
    if [ ! -s "$tmp_script" ]; then
        err "下载的文件为空，已取消。"
        rm -f -- "$tmp_script"; pause; return 1
    fi
    echo "已下载：$(wc -c < "$tmp_script") 字节，SHA-256：$(sha256sum "$tmp_script" | awk '{print $1}')"
    confirm "确认执行该换源脚本吗？" || {
        echo "已取消。"
        rm -f -- "$tmp_script"; pause; return 0
    }
    bash "$tmp_script" "${source_args[@]}" \
        --protocol https \
        --use-intranet-source false \
        --backup true \
        --upgrade-software false \
        --clean-cache false \
        --ignore-backup-tips \
        --install-epel false \
        --pure-mode
    local rc=$?
    rm -f -- "$tmp_script"
    if [ "$rc" -eq 0 ]; then
        if apt-get update -y >/dev/null 2>&1; then
            ok "换源完成且 apt update 通过。"
        else
            warn "换源脚本成功但 apt update 失败，请检查源是否可用。"
        fi
    else
        err "换源脚本退出码：$rc，请查看上面的输出。"
    fi
    pause
}

# ── 13-22. SSH 防御程序 fail2ban ───────────────────────────────────
# 装 fail2ban + rsyslog；默认参数 bantime=10m、findtime=10m、
# maxretry=5（用户标准），写 /etc/fail2ban/jail.d/sshd.local；
# 默认开启 recidive 监狱：1 天内被封 5 次 → 封 1 周。
# 与 kejilion 不同：卸载只停服务、删包，不 rm -rf /etc/fail2ban，
# 配置保留。
F2B_SSHD_LOCAL="/etc/fail2ban/jail.d/sshd.local"
F2B_RECIDIVE_LOCAL="/etc/fail2ban/jail.d/recidive.local"

f2b_write_sshd_local() {
    # $1 bantime，$2 findtime，$3 maxretry
    local bantime="$1" findtime="$2" maxretry="$3"
    mkdir -p /etc/fail2ban/jail.d
    cat > "$F2B_SSHD_LOCAL" <<EOF
[sshd]
# 由 vps-toolbox 管理
enabled = true
bantime = $bantime
findtime = $findtime
maxretry = $maxretry
logpath = /var/log/auth.log
EOF
}

f2b_write_recidive_local() {
    mkdir -p /etc/fail2ban/jail.d
    cat > "$F2B_RECIDIVE_LOCAL" <<EOF
[recidive]
# 由 vps-toolbox 管理：反复被封的 IP 加重处罚
enabled = true
logpath = /var/log/fail2ban.log
bantime = 1w
findtime = 1d
maxretry = 5
EOF
}

f2b_install() {
    echo "正在安装 fail2ban ..."
    apt_install rsyslog || return 1
    systemctl enable --now rsyslog.service 2>/dev/null || true
    if ! systemctl is-active --quiet rsyslog.service 2>/dev/null; then
        warn "rsyslog 未能启动，/var/log/auth.log 可能不再写入，fail2ban 的 sshd 规则可能看不到新失败记录。"
    fi
    if [ ! -e /var/log/auth.log ]; then
        touch /var/log/auth.log || return 1
        chmod 0640 /var/log/auth.log || return 1
    fi
    apt_install fail2ban || return 1
    # 默认参数：用户标准（5 次失败封 10 分钟）
    f2b_write_sshd_local "10m" "10m" "5"
    # 默认开启 recidive：1 天内被封 5 次 → 封 1 周
    f2b_write_recidive_local
    systemctl enable --now fail2ban.service || {
        err "fail2ban 服务启动失败。"
        return 1
    }
    fail2ban-client -t >/dev/null 2>&1 || {
        err "fail2ban 配置校验失败。"
        return 1
    }
    fail2ban-client reload >/dev/null 2>&1 || systemctl restart fail2ban.service
    sleep 1
    ok "fail2ban 已安装并启用。"
    echo "默认参数：bantime=10m findtime=10m maxretry=5"
    echo "累犯加重已开启：1 天内被封 5 次 → 封 1 周（recidive）。"
    fail2ban-client status sshd 2>/dev/null || true
}

f2b_basic_config() {
    local bantime="" findtime="" maxretry="" backup=""
    if ! command -v fail2ban-client >/dev/null 2>&1; then
        err "未检测到 fail2ban，请先安装。"
        return 1
    fi
    box_title "基础参数配置（SSH jail）"
    read -r -p "封禁时长 bantime（秒/分钟/小时，如 600 或 10m）[默认 10m]: " bantime
    read -r -p "时间窗口 findtime（秒/分钟/小时，如 600 或 10m）[默认 10m]: " findtime
    read -r -p "重试次数 maxretry（整数）[默认 5]: " maxretry
    bantime="${bantime:-10m}"
    findtime="${findtime:-10m}"
    maxretry="${maxretry:-5}"
    if [[ ! "$bantime" =~ ^[0-9]+[smhdw]?$ ]]; then
        err "封禁时长无效：$bantime（格式如 600、10m、1h、1d、1w）。"
        return 1
    fi
    if [[ ! "$findtime" =~ ^[0-9]+[smhdw]?$ ]]; then
        err "时间窗口无效：$findtime（格式如 600、10m、1h、1d、1w）。"
        return 1
    fi
    if [[ ! "$maxretry" =~ ^[0-9]+$ ]] || [ "$maxretry" -lt 1 ] || [ "$maxretry" -gt 100 ]; then
        err "重试次数无效：$maxretry（1-100）。"
        return 1
    fi
    # 时长为 0 等于不封禁，拒绝
    local bantime_num="" findtime_num=""
    bantime_num="$(printf '%s' "$bantime" | grep -oE '^[0-9]+')"
    findtime_num="$(printf '%s' "$findtime" | grep -oE '^[0-9]+')"
    if [ "$bantime_num" -eq 0 ] || [ "$findtime_num" -eq 0 ]; then
        err "时长不能为 0。"
        return 1
    fi
    # 写前备份，校验失败时恢复
    if [ -f "$F2B_SSHD_LOCAL" ]; then
        backup="${F2B_SSHD_LOCAL}.bak.$(date +%Y%m%d%H%M%S)"
        cp "$F2B_SSHD_LOCAL" "$backup"
        prune_backups /etc/fail2ban/jail.d "sshd.local.bak.*"
    fi
    f2b_write_sshd_local "$bantime" "$findtime" "$maxretry"
    if ! fail2ban-client -t >/dev/null 2>&1; then
        if [ -n "$backup" ]; then
            cp "$backup" "$F2B_SSHD_LOCAL"
            err "配置校验失败（fail2ban-client -t），已恢复备份 $backup，未生效。"
        else
            rm -f "$F2B_SSHD_LOCAL"
            err "配置校验失败（fail2ban-client -t），已删除新写的文件，未生效。"
        fi
        return 1
    fi
    ok "已写入：$F2B_SSHD_LOCAL"
    if ! fail2ban-client reload >/dev/null 2>&1; then
        warn "配置已写入并通过校验，但 reload 失败，请手工执行 fail2ban-client reload。"
    fi
    sleep 1
    fail2ban-client status sshd 2>/dev/null || true
}

f2b_uninstall() {
    warn "卸载只停止服务、删除软件包，/etc/fail2ban 下的配置会保留，"
    warn "以后重装还能继续用。"
    confirm "确定卸载 fail2ban 吗？" || { echo "已取消。"; return 0; }
    systemctl stop fail2ban.service 2>/dev/null || true
    systemctl disable fail2ban.service 2>/dev/null || true
    if DEBIAN_FRONTEND=noninteractive apt-get purge -y fail2ban 2>/dev/null \
        || DEBIAN_FRONTEND=noninteractive apt-get remove -y fail2ban; then
        ok "fail2ban 已卸载，配置保留在 /etc/fail2ban。"
    else
        err "fail2ban 卸载失败，请查看上面的报错。"
        return 1
    fi
}

settings_fail2ban() {
    need_root || return 1
    require_debian_ubuntu || return 1

    local choice=""
    while true; do
        cls
        box_title "SSH 防御程序 fail2ban"
        if command -v fail2ban-client >/dev/null 2>&1 && fail2ban-client ping >/dev/null 2>&1; then
            echo "状态：运行中"
            fail2ban-client status sshd 2>/dev/null | grep -E "Currently banned|Total banned" || true
        elif command -v fail2ban-client >/dev/null 2>&1; then
            echo "状态：已安装，未运行"
        else
            echo "状态：未安装"
        fi
        echo "------------------------"
        echo "1. 安装 fail2ban（默认 10 分钟封禁 + 累犯加重）"
        echo "2. 查看 jail 状态"
        echo "3. 查看拦截记录 / 日志"
        echo "4. 基础参数配置（bantime / findtime / maxretry）"
        echo "5. 编辑配置文件（nano）"
        echo "6. 卸载 fail2ban（保留配置）"
        echo "------------------------"
        echo "0. 返回上一级选单"
        echo "------------------------"
        read -r -p "请输入你的选择: " choice
        case "$choice" in
            1)
                f2b_install || true
                pause
                ;;
            2)
                if command -v fail2ban-client >/dev/null 2>&1; then
                    fail2ban-client status 2>/dev/null
                    echo
                    fail2ban-client status sshd 2>/dev/null
                    echo
                    fail2ban-client status recidive 2>/dev/null || true
                else
                    err "fail2ban 未安装。"
                fi
                pause
                ;;
            3)
                echo "------------------------"
                echo "最近被封 IP"
                echo "------------------------"
                if command -v fail2ban-client >/dev/null 2>&1; then
                    fail2ban-client status sshd 2>/dev/null | sed -n '/Banned IP/,$p' || echo "（无）"
                fi
                echo
                echo "------------------------"
                echo "最近 20 行 fail2ban 日志"
                echo "------------------------"
                if [ -f /var/log/fail2ban.log ]; then
                    tail -n 20 /var/log/fail2ban.log
                else
                    echo "未找到 /var/log/fail2ban.log"
                fi
                pause
                ;;
            4)
                f2b_basic_config || true
                pause
                ;;
            5)
                if [ ! -d /etc/fail2ban ]; then
                    err "/etc/fail2ban 不存在，请先安装 fail2ban。"
                    pause; continue
                fi
                apt_install nano || { pause; continue; }
                [ -f "$F2B_SSHD_LOCAL" ] || f2b_write_sshd_local "10m" "10m" "5"
                nano "$F2B_SSHD_LOCAL"
                if fail2ban-client -t >/dev/null 2>&1; then
                    echo "已保存，正在 reload fail2ban..."
                    if fail2ban-client reload >/dev/null 2>&1; then
                        ok "配置已生效。"
                    else
                        warn "配置校验通过，但 reload 失败，请手工执行 fail2ban-client reload。"
                    fi
                else
                    err "配置校验失败（fail2ban-client -t），请检查刚改的内容，未 reload。"
                fi
                pause
                ;;
            6)
                f2b_uninstall || true
                pause
                ;;
            0|"") break ;;
            *) echo "无效的选择。"; pause ;;
        esac
    done
}

# ── 13-28. Linux 系统内核参数优化（基线预设） ─────────────────────
# 照 kejilion 的 Kernel_optimize / _kernel_optimize_core 的固定预设，
# 只保留 5 个模式 + 还原默认；子项 7（管道执行远程 network-optimize.sh）
# 不要。写到 /etc/sysctl.d/99-vps-toolbox-optimize.conf。
#
# ！！！分工边界！！！
# 本项只给基线初始值，只在新机初始化、跑 vps-tune 之前用。
# vps-tune 调好后绝不要再点本项，否则会把 vps-tune 按实测给的
# 最终值重写回固定预设。
KERNEL_OPT_CONF="/etc/sysctl.d/99-vps-toolbox-optimize.conf"

kernel_optimize_core() {
    local mode_name="$1"
    local scene="${2:-high}"
    local conf="$KERNEL_OPT_CONF"
    local mem_mb=0
    mem_mb="$(get_mem_mb)"

    echo "切换到 ${mode_name}..."

    local swappiness="" dirty_ratio="" dirty_bg_ratio="" overcommit=""
    local min_free_kb="" vfs_pressure=""
    local rmem_max="" wmem_max="" tcp_rmem="" tcp_wmem=""
    local somaxconn="" backlog="" syn_backlog=""
    local port_range="" sched_autogroup="" thp="" numa="" fin_timeout=""
    local keepalive_time="" keepalive_intvl="" keepalive_probes=""

    case "$scene" in
        high|stream|game)
            swappiness=10; dirty_ratio=15; dirty_bg_ratio=5; overcommit=1
            vfs_pressure=50
            rmem_max=67108864; wmem_max=67108864
            tcp_rmem="4096 262144 67108864"; tcp_wmem="4096 262144 67108864"
            somaxconn=8192; backlog=250000; syn_backlog=8192
            port_range="1024 65535"; sched_autogroup=0; thp="never"; numa=0
            fin_timeout=10; keepalive_time=300; keepalive_intvl=30; keepalive_probes=5
            ;;
        web)
            swappiness=10; dirty_ratio=20; dirty_bg_ratio=10; overcommit=1
            vfs_pressure=50
            rmem_max=33554432; wmem_max=33554432
            tcp_rmem="4096 131072 33554432"; tcp_wmem="4096 131072 33554432"
            somaxconn=16384; backlog=10000; syn_backlog=16384
            port_range="1024 65535"; sched_autogroup=0; thp="never"; numa=0
            fin_timeout=15; keepalive_time=600; keepalive_intvl=60; keepalive_probes=5
            ;;
        balanced)
            swappiness=30; dirty_ratio=20; dirty_bg_ratio=10; overcommit=0
            vfs_pressure=75
            rmem_max=16777216; wmem_max=16777216
            tcp_rmem="4096 87380 16777216"; tcp_wmem="4096 65536 16777216"
            somaxconn=4096; backlog=5000; syn_backlog=4096
            port_range="1024 49151"; sched_autogroup=1; thp="always"; numa=1
            fin_timeout=30; keepalive_time=600; keepalive_intvl=60; keepalive_probes=5
            ;;
    esac

    # 按内存大小自适应调整
    if [ "$mem_mb" -ge 16384 ]; then
        min_free_kb=131072
        [ "$scene" != "balanced" ] && swappiness=5
    elif [ "$mem_mb" -ge 4096 ]; then
        min_free_kb=65536
    elif [ "$mem_mb" -ge 1024 ]; then
        min_free_kb=32768
        if [ "$scene" != "balanced" ]; then
            rmem_max=16777216; wmem_max=16777216
            tcp_rmem="4096 87380 16777216"; tcp_wmem="4096 65536 16777216"
        fi
    else
        min_free_kb=16384; swappiness=30; overcommit=0
        rmem_max=4194304; wmem_max=4194304
        tcp_rmem="4096 32768 4194304"; tcp_wmem="4096 32768 4194304"
        somaxconn=1024; backlog=1000
    fi

    local stream_extra="" game_extra=""
    if [ "$scene" = "stream" ]; then
        stream_extra="
# 直播推流 UDP 优化
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
net.ipv4.tcp_notsent_lowat = 16384"
    fi
    if [ "$scene" = "game" ]; then
        game_extra="
# 游戏服低延迟优化
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_slow_start_after_idle = 0"
    fi

    # 拥塞算法：内核 >= 4.9 且有 bbr 模块就用 bbr，否则 cubic
    local cc="bbr" qdisc="fq" kver=""
    kver="$(uname -r | sed -E 's/^([0-9]+\.[0-9]+).*/\1/')"
    if printf '%s\n%s' "4.9" "$kver" | sort -V -C; then
        if ! lsmod 2>/dev/null | grep -q tcp_bbr; then
            modprobe tcp_bbr 2>/dev/null || true
        fi
        if ! sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -q bbr; then
            cc="cubic"; qdisc="fq_codel"
        fi
    else
        cc="cubic"; qdisc="fq_codel"
    fi

    [ -f "$conf" ] && cp "$conf" "${conf}.bak.$(date +%s)-$$"
    prune_backups /etc/sysctl.d "99-vps-toolbox-optimize.conf.bak.*"

    echo "写入优化配置..."
    cat > "$conf" << SYSCTL
# vps-toolbox 内核调优配置
# 模式: $mode_name | 场景: $scene
# 内存: ${mem_mb}MB | 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
# 注意：这是基线预设（初始值），只在跑 vps-tune 之前用；
# vps-tune 调好后绝不要再用本项重写参数。

# ── TCP 拥塞控制 ──
net.core.default_qdisc = $qdisc
net.ipv4.tcp_congestion_control = $cc

# ── TCP 缓冲区 ──
net.core.rmem_max = $rmem_max
net.core.wmem_max = $wmem_max
net.core.rmem_default = $(echo "$tcp_rmem" | awk '{print $2}')
net.core.wmem_default = $(echo "$tcp_wmem" | awk '{print $2}')
net.ipv4.tcp_rmem = $tcp_rmem
net.ipv4.tcp_wmem = $tcp_wmem

# ── 连接队列 ──
net.core.somaxconn = $somaxconn
net.core.netdev_max_backlog = $backlog
net.ipv4.tcp_max_syn_backlog = $syn_backlog

# ── TCP 连接优化 ──
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = $fin_timeout
net.ipv4.tcp_keepalive_time = $keepalive_time
net.ipv4.tcp_keepalive_intvl = $keepalive_intvl
net.ipv4.tcp_keepalive_probes = $keepalive_probes
net.ipv4.tcp_max_tw_buckets = 65536
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_window_scaling = 1

# ── 端口与内存 ──
net.ipv4.ip_local_port_range = $port_range
net.ipv4.tcp_mem = $((mem_mb * 1024 / 8)) $((mem_mb * 1024 / 4)) $((mem_mb * 1024 / 2))
net.ipv4.tcp_max_orphans = 32768

# ── 虚拟内存 ──
vm.swappiness = $swappiness
vm.dirty_ratio = $dirty_ratio
vm.dirty_background_ratio = $dirty_bg_ratio
vm.overcommit_memory = $overcommit
vm.min_free_kbytes = $min_free_kb
vm.vfs_cache_pressure = $vfs_pressure

# ── CPU/内核调度 ──
kernel.sched_autogroup_enabled = $sched_autogroup
$([ -f /proc/sys/kernel/numa_balancing ] && echo "kernel.numa_balancing = $numa" || echo "# numa_balancing 不支持")

# ── 安全防护 ──
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# ── 文件描述符 ──
fs.file-max = 1048576
fs.nr_open = 1048576

# ── 连接跟踪 ──
$(if [ -f /proc/sys/net/netfilter/nf_conntrack_max ]; then
echo "net.netfilter.nf_conntrack_max = $((somaxconn * 32))"
echo "net.netfilter.nf_conntrack_tcp_timeout_established = 7200"
echo "net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30"
echo "net.netfilter.nf_conntrack_tcp_timeout_close_wait = 15"
echo "net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 15"
else
echo "# conntrack 未启用"
fi)
$stream_extra
$game_extra
SYSCTL

    echo "应用优化参数..."
    local applied=0 skipped=0 line="" key="" skipped_list=""
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue
        if sysctl -w "$line" >/dev/null 2>&1; then
            applied=$((applied + 1))
        else
            skipped=$((skipped + 1))
            key="${line%%=*}"
            key="${key//[[:space:]]/}"
            if [ -z "$skipped_list" ]; then
                skipped_list="$key"
            else
                skipped_list="$skipped_list，$key"
            fi
        fi
    done < "$conf"
    echo "已应用 ${applied} 项参数${skipped:+，跳过 ${skipped} 项不支持的参数}"
    if [ "$skipped" -gt 0 ]; then
        echo "跳过的参数：$skipped_list"
    fi

    if [ -f /sys/kernel/mm/transparent_hugepage/enabled ]; then
        echo "$thp" > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
    fi

    if ! grep -q "# vps-toolbox-optimize" /etc/security/limits.conf 2>/dev/null; then
        cat >> /etc/security/limits.conf << 'LIMITS'

# vps-toolbox-optimize
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
LIMITS
    fi

    if [ "$cc" = "bbr" ]; then
        echo "tcp_bbr" > /etc/modules-load.d/bbr.conf 2>/dev/null || true
        sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf 2>/dev/null || true
    fi

    ok "${mode_name} 优化完成！配置已持久化到 ${conf}"
    echo "内存：${mem_mb}MB | 拥塞算法：$cc | 队列：$qdisc"
}

kernel_optimize_restore() {
    echo "还原到默认设置..."
    rm -f "$KERNEL_OPT_CONF"
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf 2>/dev/null || true
    sysctl --system 2>/dev/null | tail -1
    [ -f /sys/kernel/mm/transparent_hugepage/enabled ] && \
        echo always > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
    if grep -q "# vps-toolbox-optimize" /etc/security/limits.conf 2>/dev/null; then
        sed -i '/# vps-toolbox-optimize/,+4d' /etc/security/limits.conf
    fi
    rm -f /etc/modules-load.d/bbr.conf 2>/dev/null || true
    ok "优化配置已删除，运行时的参数需重启后才完全恢复。"
    if confirm "现在重启服务器吗？"; then
        reboot
    fi
}

settings_kernel_optimize() {
    need_root || return 1
    require_debian_ubuntu || return 1

    local choice="" current_mode=""
    while true; do
        cls
        current_mode="$(grep "^# 模式:" "$KERNEL_OPT_CONF" 2>/dev/null | sed 's/# 模式: //' | awk -F'|' '{print $1}' | xargs)"
        box_title "Linux 系统内核参数优化（基线预设）"
        if [ -n "$current_mode" ]; then
            echo "当前模式：$current_mode"
        else
            echo "当前模式：未优化"
        fi
        echo "------------------------"
        err "分工边界：本项只给基线初始值，只在新机初始化、跑 vps-tune 之前用。"
        err "vps-tune 调好后绝不要再点本项，会把调优结果重写回固定预设。"
        echo "------------------------"
        echo "1. 高性能优化模式：最大化系统性能，激进的内存和网络参数。"
        echo "2. 均衡优化模式：性能与资源消耗之间取得平衡，适合日常使用。"
        echo "3. 网站优化模式：针对网站服务器优化，超高并发连接队列。"
        echo "4. 直播优化模式：针对直播推流优化，UDP 缓冲区加大，减少延迟。"
        echo "5. 游戏服优化模式：针对游戏服务器优化，低延迟优先。"
        echo "6. 还原默认设置：将系统设置还原为默认配置。"
        echo "------------------------"
        echo "0. 返回上一级选单"
        echo "------------------------"
        read -r -p "请输入你的选择: " choice
        case "$choice" in
            1)
                confirm "确定切换到高性能优化模式吗？" || { echo "已取消。"; pause; continue; }
                kernel_optimize_core "高性能优化模式" "high"
                pause
                ;;
            2)
                confirm "确定切换到均衡优化模式吗？" || { echo "已取消。"; pause; continue; }
                kernel_optimize_core "均衡优化模式" "balanced"
                pause
                ;;
            3)
                confirm "确定切换到网站优化模式吗？" || { echo "已取消。"; pause; continue; }
                kernel_optimize_core "网站搭建优化模式" "web"
                pause
                ;;
            4)
                confirm "确定切换到直播优化模式吗？" || { echo "已取消。"; pause; continue; }
                kernel_optimize_core "直播优化模式" "stream"
                pause
                ;;
            5)
                confirm "确定切换到游戏服优化模式吗？" || { echo "已取消。"; pause; continue; }
                kernel_optimize_core "游戏服优化模式" "game"
                pause
                ;;
            6)
                confirm "确定还原到默认设置吗？" || { echo "已取消。"; pause; continue; }
                kernel_optimize_restore
                pause
                ;;
            0|"") break ;;
            *) echo "无效的选择。"; pause ;;
        esac
    done
}

# ── 13-41. 系统日志管理工具 ───────────────────────────────────────
# 照 kejilion 的 log_menu，以只读查看为主，清理走 journalctl 安全方式。
settings_logs() {
    local choice="" count="" svc="" c=""
    while true; do
        cls
        box_title "系统日志管理"
        echo "主机名：$(hostname)"
        echo "系统时间：$(date)"
        echo
        echo "[ /var/log 目录占用 ]"
        du -sh /var/log 2>/dev/null || echo "（无法读取）"
        echo
        echo "[ journal 日志占用 ]"
        journalctl --disk-usage 2>/dev/null || echo "（无法读取）"
        echo "------------------------"
        echo "1. 查看最近系统日志（journal）"
        echo "2. 查看指定服务日志"
        echo "3. 查看登录/安全日志"
        echo "4. 实时跟踪日志"
        echo "5. 清理旧 journal 日志"
        echo "0. 返回上一级选单"
        echo "------------------------"
        read -r -p "请选择操作: " choice
        case "$choice" in
            1)
                read -r -p "查看最近多少行日志？[默认 100]: " count
                count="${count:-100}"
                if [[ ! "$count" =~ ^[0-9]+$ ]]; then
                    warn "行数无效，已用默认值 100。"
                    count=100
                fi
                journalctl -n "$count" --no-pager
                pause
                ;;
            2)
                read -r -p "请输入服务名（如 sshd、nginx）: " svc
                if [ -z "$svc" ]; then
                    echo "服务名为空。"
                elif [[ ! "$svc" =~ ^[A-Za-z0-9@._-]+$ ]]; then
                    echo "服务名无效。"
                elif systemctl show -p LoadState --value "$svc" 2>/dev/null | grep -qx "loaded"; then
                    journalctl -u "$svc" -n 100 --no-pager
                else
                    echo "服务不存在或无日志：$svc"
                fi
                pause
                ;;
            3)
                echo "------------------------"
                echo "最近登录日志"
                echo "------------------------"
                last -n 10 2>/dev/null || echo "（无法读取）"
                echo
                echo "------------------------"
                echo "认证日志"
                echo "------------------------"
                if [ -f /var/log/auth.log ]; then
                    tail -n 20 /var/log/auth.log
                else
                    echo "未找到安全日志文件"
                fi
                pause
                ;;
            4)
                echo "1) 系统日志"
                echo "2) 指定服务日志"
                read -r -p "选择跟踪类型: " c
                if [ "$c" = "1" ]; then
                    journalctl -f
                elif [ "$c" = "2" ]; then
                    read -r -p "输入服务名: " svc
                    journalctl -u "$svc" -f
                else
                    echo "无效选择"
                fi
                pause
                ;;
            5)
                echo "清理 journal 日志（安全方式）"
                echo "1) 保留最近 7 天"
                echo "2) 保留最近 3 天"
                echo "3) 限制日志最大 500M"
                read -r -p "请选择清理方式: " c
                case "$c" in
                    1) journalctl --vacuum-time=7d && ok "journal 日志清理完成。" ;;
                    2) journalctl --vacuum-time=3d && ok "journal 日志清理完成。" ;;
                    3) journalctl --vacuum-size=500M && ok "journal 日志清理完成。" ;;
                    *) echo "无效选项" ;;
                esac
                sleep 1
                ;;
            0|"") break ;;
            *) echo "无效的选择。"; pause ;;
        esac
    done
}

# ── 13-42. 系统变量管理工具 ───────────────────────────────────────
# 照 kejilion 的 env_menu：查看已生效变量与配置文件里的变量，
# 可 nano 编辑、source 重载（重载只对当前脚本会话生效，
# 新登录的 shell 才会用新值）。
settings_env() {
    local bashrc="$HOME/.bashrc"
    local profile="$HOME/.profile"
    local choice=""

    show_env_vars() {
        cls
        box_title "当前已生效环境变量（节选）"
        printf "%-20s %s\n" "变量名" "值"
        echo "------------------------"
        local v=""
        for v in USER HOME SHELL LANG PWD; do
            printf "%-20s %s\n" "$v" "${!v:-}"
        done
        echo
        echo "PATH:"
        echo "$PATH" | tr ':' '\n' | nl -ba
        echo
        box_title "配置文件中定义的变量（解析）"
        parse_file_vars() {
            local f="$1"
            [ -f "$f" ] || return
            echo
            echo ">>> 来源文件：$f"
            echo "------------------------"
            grep -Ev '^\s*#|^\s*$' "$f" \
            | grep -E '^(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*=' \
            | while read -r line; do
                local var="" val=""
                var="$(echo "$line" | sed -E 's/^(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*).*/\2/')"
                val="$(echo "$line" | sed -E 's/^[^=]+=//')"
                printf "%-20s %s\n" "$var" "$val"
            done
        }
        parse_file_vars "$HOME/.bashrc"
        parse_file_vars "$HOME/.profile"
        echo
        echo "------------------------"
        pause
    }

    while true; do
        cls
        box_title "系统环境变量管理"
        echo "当前用户：${USER:-未知}"
        echo "------------------------"
        echo "1. 查看当前常用环境变量"
        echo "2. 查看 ~/.bashrc"
        echo "3. 查看 ~/.profile"
        echo "4. 编辑 ~/.bashrc"
        echo "5. 编辑 ~/.profile"
        echo "6. 重新加载环境变量（source，仅当前会话）"
        echo "------------------------"
        echo "0. 返回上一级选单"
        echo "------------------------"
        read -r -p "请选择操作: " choice
        case "$choice" in
            1) show_env_vars ;;
            2)
                cls
                if [ -f "$bashrc" ]; then
                    echo "------------------------"
                    echo "查看文件：$bashrc"
                    echo "------------------------"
                    cat -n "$bashrc"
                else
                    echo "文件不存在：$bashrc"
                fi
                pause
                ;;
            3)
                cls
                if [ -f "$profile" ]; then
                    echo "------------------------"
                    echo "查看文件：$profile"
                    echo "------------------------"
                    cat -n "$profile"
                else
                    echo "文件不存在：$profile"
                fi
                pause
                ;;
            4)
                apt_install nano || { pause; continue; }
                nano "$bashrc"
                if [ -f "$bashrc" ] && ! bash -n "$bashrc"; then
                    warn "语法检查失败（bash -n），请检查刚改的内容，下次登录可能受影响。"
                fi
                ;;
            5)
                apt_install nano || { pause; continue; }
                nano "$profile"
                if [ -f "$profile" ] && ! bash -n "$profile"; then
                    warn "语法检查失败（bash -n），请检查刚改的内容，下次登录可能受影响。"
                fi
                ;;
            6)
                echo "正在重新加载环境变量（只对当前脚本会话生效，新登录才用新值）..."
                local src_ok=1
                if [ -f "$bashrc" ]; then
                    # shellcheck disable=SC1090
                    if ! source "$bashrc"; then
                        warn "重载 $bashrc 时有报错（见上面），请检查。"
                        src_ok=0
                    fi
                fi
                if [ -f "$profile" ]; then
                    # shellcheck disable=SC1090
                    if ! source "$profile"; then
                        warn "重载 $profile 时有报错（见上面），请检查。"
                        src_ok=0
                    fi
                fi
                if [ "$src_ok" -eq 1 ]; then
                    ok "环境变量已重新加载。"
                fi
                pause
                ;;
            0|"") break ;;
            *) echo "无效的选择。"; pause ;;
        esac
    done
}

# ── 13-99. 重启服务器 ─────────────────────────────────────────────
settings_reboot() {
    need_root || return 1
    box_title "重启服务器"
    if confirm "现在重启服务器吗？"; then
        echo "正在重启..."
        reboot
    else
        echo "已取消。"
        pause
    fi
}

# ── 13-101. 命令高级用法（只读帮助） ──────────────────────────────
show_help() {
    cls
    box_title "vps-toolbox 命令用法（v$VERSION）"
    echo "------------------------"
    echo "交互菜单："
    echo "  ./vps-toolbox.sh            打开主菜单"
    echo "  tbox                        打开主菜单（需先创建快捷键）"
    echo
    echo "直接子命令："
    echo "  tbox info                   系统信息查询"
    echo "  tbox update                 系统更新"
    echo "  tbox clean                  系统清理"
    echo "  tbox bbr                    BBR 管理（基线开启）"
    echo "  tbox warp                   WARP 管理"
    echo "  tbox settings               系统工具子菜单"
    echo "  tbox help                   显示本帮助"
    echo
    echo "主菜单："
    echo "  1 系统信息查询  2 系统更新  3 系统清理"
    echo "  5 BBR 管理      7 WARP 管理  13 系统工具"
    echo "  0 退出脚本"
    echo
    echo "系统工具子菜单（保留的编号）："
    echo "  1 快捷键  2 改密码  6 改 SSH 端口  7 DNS  8 重装系统"
    echo "  10 IPv4 优先  11 端口占用  12 swap  15 时区  16 BBRv3"
    echo "  18 主机名  19 换源  22 fail2ban  28 内核参数优化"
    echo "  41 日志管理  42 环境变量  99 重启  101 帮助  102 卸载"
    echo
    echo "新机初始化建议顺序："
    echo "  7（DNS 国内）→ 10（IPv4 优先）→ 12（swap 2048M）"
    echo "  → 15（上海时区）→ 18（主机名）→ 16（XanMod BBRv3，仅 x86 新机）"
    echo "  → 28（基线预设，仅跑 vps-tune 之前）"
    echo "  → 再跑 vps-tune 实测调优，调好后不再动 28 和 5。"
    echo
    echo "隐私：本脚本零遥测、零对外上报、不查询 IP。"
    echo "------------------------"
}

# ── 13-102. 卸载脚本 ──────────────────────────────────────────────
settings_uninstall() {
    box_title "卸载 vps-toolbox"
    echo "将删除：crontab 里 vps-toolbox 相关的行、/usr/local/bin 下"
    echo "指向本脚本的快捷键、本脚本文件本身。"
    echo "不会动系统配置、不会删其他工具。"
    confirm "确定卸载吗？" || { echo "已取消。"; pause; return 0; }
    # 清 crontab 里相关行
    # 先把 crontab -l 的结果落盘并判退出码：失败时绝不把空内容喂给 crontab -。
    if command -v crontab >/dev/null 2>&1; then
        local cron_tmp="" cron_out=""
        cron_tmp="$(mktemp /tmp/vps-toolbox-cron.XXXXXX)" || {
            err "无法创建临时文件，跳过 crontab 清理。"
            cron_tmp=""
        }
        if [ -n "$cron_tmp" ]; then
            cron_out="$(crontab -l 2>&1 > "$cron_tmp"; echo "rc=$?")"
            if printf '%s' "$cron_out" | grep -q '^rc=0$'; then
                grep -v "vps-toolbox" "$cron_tmp" | grep -v "vps_toolbox" | crontab - 2>/dev/null || true
                echo "已清理 crontab 里 vps-toolbox 相关的行。"
            elif printf '%s' "$cron_out" | grep -qi 'no crontab'; then
                echo "当前没有 crontab，无需清理。"
            else
                err "读取 crontab 失败，未做任何改动，请手工检查 crontab。"
            fi
            rm -f -- "$cron_tmp"
        fi
    fi
    # 删指向本脚本的软链
    local link=""
    for link in /usr/local/bin/tbox /usr/local/bin/vps-toolbox; do
        if [ -L "$link" ] && [ "$(readlink -f "$link" 2>/dev/null)" = "$SCRIPT_PATH" ]; then
            rm -f -- "$link"
            echo "已删除快捷键：$link"
        fi
    done
    echo "正在删除脚本文件本身：$SCRIPT_PATH"
    rm -f -- "$SCRIPT_PATH"
    echo "vps-toolbox 已卸载。"
    exit 0
}

# ── 13. 系统工具子菜单 ────────────────────────────────────────────
settings_menu() {
    need_root || return 1
    require_debian_ubuntu || return 1

    local choice="" w
    local lines=() left=() lw=0
    while true; do
        cls
        left=(
            "  ${C_CYAN}1.${C_RESET}   设置脚本启动快捷键"
            "  ${C_CYAN}6.${C_RESET}   修改 SSH 连接端口"
            "  ${C_CYAN}8.${C_RESET}   一键重装系统（仅空机器）"
            "  ${C_CYAN}11.${C_RESET}  查看端口占用状态"
            "  ${C_CYAN}15.${C_RESET}  系统时区调整"
            "  ${C_CYAN}18.${C_RESET}  修改主机名"
            "  ${C_CYAN}22.${C_RESET}  SSH 防御程序 fail2ban"
            "  ${C_CYAN}41.${C_RESET}  系统日志管理工具"
            "  ${C_CYAN}99.${C_RESET}  重启服务器"
            "  ${C_CYAN}102.${C_RESET} 卸载脚本"
        )
        lw=$(( $(max_width "${left[@]}") + 2 ))
        lines=(
            "  ${C_BOLD}${C_CYAN}系统工具${C_RESET}"
            "---"
            "$(pad_to "${left[0]}" "$lw")${C_CYAN}2.${C_RESET}   修改登录密码"
            "$(pad_to "${left[1]}" "$lw")${C_CYAN}7.${C_RESET}   优化 DNS 地址"
            "$(pad_to "${left[2]}" "$lw")${C_CYAN}10.${C_RESET}  切换优先 IPv4/IPv6"
            "$(pad_to "${left[3]}" "$lw")${C_CYAN}12.${C_RESET}  修改虚拟内存大小"
            "$(pad_to "${left[4]}" "$lw")${C_CYAN}16.${C_RESET}  设置 BBR3 加速"
            "$(pad_to "${left[5]}" "$lw")${C_CYAN}19.${C_RESET}  切换系统更新源"
            "$(pad_to "${left[6]}" "$lw")${C_CYAN}28.${C_RESET}  内核参数优化（基线预设）"
            "$(pad_to "${left[7]}" "$lw")${C_CYAN}42.${C_RESET}  系统变量管理工具"
            "$(pad_to "${left[8]}" "$lw")${C_CYAN}101.${C_RESET} 命令高级用法"
            "${left[9]}"
            "---"
            "  ${C_CYAN}0.${C_RESET}   返回主菜单"
        )
        w=$(max_width "${lines[@]}")
        box "$w" "${lines[@]}"
        read -r -p "请输入你的选择: " choice
        case "$choice" in
            1) settings_shortcut ;;
            2) settings_passwd ;;
            6) settings_ssh_port ;;
            7) settings_dns ;;
            8) settings_dd ;;
            10) settings_ipv4_first ;;
            11) settings_ports ;;
            12) settings_swap ;;
            15) settings_timezone ;;
            16) settings_bbr3 ;;
            18) settings_hostname ;;
            19) settings_mirror ;;
            22) settings_fail2ban ;;
            28) settings_kernel_optimize ;;
            41) settings_logs ;;
            42) settings_env ;;
            99) settings_reboot ;;
            101) show_help; pause ;;
            102) settings_uninstall ;;
            0|"") return 0 ;;
            *) echo "无效的选择。"; pause ;;
        esac
    done
}

# ── 主菜单 ────────────────────────────────────────────────────────
main_menu() {
    local choice="" w
    local lines=()
    while true; do
        cls
        lines=(
            "  ${C_BOLD}${C_CYAN}VPS 工具箱 v$VERSION（精简自研版）${C_RESET}"
            "  零遥测 · 仅 Debian/Ubuntu"
            "---"
            "  ${C_CYAN}1.${C_RESET}   系统信息查询"
            "  ${C_CYAN}2.${C_RESET}   系统更新"
            "  ${C_CYAN}3.${C_RESET}   系统清理"
            "  ${C_CYAN}5.${C_RESET}   BBR 管理"
            "  ${C_CYAN}7.${C_RESET}   WARP 管理"
            "  ${C_CYAN}13.${C_RESET}  系统工具"
            "---"
            "  ${C_CYAN}0.${C_RESET}   退出脚本"
        )
        w=$(max_width "${lines[@]}")
        box "$w" "${lines[@]}"
        read -r -p "请输入你的选择: " choice
        case "$choice" in
            1) sys_info ;;
            2) sys_update ;;
            3) sys_clean ;;
            5) bbr_enable ;;
            7) warp_manage ;;
            13) settings_menu ;;
            0|"") echo "再见。"; exit 0 ;;
            *) echo "无效的选择。"; pause ;;
        esac
    done
}

# ── 命令行入口 ────────────────────────────────────────────────────
if [ "$#" -eq 0 ]; then
    main_menu
    exit 0
fi

case "$1" in
    info)     sys_info ;;
    update)   sys_update ;;
    clean)    sys_clean ;;
    bbr)      bbr_enable ;;
    warp)     warp_manage ;;
    settings) settings_menu ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "用法：$0 [info|update|clean|bbr|warp|settings|help]"
        echo "不带参数打开交互菜单；tbox help 查看完整说明。"
        exit 1
        ;;
esac
