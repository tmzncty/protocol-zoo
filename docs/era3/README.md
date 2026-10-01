# 第三纪元：互联网长出基础设施器官（The Internet Grows Organs）

核心问题：一个强调端到端主机通信的网络，如何长出命名、自治、政策路由、中间盒、缓存、交换、分发、隧道与控制平面。

## 展厅

A. Names Become Infrastructure  · DNS、地址与发现
B. Networks Become Autonomous  · BGP、CIDR 与自治系统
C. The Backbone Becomes a System  · IXP、Anycast 与路径观察
D. Middleboxes Enter the Path  · NAT、防火墙、代理与负载均衡
E. Address Scarcity Changes Architecture  · 地址复用与可达性
F. The Internet Learns to Cache and Distribute  · HTTP、缓存与 CDN
G. Tunnels Build Networks Inside Networks  · GRE、VPN、overlay 与 MTU
H. The End-to-End Principle Under Pressure  · TLS、终止点与责任边界

本阶段的专题文档：

- [`HTTP.md`](HTTP.md)：HTTP/0.9、1.0、1.1、2、3 的语义与 framing 演化；
- [`TLS.md`](TLS.md)：TLS 1.2/1.3、认证边界与密钥/证书限制；
- [`TUNNELS.md`](TUNNELS.md)：IP-in-IP、GRE、加密隧道、overlay 与 MTU；
- [`END-TO-END.md`](END-TO-END.md)：端到端论证、中间盒压力与逐项信任边界；
- [`SURVIVAL-MATRIX.md`](SURVIVAL-MATRIX.md)：定性存续比较与明确限制；
- [`VPS-SAFETY.md`](VPS-SAFETY.md)：自有 VPS 的最小暴露与清理边界；
- [`MTU-PMTUD.md`](MTU-PMTUD.md)：M18 本地低 MTU 复现、WAN 观察边界与 black-hole 推论；
- [`TRACEROUTE.md`](TRACEROUTE.md)：M19 TTL/Hop Limit 方法、probe family 与 `*` 的证据含义；
- [`DHCP-INTEGRATION.md`](DHCP-INTEGRATION.md)：M20 DORA 到 TFTP 的本地 packet-evidence 闭环；
- [`TCP-UDP-WAN.md`](TCP-UDP-WAN.md)：M29–M30 transport 契约、受控 WAN 失败与 L4 门槛；
- [`FAILURE-GALLERY.md`](FAILURE-GALLERY.md)：M33 timeout、权限与 application 未闭环的失败证据；
- [`dns-root-anatomy.md`](dns-root-anatomy.md)：现代 DNS 根解剖——13 身份 / 12 运营者 / 2000+ Anycast 实例、root hints 启动锚点与缓存经济学。

每章区分：当时的问题、当时提出的方案、最终占主导的实现、今天仍存活的部分，以及不应倒投回历史的现代解释。没有实验记录的主张不会被写成真实抓包结论。

## 证据等级

`L0` citation；`L1` fixture；`L2` executable local reproduction；`L3` local packet evidence；`L4` controlled real-WAN evidence；`L5` external corroboration。使用 VPS 不自动提高等级。

第三纪元封馆时已经形成多组受控本地 L3 证据：DNS delegation/glue/递归与缓存、HTTP/1.0 与 HTTP/1.1 连接可见性、TLS `ClientHello`/ALPN 与加密后的应用不可见性、GRE 内外层封装、reverse proxy 的两条独立 TCP legs、PMTUD 的 ICMP fragmentation-needed/MTU 1400，以及已知 ground truth 中的 UDP/ICMP traceroute。对应入口见 [`../ERA3-EVIDENCE-ATLAS.md`](../ERA3-EVIDENCE-ATLAS.md)。

这些证据不会被扩张成没有做过的公网结论。公网 BGP announcement、完整 IXP route-server、公网 Anycast 操纵、provider NAT 类型判断、WireGuard 公网隧道、全球 CDN，以及 NAT/firewall/LB/cache 的全部 packet-level 子实验，仍按实际条件保留为历史研究、document reconstruction、bounded observation、`not-run` 或明确 blocker。

## 封馆状态

第三纪元实验事实的封馆锚点为 `736c14b`。该锚点之后允许继续修正文档、中文导览、索引和勘误，但不能在没有新证据与新边界声明的情况下，把后续文字修改解释成第三纪元已经完成新的实验事实。

机器可读封馆状态见 [`../../data/era3/status.json`](../../data/era3/status.json)。机器可读索引另见 [`../../data/era3/protocols.json`](../../data/era3/protocols.json)、[`../../data/era3/survival-matrix.json`](../../data/era3/survival-matrix.json) 与 [`../../data/era3/evidence.json`](../../data/era3/evidence.json)。M18–M33 observation ledger 见 [`../../research/data/era3-observations.md`](../../research/data/era3-observations.md) 与 `.json`；其中 `local`、`wan`、`inference` 是分开的来源标签。
