# FTP 展品

署名：**祀（岁家老十三）**。

规范：RFC 959；扩展地址/被动模式：RFC 2428。成熟实现优先使用 `pyftpdlib`、vsftpd 或 GNU Inetutils ftpd，不重写 daemon。

## 两条连接

控制连接通常由 client→server:21 建立，命令/回复使用 ASCII 行；LIST/RETR 另开 data connection。Active 模式用 `PORT/EPRT` 告知服务器回连客户端；passive 模式用 `PASV/EPSV` 让服务器监听临时端口并由客户端连接。NAT/防火墙通常使 passive 更容易部署，但仍需正确开放 server data range。

## 实验记录

`scripts/real-app-capture.sh` 使用 `pyftpdlib 1.5.9` 在 `pz-server` 的 `198.18.0.2:2121` 启动成熟 FTP 服务。归档 `captures/real-app-netns/ftp.pcapng` 共 64 帧：1–42 是成功的 EPSV/RETR 会话，43–64 是另一次仅登录、查询能力后退出的会话。后者没有主动模式数据连接；名为 `ftp-active.log` 的 transcript 记录了 `?Invalid command.`，不能当作成功主动传输的证据。实验使用合成账号和文件，不连接公网。

## Active mode 真实记录

独立 active-mode capture 见 `captures/real-app-netns/ftp-active.pcapng` 和 `ftp-active.frames.tsv`：36 帧，控制端口为 2122。`EPRT`（frame 18）指定客户端监听端口 47135；server 发出的 data SYN（frame 19）实际来自 **48707，而不是 20**，随后可见 `LIST`（frame 23）和 `226`（frame 30）。当前脚本不生成这份独立抓包，其完整生成命令、环境和对应 transcript 尚缺记录，不能宣称已形成复现闭环。

从 [逐帧读包：谁敲门，谁搬文件？](capture-reading.md) 对照两份归档：主动/被动区分的是**谁发起数据连接**，不是文件必须往相反方向走。页面包含四元组、帧号、RFC 定位及只读检查命令。

## 安全

FTP 控制和数据默认明文；TLS 扩展（FTPS）与 SFTP 不是同一协议。生产环境优先 SFTP/HTTPS 或明确配置 TLS。
