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
