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

## 框线风格验证（v1.0.4，2026-11-22 21:45–21:55）

改动：主菜单、系统工具子菜单、BBR 页画整框，其余各页标题改成小框
（`box_title`）；颜色定义改成 `$'\033...'` 存真实 ESC 字节，
`dwidth` 用 `LC_ALL=C.UTF-8 wc -m` 量字符数（POSIX locale 下
`wc -m` 按字节数、中文会被算宽、框撑大）；BBR 已是 bbr+fq 时
直接提示已开启、不再问（避免在 vps-tune 调优过的机器上误点重写）。

| 检查项 | 方法 | 结果 |
|---|---|---|
| 主菜单框线 | 沙箱 `printf '0\n' \| bash vps-toolbox.sh`，逐行量显示宽 | 通过，每行 37 列，边框与内容严丝合缝 |
| 系统工具子菜单框线 | 沙箱 `printf '13\n0\n0\n' \| bash vps-toolbox.sh` | 通过，双栏排版保留，框线对齐 |
| BBR 不支持内核 | 沙箱实测（内核只有 reno cubic） | 通过，“当前内核不支持 BBR”整框显示，54 列对齐 |
| BBR 已开启 | 沙箱 mock sysctl（MOCK_CC=bbr MOCK_QDISC=fq） | 通过，显示“已开启，无需重复开启。”，不问确认、只读不写 |
| BBR 开启流程 | 沙箱 mock sysctl（MOCK_CC=cubic），输 n 取消 | 通过，开启页整框显示（62 列对齐），取消后不写配置 |
| 系统信息标题 | 沙箱 `bash vps-toolbox.sh info` | 通过，标题小框正常，正文保持原样 |
| 静态检查 | `bash -n` + shellcheck（-S warning） | 通过，0 警告（中途修掉 1 个 SC2178：settings_logs 里的 `lines` 行数变量改名 `count`，避免和 box 用的 `lines` 数组撞名） |

说明：框内容行里不要用 3 字节的非中文符号（→ ⚠ ✓ 等），会算宽
1 列、框对不齐；`→` 只出现在普通 echo/warn/err 输出里（不进框），
不影响对齐。v1.0.5 已把 `settings_logs` / `settings_env` 里的
`===` 小节分隔线也统一成 24 横线，全文件分隔线只剩一种。

## 13 号全面审查与修复（v1.0.5，2026-11-22 22:05–22:30）

起因：用户把我们的 3、5、7、13 号菜单和上游（kejilion / Joey
BBR / fscarmen WARP）逐张对比，觉得 13 号功能最多，要求全面检查，
并强调排版必须规整。审查覆盖 13 号 20 项 + helper，全文 2137 行。

审查结论：严重 0 / 高 0 / 中 6 / 低 55（功能 45 + 版式 10）。
未发现命令注入、明文密码落盘、rm -rf、--no-check-certificate、
未确认的破坏性操作。6 个中问题与 10 个版式问题全部修完，
另修 1 个审查中发现的旧问题（环境变量页 USER 未定义会崩）。

| 编号 | 问题 | 修复 | 验证 |
|---|---|---|---|
| U1 | 卸载清 crontab：`crontab -l` 失败会把空内容喂给 `crontab -`，清空整份 crontab | mktemp 落盘 + 判退出码；rc=0 才过滤重装；“no crontab”正常跳过；其他失败报错且绝不动 crontab | mock 三场景全过（正常过滤重装 / 无 crontab 跳过 / 读取失败报错且不调 crontab -） |
| P1 | 改 SSH 端口：`sshd -t` 失败不回滚，sshd_config 留在坏状态 | 备份路径存变量；校验失败先 cp 恢复再报错 | mock sshd 返回 1，提示“已恢复备份”，测后文件哈希与测前一致 |
| W1 | swap 自定义大小没上限 | 加 16384M 上限 + 根分区可用空间检查 | 99999 被拒（“最大 16384M”），128 通过 |
| W2 | swap 失败路径丢 swap（先停旧再建新） | 先建新（/swapfile.new + mkswap）后停旧；旧文件备份成 /swapfile.old；失败移回并恢复 | mock 失败路径无残留、fstab 未动；成功路径 128M 权限 600、fstab 只加一行；fstab 的 sed 另验：swap 分区行、/swapfile2 都保留 |
| F2 | fail2ban 基础参数不校验，写完只 reload 不跑 -t | 校验 bantime/findtime（`^[0-9]+[smhdw]?$`）、maxretry 1–100；写前备份，写完跑 `fail2ban-client -t`，失败恢复备份；reload 失败改报警告 | 正则实测：接受 10m/600/1h/1d/1w，拒绝 10x/abc/“10 m”；maxretry 接受 1/100，拒绝 0/101 |
| S1 | 快捷键名能遮蔽系统命令（ls/cat/rm） | `command -v` 查到同名就拒绝（除非本来就指向本脚本）；另拒 `.`、`..`、首字符 `-`/`.` | 假命令 mycmd 被拒且未建软链；`.` 被拒；合法名正常建链（测后已删） |
| 版式 | 4 处裸标题（BBRv3 已装分支、内核参数优化、环境变量管理、命令高级用法） | 全部改 box_title | 逐页确认 |
| 版式 | 分隔线 6 种长度（24/38/39/40/47/48）+ `-`/`=` 混用 | 全文件统一成 24 横线；带标题的 `======` 改成“24 横线 + 标题独占一行 + 24 横线” | grep 验证：分隔线只剩 24 横线 48 处，`=` 线 0 条 |
| 版式 | 13 号菜单双栏差 1 列（右栏 33/34 混用） | 左栏用 `max_width` 算最宽项 + 2 列间距，再用 `pad_to` 补齐 | 沙箱渲染：9 行右栏全部从第 35 列起，外框 66 列整齐 |
| 版式 | 日志页一屏两个标题框显碎、跟踪后无 pause、标题框后红字警告贴得紧 | 日志页合并成一个标题框；跟踪结束加 pause；DD 与 BBRv3 的标题框后加空行 | 逐页确认；42-1 页 8 条分隔线全是 24 横线 |
| 旧问题 | 环境变量页 `echo "当前用户：$USER"`，`set -u` 下 USER 未定义会崩（cron/su 环境） | 改成 `${USER:-未知}` | 沙箱复现过崩溃，改后正常 |

静态检查：`bash -n` + shellcheck（-S warning）0 警告。
其余 45 个低问题未修，分批处理，不堵这一版。

## 对比上游后补齐的功能（v1.0.6，2026-11-22 22:33–22:40）

起因：用户把我们的 3、5、7、13 号菜单和上游（kejilion / Joey
BBR / fscarmen WARP）逐张对比，确认筛过的功能都要补齐（筛掉的
DD 系统与 13 号子项不加回来）。三处都是给已筛过的功能补信息，
不加新功能、不扩大范围。

| 位置 | 改动 | 验证 |
|---|---|---|
| 3 号清理 | 跑完加“清理小结”：磁盘可用（/）清理前 → 清理后、释放约多少 MB；journal 占用清理前 → 清理后。清理前后分别取 `df -m /` 可用 MB 与 `journalctl --disk-usage` 第 7 列；释放量为负时改报“清理期间有其他写入，净减少 X MB” | 沙箱实测 df/journal 取值命令（可用 7443 MB、journal 8.0M）；小结算术用模拟值验过（7000 → 7325，释放约 325 MB；journal 325.6M → 12.0M） |
| 5 号 BBR | 加状态块：内核版本、BBR 版本、拥塞算法、队列算法。新增 `bbr_version()`，判定与 vps-tune 同一套：内核名含 xanmod/bbrv3 → v3，`modinfo tcp_bbr` version 字段 → v3/v1，兜底 v1。四行标签改短（拥塞算法 / 队列算法 / 内核版本 / BBR 版本）使值列对齐；已开启、不支持、待开启三页与开启后的回显都带状态 | 沙箱 mock：bbr+fq 已开启页 4 行对齐（48 列），modinfo version 1.0 → v1；mock 内核 7.3.5-xanmod1 → v3 |
| 7 号 WARP | 确认前加一句“进去后先选语言：选 2 是简体中文（默认是英文）。” | 沙箱输 n 取消，提示行正常出现 |

静态检查：`bash -n` + shellcheck（-S warning）0 警告。
安全复审：三处改动只读系统状态（df、journalctl、sysctl、uname、
modinfo），无新注入面、无 eval、无新执行路径。

## 13 号剩余 45 个低问题全修完（v1.0.7，2026-11-22 23:10–23:30）

起因：v1.0.5 审计的 45 个功能类低问题当时分批处理、未修；用户
2026-11-22 23:10 点名先修这 45 个。原审计逐条清单未落文件，
本次是重审 13 号子菜单 + 共用 helper 后重新列出的 45 项。

| 批 | 内容 | 关键项 |
|---|---|---|
| 正确性 / fail-open（10 项） | check_disk_space 读不到时 fail-open → 校验数字、失败即拒；add_swap `swapoff -a` 会停 swap 分区 → 只停 /swapfile；kernel_optimize_restore 删配置 ≠ 恢复运行时值 → 改文案并问是否重启；改 SSH 端口连 sshd_config.d 里的旧 Port 一起处理、重启失败恢复备份；DD 脚本按退出码报错、不再问重启；f2b 卸载两路都失败不再报 ok；日志选项 5 选错不再报“清理完成”；f2b 安装验 rsyslog 是否 active；bbr_enable_nopause 验写盘 | 1、20、37、9、10、16、33、40、32、24 |
| 校验与反馈（10 项） | passwd 按退出码报成败；chattr +i 验结果（两处）；fail2ban 手动改配置后先 -t 再 reload；改 .bashrc/.profile 后 bash -n 检查；bantime/findtime 为 0 拒绝；Banned IP 全显示；跳过的 sysctl 参数列名；时区/主机名加非 systemd 兜底；swap 预设档也先查磁盘空间 | 8、13、36、43、34、35、38、23、29、21 |
| 稳健性与清理（25 项） | 6 处下载加超时（curl --max-time 60 / wget --timeout=60）；卸载扫描全部指向本脚本的快捷键；四处时间戳备份新增 prune_backups、只留最新 3 份；系统信息流量统计改算全部非 lo 网卡；日志查服务名先校验字符集 + systemctl show 判存在；换源后 apt-get update 验证；DNS 改完 getent 解析测试；卸载 XanMod 前确认有兜底内核；apt update 失败拦截/警告；bbr3 已安装分支分“运行中内核 / 已安装 XanMod”两行；hosts 替换全换；gai.conf 校验值是 100；快捷键建完验证；check_apt_free 加 fuser 查锁；get_mem_mb 读不到出 0；dwidth 回退；日志行数非法先 warn；env source 失败 warn；内核备份时间戳加 PID；端口输出改 ss -tulnp；swap 警告文案改准；DD 删安装器临时文件；resolv.conf 换前备份；删 6 个 Mint 死代码代号 | 2、22、45、24、42、31、15、25、26、27、28、30、18、7、3、4、5、41、44、39、19、40、17、14、6 |

改法与原清单不同的 8 处（均有原因，见实现记录）：SSH 恢复时 .d
备份一起恢复；时区校验改读 /etc/localtime 软链（`date +%Z` 只给
缩写、永远对不上区域名，会误报）；bbr3 命令半角括号修正；hosts
全换改按行寻址全局替换（只加 g 换不掉）；bbr_enable_nopause 的
sysctl 行末加 `|| true`；Banned IP 的 sed 恒返回 0；bash -n 与
source 前加 `[ -f ]` 保护；快捷键验证用 readlink 解析后比对。

验证：`bash -n` 通过、shellcheck（-S warning）0 警告；抽查实测
prune_backups（5 份留最新 3 份）、check_disk_space 在 df 失败时
err 并 return 1、f2b 零时长拒绝、gai.conf 值 50 识别并修正为
100、主菜单冒烟正常；时区 /etc/localtime 软链校验实测通过。

**订正（2026-11-22 23:32，主菜单审计时发现）**：上表“稳健性与清理”
里写的“系统信息流量统计改算全部非 lo 网卡”实际没改上——v1.0.7
文件里仍是旧的 eth/ens/enp/eno 白名单。抽查只验了几项，漏了这
一处。已在 v1.0.8 补修（见下节），以后每批修完逐项 grep 核对。

## 主菜单 1/2/3/5/7 + install.sh 全面审查与修复（v1.0.8，2026-11-22 23:32–23:41）

起因：13 号审计结项后，主菜单 1/2/3/5/7 与 install.sh 还没审过；
用户 2026-11-22 23:32 点名两个一起审，审完点名中 3 + 低 16 全修。
审计结论：严重 0 / 高 0 / 中 3 / 低 16，另有 2 项已知接受的风险
（WARP 与 install.sh 下载的第三方脚本无哈希校验）不修。

| 级别 | 内容 |
|---|---|
| 中 1 | 1 号流量统计网卡白名单：只算 eth/ens/enp/eno，wlan/wg/tailscale 流量不算 → 改成 `NR>2 && $1 !~ /^lo:/` 算全部非 lo 网卡。**这是 v1.0.7 漏修的一项**（见上节订正），本版补上，旧白名单 grep 已 0 处 |
| 中 2 | 3 号清理 apt 三命令（autoremove/clean）失败不报、最后照样“清理完成” → 加 apt_ok 标记，失败 warn，末尾按 apt_ok 决定 ok 还是 err；多余的 autoclean 一并删掉（clean 已清全部缓存） |
| 中 3 | 5 号 BBR 的 ok 打早了：`sysctl -p` 成功就 ok，再回读 → 改成先回读 new_cc，是 bbr 才 ok，否则 err“拥塞算法仍是 X，BBR 未生效”并 return 1 |
| 低 | install.sh 下载加超时（curl --max-time 60 / wget --timeout=60）；install.sh 装前验系统（只收 Debian/Ubuntu）；install.sh 建 tbox 前检查遮蔽（已存在且指向别处时拒绝）；1 号 CPU 占用除零（t==t1 时输出 0）、删装饰 `sleep 1`、os_info cut 改 `-f2-`、负载改读 /proc/loadavg；2 号提示被 hold 的包（apt-mark showhold）、更新完提示可用 3 号清理旧内核；5 号写配置前备份旧 conf（时间戳+PID，prune_backups 只留最新 3 份）、mkdir/写文件/`[ -s ]` 三处显式检查、cc 已是 bbr 但 qdisc 不是 fq 时红色提醒可能是 vps-tune 调过的；7 号 mktemp 后设 EXIT trap，中断也清理临时文件（5 处 return 前各加 `trap - EXIT`）；新增 `version` 子命令（`tbox version`）；子命令多余参数 warn 提示 |

验证：`bash -n` 两文件通过、shellcheck（-S warning）0 警告；
19 项逐项 grep 核对全部在位（不再只抽查）；沙箱实测 `tbox version`
输出 `vps-toolbox 1.0.8`（升版后）、`version foo bar` 先 warn 多余
参数再输出版本、`tbox info` 正常（CPU 9%、负载 0.14 0.31 0.45、
流量 45.97M/2.80M）。install.sh 的新检查（OS、tbox 遮蔽）只做了
代码核对，未在真机跑完整安装；3 号 apt 失败分支、5 号 BBR 回读
失败分支未在沙箱触发过（需真机或 mock）。

## 102 卸载移到主菜单（v1.0.9，2026-11-22 23:52–23:55）

用户在 rn-sjc 的 FinalShell 截图里问：卸载能不能从子菜单移到主
菜单。改动：主菜单加 `102. 卸载脚本`（编号不变），子菜单删掉 102
那行（左列 + 右列单行 + case 分支）；help 页主菜单区加 102、子菜
单区去掉 102，并补上漏列的 `tbox version`；README 的主菜单清单、
子菜单清单、功能说明、子命令清单同步改；卸载函数本身一字未动
（已审过，确认流程不变）；函数头注释由 `13-102` 改成 `102`。
另顺手把 README 里 3 号清理说明中已删的 autoclean 去掉。
TESTING.md 里 v1.0.2 时代的“13-102 卸载”历史记录不动（当时确实
在子菜单），只在这里说明迁移。

验证：`bash -n` 通过、shellcheck（-S warning）0 警告；沙箱实测
主菜单出现 102 行、子菜单不再有 102、`tbox version` 出 1.0.9、
`tbox help` 主菜单区有 102 且子命令区有 version。卸载本身未在沙
箱执行（会删脚本，只做代码核对）。

## 自更新快捷键（v1.0.10，2026-11-22 23:54–23:58）

用户要一个更新快捷键，不用每次手打一键安装命令。做法：新增
`self_update`（主菜单 103 更新工具箱 + 子命令 `tbox self-update`），
复用 install.sh——下载 install.sh 到临时文件（curl --max-time 60 /
wget --timeout=60），验非空 + `bash -n`，再执行；装完 install.sh
会直接进新版主菜单，self_update 随后 `exit`，不回旧菜单，避免嵌
套。临时文件用 EXIT trap 清理（5 处 return 前 `trap - EXIT`，与
warp_manage 同一套做法）；更新前要确认；装完显示当前版本号。
help 页子命令区与主菜单区、README 的子命令清单/菜单清单/功能说
明/更新记录同步改。

验证：`bash -n` 通过、shellcheck（-S warning）0 警告；沙箱实测
主菜单出现 103 行、`tbox help` 有 self-update 与 103、`tbox version`
出 1.0.10；自更新取消路径实测正常（输 n 即取消，未下载）。
端到端自更新在沙箱实测跑通过（setsid、无控制终端）：下载
install.sh、执行、装到 /usr/local/bin、tbox help 验证通过；
但装到的是 v1.0.9——刚推完 v1.0.10，raw.githubusercontent.com
缓存（约 5 分钟）还没到，与手动一键命令同一行为，等缓存过后
再跑就是 1.0.10。实测还抓到 install.sh 一处健壮性问题：`[ -e
/dev/tty ]` 只判存在，无控制终端时打不开，`set -e` 下会让安装
报失败（其实已装好）；已修成菜单启动失败只打印提示、不算安装
失败（见 install.sh 注释），属 v1.0.10 的一部分。
