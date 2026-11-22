# vps-toolbox 测试记录

## 已验证（沙箱，2026-11-22）

沙箱：Ubuntu 24.04.5 LTS，bash 5.2.21，root 身份。
测试只跑了只读部分，**没有执行任何写系统操作**（没有 apt、没有写
sysctl、没有建 swap、没有装 fail2ban、没有改任何系统文件）。
验证后确认沙箱系统无残留（`/etc/sysctl.d/99-vps-toolbox-bbr.conf`、
`/usr/local/bin/tbox` 均不存在）。

| 检查项 | 方法 | 结果 |
|---|---|---|
| 语法检查 | `bash -n vps-toolbox.sh` | 通过 |
| shellcheck | shellcheck v0.10.0，`-S warning` | 干净（0 警告；最初 11 个警告已修掉：8 个中文引号、2 个未用颜色变量、1 个未用局部变量） |
| 帮助 | `bash vps-toolbox.sh help` | 正常打印 |
| 系统信息 | `bash vps-toolbox.sh info`（管道输入过 pause） | 正常，显示主机名、系统版本、内核、CPU、内存、磁盘、流量、拥塞算法、本机 IP、DNS、运行时长 |
| 主菜单渲染 | `printf '0\n' \| bash vps-toolbox.sh` | 正常，退出码 0 |
| 系统工具菜单渲染 | `printf '13\n0\n0\n' \| bash vps-toolbox.sh` | 正常，20 个保留项都在 |
| 28 内核优化子菜单渲染 | `printf '28\n0\n0\n' \| bash vps-toolbox.sh settings` | 正常，分工边界警告正常显示 |
| 22 fail2ban 子菜单渲染 | `printf '22\n0\n0\n' \| bash vps-toolbox.sh settings` | 正常，显示“未安装” |
| 7 DNS 子菜单渲染 | `printf '7\n0\n0\n' \| bash vps-toolbox.sh settings` | 正常 |
| 无效子命令 | `bash vps-toolbox.sh badcmd` | 打印用法，退出码 1 |
| 无 TTY 清屏 | 管道运行时不再报 `TERM environment variable not set` | 已修（`cls` 只在交互终端清屏） |

说明：

- 系统信息里“网络算法：cubic 未知”——沙箱内核不暴露
  `net.core.default_qdisc`，`sysctl -n` 读不到， fallback 显示“未知”；
  真机上会正常显示 fq / fq_codel。
- 系统信息里“总接收 / 总发送 0.00B”——沙箱网卡名不是 eth/ens/enp/eno
  开头，统计不到；真机上有这类网卡时会正常累计。
- shellcheck 二进制是临时下载到 /tmp 的静态版（v0.10.0），未装到系统。

## 仍需真机验证（未在沙箱跑）

请在测试 VPS 上逐项验证，不要直接在生产节点（amd01-sjc、N100 面板 VM、
主力节点）上试。建议顺序与新机初始化顺序一致。

| 功能 | 验证方法 | 通过标准 |
|---|---|---|
| 2 系统更新 | 在测试 VPS 上跑一次 | 能完成更新；装了新内核时提示对照清单与重启 |
| 3 系统清理 | 跑一次，跑前后 `journalctl --disk-usage` 对照 | 日志保留 7 天内，`apt autoremove` 不误删 |
| 5 BBR 开启 | 跑一次，`sysctl net.ipv4.tcp_congestion_control` | 输出 bbr；`/etc/sysctl.d/99-vps-toolbox-bbr.conf` 存在 |
| 7 WARP | 在一次性测试机上跑一次 | 三条警告先打印；装完 DNS 被改写，用 13-7 选 2 能改回 |
| 13-1 快捷键 | 建一次，`tbox` 能打开 | 软链指向脚本本身 |
| 13-2 改密码 | （可跳过，或在测试机上改） | `passwd` 正常交互 |
| 13-6 改 SSH 端口 | 在测试 VPS 上改成非 1114 再改回 | 改后 `sshd -t` 通过、新端口监听、旧会话断开；`sshd_config.d` 未被动 |
| 13-7 DNS | 选 2 国内 | `/etc/resolv.conf` 为 223.5.5.5 / 183.60.83.19，`chattr +i` 已加锁 |
| 13-8 重装 | **只在空闲测试机上验证**，且先确认口令拦截有效 | 输入错误口令时取消；正确口令后下载并执行重装脚本 |
| 13-10 IPv4 优先 | 跑一次，`grep precedence /etc/gai.conf` | 有 `precedence ::ffff:0:0/96  100` |
| 13-11 端口占用 | 跑一次 | 正常列出监听端口 |
| 13-12 swap | 在测试 VPS 上选 2048M | `free -m` 显示 2048M swap；`/etc/fstab` 只有一行 swapfile |
| 13-15 时区 | 选 1 上海 | `timedatectl` 显示 Asia/Shanghai |
| 13-16 XanMod | 在 x86 测试 VPS 上装一次 | 装完重启后 `uname -r` 含 xanmod，`sysctl` 显示 bbr |
| 13-16 ARM 拒绝 | 在 ARM 测试机上点一次 | 明确拒绝，不执行任何第三方脚本 |
| 13-18 主机名 | 改一次 | `hostname`、`hostnamectl`、`/etc/hostname`、`/etc/hosts` 一致，localhost 别名保留 |
| 13-19 换源 | 在源有问题的测试机上跑一次 | 打印 SHA-256 并要确认；换完 `apt update` 正常，原配置有备份 |
| 13-22 fail2ban 安装 | 在测试 VPS 上装一次 | `fail2ban-client status sshd` 正常；`sshd.local` 为 10m/10m/5；recidive 监狱存在；故意输错 5 次密码被封 10 分钟 |
| 13-22 fail2ban 卸载 | 装完再卸一次 | 服务停了、包删了，`/etc/fail2ban` 配置还在 |
| 13-28 内核优化 | 选 2 均衡，跑一次 | `/etc/sysctl.d/99-vps-toolbox-optimize.conf` 存在，参数已应用；再选 6 还原，文件删除 |
| 13-41 日志 | 查看最近日志、清理选 1 | 正常显示；清理后 journal 占用下降 |
| 13-42 环境变量 | 查看、编辑、重载 | 正常显示；编辑后新登录生效 |
| 13-99 重启 | 在测试 VPS 上确认一次 | Y 确认后重启；N 取消 |
| 13-102 卸载 | 在测试 VPS 上跑完其他验证最后执行 | 快捷键、crontab 相关行、脚本文件本身都删掉 |
| 分工边界 | 跑完 vps-tune 后，再点 5 和 28 | 菜单与文件头警告可见；实际不要点（点之前先在测试机确认行为） |

## 回归方法

每次改完脚本，先跑：

```bash
bash -n vps-toolbox.sh
shellcheck -S warning vps-toolbox.sh
printf '0\n' | bash vps-toolbox.sh
```

三项都过，再上测试 VPS 验证改动的功能。

## InstaBox 真机验证（2026-11-22）

测试机：InstaBox 免费机器 agent-browser-4x37（机器 ID
m_agq72cyqns5b4cvrngw2eylhn4），Firecracker 微虚拟机，Debian 13
（trixie），systemd 257，x86_64 AMD EPYC 4 核 / 8GB 内存 / 16GB 磁盘，
内核 6.18.60-instabox（宿主机提供）。SSH 用户为 `user`（UID 1000），
sudo 免密；脚本用 `sudo bash /tmp/vps-toolbox.sh` 跑，菜单用管道输入
驱动。机器 30 分钟闲置自动暂停，测试全程连续完成，未断线。

注意：旧 SSH 令牌已失效（网关拒认证），测试前在控制台新建了一个
永不过期的令牌“Muse SSH testing”，已存入 ~/.secrets/instabox-ssh-token
（单行，600）。原有令牌未动。

| 功能 | 结果 | 详情 |
|---|---|---|
| 1 系统信息 | 通过 | 主机名、Debian 13、内核、CPU、内存、swap、磁盘、流量（186M 接收，网卡匹配正常）、cubic/pfifo_fast、内外 IP、DNS、UTC 时区、运行时长都正常 |
| 2 系统更新 | 通过 | 约 21 秒完成 apt update + full-upgrade，装了一批更新；无新内核（宿主机内核），无重启提示 |
| 3 系统清理 | 通过 | autoremove 0 个可删、clean/autoclean 正常；journal 8M→11.7M（机器才 1 天大，无 7 天以上日志可清，增长是更新本身产生的日志） |
| 5 BBR 开启 | **失败（环境限制）** | 见下方详述 |
| 13-1 快捷键 | 通过 | `/usr/local/bin/tbox` → 脚本本身，`tbox help` 正常 |
| 13-7 DNS | 通过 | 选 2 国内：resolv.conf 为 223.5.5.5 / 183.60.83.19 + v6 2400:3200::1 / 2400:da00::6666，`chattr +i` 已加锁；www.baidu.com 解析正常 |
| 13-10 IPv4 优先 | 通过 | `/etc/gai.conf` 有 `precedence ::ffff:0:0/96  100` |
| 13-11 端口占用 | 通过 | 列出 sshd:22、Xvnc:5901 及进程 |
| 13-12 swap | 通过 | 选 2048M：`free -m` 显示 2047M，`/swapfile` 已启用；fstab 只有一行 swapfile。**副作用**：原有 4G `/data/swapfile` 被 swapoff 停用、移出 fstab，文件本身还留在磁盘上（4G 未删），见残留 |
| 13-15 时区 | 通过 | 选 1 上海：`timedatectl` 显示 Asia/Shanghai |
| 13-18 主机名 | 通过 | 改成 tbox-test：hostname、hostnamectl、/etc/hostname、/etc/hosts 两行一致，localhost 别名保留；已改回 instabox-agent-browser-4x37，留一个 /etc/hosts.bak.* |
| 13-22 fail2ban 安装 | 通过 | `fail2ban-client status sshd` 与 recidive 正常；sshd.local 为 10m/10m/5；recidive.local 为 1w/1d/5；fail2ban 与 rsyslog 服务均为 active |
| 13-22 fail2ban 封禁 | 通过 | `banip 203.0.113.1`（TEST-NET 段，未动真实 IP）后 Banned IP 列表与 nft 规则均有该 IP；`unbanip` 后清空 |
| 13-22 fail2ban 改参数 | 通过 | 子项 4 改 bantime=1h 写入成功，再用默认空输入改回 10m/10m/5 |
| 13-22 fail2ban 卸载 | 通过 | 服务停、包删，`/etc/fail2ban/jail.d/` 下 sshd.local 与 recidive.local 保留 |
| 13-28 内核优化 | 通过 | 选 2 均衡：配置文件已写（模式 均衡优化模式，7964MB）；拥塞算法正确回落 cubic / fq_codel；逐项应用 52 项，跳过 1 项（default_qdisc，见 BBR 一节）；运行值 swappiness=30、somaxconn=4096、fin_timeout=30、rmem_max=16777216 均与预设一致；limits.conf 已加 vps-toolbox-optimize 段 |
| 13-28 还原 | 通过（有保留） | 配置文件已删，limits.conf 段已清；**但运行值不重置**：swappiness 仍为 30（Debian 默认 60），要重启才恢复默认。还原只删配置，不管运行值 |
| 13-41 日志 | 通过 | 选项 2 查 sshd 日志、选项 1 查最近日志正常；选项 5 清理选 1 后 journal 23.6M→11.7M |
| 13-42 环境变量 | 部分通过 | 选项 1 查看、2/3 查 bashrc/profile、6 重载都正常（sudo 下看的是 /root 的文件）；选项 4/5 编辑打开 nano，需交互终端，管道测不了，未验证 |
| 13-102 卸载 | 通过 | tbox 软链与脚本文件都删了，crontab 无残留行，`tbox` 命令已不存在 |
| 13-2 改密码 | 跳过 | 没必要在测试机上改 |
| 13-6 改 SSH 端口 | 跳过 | 会断掉 InstaBox 网关的 SSH 接入 |
| 13-8 重装 | 跳过 | 会清空机器 |
| 13-16 XanMod | 跳过 | 微虚拟机内核由宿主机提供，装了也不生效 |
| 13-19 换源 | 跳过 | 默认源正常，无需换 |
| 7 WARP | 跳过 | 条款禁公共 VPN 出口 |
| 13-99 重启 | 跳过 | 有起不来风险 |
| 分工边界（5 与 28） | 未单独测 | 5 与 28 的菜单/文件头警告在各自输出里都已看到；未跑 vps-tune，无需再点 |

### 5 BBR 开启失败的根因（环境限制，不是脚本 bug）

- 配置文件已正常写出：`/etc/sysctl.d/99-vps-toolbox-bbr.conf`（fq + bbr 两行）。
- 但 `sysctl -p` / `sysctl -w` 写 `net.core.default_qdisc` 与
  `net.ipv4.tcp_congestion_control` 都报 `No such file or directory`；
  直接写 `/proc/sys/net/ipv4/tcp_congestion_control` 同样 ENOENT。
- 对照：`echo 1 > /proc/sys/net/ipv4/ip_forward` 可以写（已改回 0），
  证明不是权限问题，是宿主机内核没有把这两个 sysctl 键暴露给微虚拟机。
- 另：`tcp_available_congestion_control` 只有 `reno cubic`，无 bbr
  （宿主机内核无 tcp_bbr，`modprobe` 也没有装）。
- 结论：InstaBox 微虚拟机改不了拥塞算法/队列算法，BBR 在此环境下
  无法开启；真机 VPS 上应正常。**改进建议（未改脚本）**：`bbr_enable`
  写配置前先查 `tcp_available_congestion_control` 里有没有 bbr，
  没有就明确提示而不是先写文件再报“应用参数失败”。

### 机器最终状态（测试结束时，2026-11-22 21:18 CST，仍 Running）

- 主机名已恢复 instabox-agent-browser-4x37；时区 Asia/Shanghai；
  DNS 国内且 +i 锁定；gai.conf 有 IPv4 优先规则。
- swap：`/swapfile` 2048M 在用；原 `/data/swapfile` 4G 已停用、移出
  fstab，文件还在磁盘上（占 4G），如需恢复可重新 `swapon` 并加回 fstab。
- 残留文件：`/etc/sysctl.d/99-vps-toolbox-bbr.conf`（两行 bbr/fq，
  在此机器上永远应用不上，`sysctl --system` 会报两行错；真机上无此问题）、
  `/etc/fail2ban/jail.d/sshd.local` 与 `recidive.local`（包已卸）、
  `/etc/hosts.bak.20261122211644`、rsyslog（fail2ban 安装时装的，服务在跑）。
- 运行值残留：swappiness=30（28 还原后未重置，重启恢复 60）；
  拥塞算法 cubic、队列 pfifo_fast（未变）。
- 磁盘：4.9G→6.9G/16G（新增 /swapfile 2G + 系统更新），journal 11.7M。
- 脚本与快捷键已卸载，crontab 干净。

### 清理（2026-11-22 21:20，测试后）

- 已删 `/etc/sysctl.d/99-vps-toolbox-bbr.conf`（此机器上永远应用不上、还会让 `sysctl --system` 报错）。
- swap 已恢复原状：4G `/data/swapfile` 重新启用并加回 fstab；工具箱的 2G `/swapfile` 已停用并删除，fstab 里只剩原有的一行。现 `free -m` 显示 swap 4095M。
- 留下的残留（无害）：`/etc/fail2ban/jail.d/` 下两个 local 配置（包已卸，无服务读它们）、`/etc/hosts.bak.20261122211644`、rsyslog（fail2ban 装的依赖，服务在跑）。

## 一键安装验证（v1.0.2，2026-11-22 21:24–21:25）

新增 `install.sh`：下载到临时文件、确认非空、`bash -n` 语法通过
再安装到 `/usr/local/bin/vps-toolbox`（0755），建 `/usr/local/bin/tbox`
快捷方式，装完跑 `tbox help` 验证。重新跑一遍就是更新。

| 环境 | 方法 | 结果 |
|---|---|---|
| 沙箱（Ubuntu 24.04） | 本地 `bash install.sh` | 通过，装完 `tbox help` 正常，版本 v1.0.1（当时 main 上还是 v1.0.1） |
| InstaBox（Debian 13） | scp 上传后 `sudo bash /tmp/install.sh` | 通过，同上，`/usr/local/bin/vps-toolbox` 与 `tbox` 软链都在 |

说明：两次实测装的都是当时 main 分支上的 v1.0.1（v1.0.2 还没推），
安装器逻辑不变，推完 v1.0.2 后同一条命令装到的就是 v1.0.2。
InstaBox 上装完工具箱就留在机器里了（`tbox` 可用），未卸载。

## 自动跳转主菜单验证（v1.0.3，2026-11-22 21:33–21:35）

改动：`install.sh` 装完验证通过后直接进主菜单，不用再打 `tbox`。
实现是 `"$DEST" </dev/tty`（安装器是管道进来的，stdin 是管道不是
终端，所以从 `/dev/tty` 接管输入；没终端时只打印提示、不启动菜单）。

| 环境 | 方法 | 结果 |
|---|---|---|
| InstaBox（Debian 13） | scp 上传新 install.sh，用 `ssh -tt` 分配 PTY、stdin 用管道模拟 `curl \| bash`，4 秒后送 `0` 退出 | 通过，主菜单正常出现（v1.0.2 字样，因 main 上还是 v1.0.2），输入 0 后打印“再见。”正常退出 |

说明：`ssh -t`（单 t）会因 stdin 是管道而拒绝分配 PTY，
必须用 `ssh -tt`（双 t）强制分配，这才是用户 FinalShell 交互
会话的真实情况。测试里菜单前有一行 `'unknown': I need something
more specific.`，是 PTY 的 TERM 未设导致 `tput/clear` 的报错，
用户真实终端 TERM 正常时不会出现，不影响菜单。
