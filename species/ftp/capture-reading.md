# FTP 逐帧读包：谁敲门，谁搬文件？

同样是服务器把内容交给客户端，数据连接可以由不同一方先“敲门”。下面只解释仓内已有的合成实验抓包，不新开服务，也不把观察到的端口或时序当成所有 FTP 实现的规定。

## 先分清三个文件和两个计数范围

路径均相对仓库根目录；帧号在**各自文件内**从 1 开始，不跨文件累计。

| 归档 | 帧数 | 实际内容 |
| --- | ---: | --- |
| `captures/real-app-netns/telnet.pcapng` | 7 | 原实验的 Telnet 连接，不属于 FTP 会话 |
| `captures/real-app-netns/ftp.pcapng` | 64 | 1–42：被动 RETR；43–64：另一次仅登录/查询能力/退出 |
| `captures/real-app-netns/ftp-active.pcapng` | 36 | 独立的 EPRT/LIST 主动模式记录，控制端口 2122 |

[`real-app.json`](../../captures/real-app-netns/real-app.json) 的 `result.capture` 仍指原来的 `{telnet,ftp}.pcapng`，因此 `result.frames` 是 **7 + 64 = 71**，不是旧值 74。`ftp.passive_frames` 包括第一会话的控制、数据和关闭帧，共 42；其余 22 帧是 login-only，不是 active transfer。独立的 36 帧放在 `ftp_active_supplement`，不混入原计数；三个文件合计才是 107。

## 两种“敲门方式”，同一个内容方向

箭头在“连接”行表示首次 SYN 的方向；“内容”行才表示应用数据方向。

| 观察项 | 被动：`ftp.pcapng` | 主动：`ftp-active.pcapng` |
| --- | --- | --- |
| 控制连接 | client `198.18.0.1:40734` → server `198.18.0.2:2121`（帧 1） | client `198.18.0.1:33594` → server `198.18.0.2:2122`（帧 1） |
| 协商 | `EPSV`（22），`229 ... (|||19000|)`（23） | `EPRT \|1\|198.18.0.1\|47135\|`（18） |
| 数据连接 | **client** `198.18.0.1:40810` → server `198.18.0.2:19000`（SYN 24） | **server** `198.18.0.2:48707` → client `198.18.0.1:47135`（SYN 19） |
| 内容 | `RETR` 下载文件，server → client（数据帧 29） | `LIST` 返回目录列表，server → client（数据帧 25） |

`EPSV` 的 229 回复只给出监听端口，地址和地址族沿用控制连接；不能从括号里“读出”一个并不存在的 IP。`EPRT` 中 `1` 表示 IPv4，接下来的地址和端口是服务器要连接的客户端端点。依据见 [RFC 2428 §2](https://www.rfc-editor.org/rfc/rfc2428.html#section-2) 与 [§3](https://www.rfc-editor.org/rfc/rfc2428.html#section-3)。

不要把“主动模式”背成“源端口必为 20”：本归档明确是 48707。[RFC 959 §3.2](https://www.rfc-editor.org/rfc/rfc959.html#section-3.2) 描述默认服务器数据端口为控制端口 L−1；那是规范中的默认值，并不是这份抓包的实测值。传输请求决定数据发送者，主动/被动决定连接建立方式，两者不是一回事（另见 [§3.3](https://www.rfc-editor.org/rfc/rfc959.html#section-3.3)）。

## 按帧追一遍

被动 RETR：22 发 `EPSV` → 23 返回 19000 → 24–26 数据连接三次握手 → 27 发 `RETR` → 28 回复 `125` → 29 服务器发送 25 字节 TCP payload → 32 控制连接回复 `226`。这 25 字节与 [`ftp-passive.log`](../../captures/real-app-netns/ftp-passive.log) 的接收计数相符；不是整个 pcap 文件大小。

主动 LIST：18 发 `EPRT` → 19–21 服务器主动建立数据连接 → 22 回复 `200` → 23 发 `LIST` → 24 回复 `125` → 25 服务器发送目录列表 → 30 回复 `226`。这里握手甚至在 LIST 前完成；这是该记录的时序，不能推广为所有实现必须如此。

再看 `ftp.pcapng` 的 43–64：客户端控制端口变为 40750，只有 `USER/PASS/SYST/FEAT/QUIT` 和回复；没有 `EPRT/PORT/EPSV/PASV/LIST/RETR`，也没有第二条数据连接。[`ftp-active.log`](../../captures/real-app-netns/ftp-active.log) 中的 `?Invalid command.` 是客户端报错，没有对应的 FTP `LIST` 请求帧。这个文件名保留历史，但不能替独立 `ftp-active.pcapng` 作成功 transcript。这里的关联依据是脚本的第二次调用和相符的命令/回复序列；transcript 没有时间戳或流 ID，不能据此认证同一次采集的完整来源链。

## 只读复核，不需要 root 或联网

在仓库根目录，有 Wireshark/tshark 时可直接读现有文件。下面只选择连接头、命令名和回复码，不输出 `USER/PASS` 参数。

```sh
# 首次 SYN：看清谁发起连接（输出不含凭据）。
tshark -r captures/real-app-netns/ftp.pcapng \
  -Y 'tcp.flags.syn == 1 && tcp.flags.ack == 0' \
  -T fields -e frame.number -e ip.src -e tcp.srcport -e ip.dst -e tcp.dstport
tshark -r captures/real-app-netns/ftp-active.pcapng \
  -Y 'tcp.flags.syn == 1 && tcp.flags.ack == 0' \
  -T fields -e frame.number -e ip.src -e tcp.srcport -e ip.dst -e tcp.dstport

# 自定义控制端口显式 Decode As FTP；帧号保留原始文件编号。
tshark -r captures/real-app-netns/ftp.pcapng -d tcp.port==2121,ftp \
  -T fields -e frame.number -e ftp.request.command -e ftp.response.code
tshark -r captures/real-app-netns/ftp-active.pcapng -d tcp.port==2122,ftp \
  -T fields -e frame.number -e ftp.request.command -e ftp.response.code

# Node 内置库即可进行固定归档的一致性检查和负例回归。
node scripts/validate-ftp-evidence.js
node --test tests/ftp-evidence.test.js
```

本次逐帧校对使用成熟解码器 Scapy 2.6.1 离线读取这三份 pcapng，再与原有 TSV 对照；上述 tshark 命令是等价的读法示例，不是本次执行过 tshark 的声明。Node 检查器绑定经复核的 pcap SHA-256、TSV、帧数、端点和会话归属；它**不是新的抓包解码器**，也不验证任意新抓包的协议正确性。更换归档须重新解码和复核，不能只改预期哈希让检查变绿。

当前工作流和 `make check` **没有运行这项 FTP 检查**，请单独执行上述两个 Node 命令；其他 Era 的绿色 CI 不能替它背书。

## 复现边界与安全

[`scripts/real-app-capture.sh`](../../scripts/real-app-capture.sh) 只生成 Telnet 和控制端口 2121 的 FTP 抓包/TSV。脚本给客户端的 `list` 在现有 transcript 中报错；第一次调用另有成功 `get`，第二次没有成功传输。它也不生成控制端口 2122 的独立 active pcap/TSV，且不重写 `real-app.json`。独立记录的生成命令、完整环境、捕获过滤器和匹配 transcript 未记录，不能把原实验的元数据直接套用过去。

因此，本页完成的是**已有归档的解释与纠错**，不是新实验或主动模式复现闭环。旧二进制、TSV 和 transcript 均保留；重新生成时应另用输出目录，避免覆盖待比较的证据。本实验地址属于 198.18.0.0/15 基准测试地址段，不是 TEST-NET 文档地址段。

FTP 明文传送命令和内容，即使 transcript 已脱敏也不要据此认为原始包不含合成口令。不要把真实账号用于实验；不要对公网开放 FTP，也不要为了抓包修改宿主机防火墙。需要重现实验时遵守 [实验安全边界](../../docs/LAB-SAFETY.md)；模式对照不是生产部署建议，另参见 [RFC 2428 §4](https://www.rfc-editor.org/rfc/rfc2428.html#section-4)。
