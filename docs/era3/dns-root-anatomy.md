# DNS 根：13 个身份、约 2000 个实例

> 「全球只有 13 台 DNS 根服务器」这个流行说法现在是错的，而且错得有信息量。准确的说法是：**13 个根服务器身份（A–M）**，由 **12 个独立运营机构**运营（Verisign 同时运营 A 和 J），背后是 **2000+ 个 Anycast 实例**（Root Server Technical Operations Association 2026-08 数据：2004 个）。
>
> 本条与 [`dns.md`](dns.md)（DNS 总展品）和 `tmzncty/computer-network-archaeology` 的 [`hosts-txt-to-dns.md`](https://github.com/tmzncty/computer-network-archaeology/blob/main/docs/lineage/hosts-txt-to-dns.md)（HOSTS.TXT→DNS 迁移史）互补：那边讲「为什么会有 DNS」，这里讲「今天的根到底是什么」。

## 身份 ≠ 机器

`A.ROOT-SERVERS.NET` 到 `M.ROOT-SERVERS.NET` 是 13 个**逻辑身份**（标识 + 服务承诺），不是一个机房里的 13 台机器。每个身份靠 Anycast 由全球大量实例同时应答：

```text
逻辑层：A B C D E F G H I J K L M      （13 身份 / 12 运营者）

物理层：A → ● ● ● ● ● ● ...
        B → ● ● ● ...
        ...
        M → ● ● ● ● ...
        合计约 2000 个运行实例
```

BGP 把查询导向拓扑上较近的实例；本地实例故障、路由撤销后流量自动转向其他实例。`dig @198.41.0.4 .` 命中的是哪个物理节点，提问者并不知道。

13 这个数字本身来自历史约束：DNS 响应必须装进 512 字节 UDP 包，根记录 + 13 组 IPv4 地址是当时塞得下的上限。IPv6 后出现 13 个身份名的说法仍延续（AAAA 记录以另外方式携带）。

## 根区里到底有什么

比想象的少：**有哪些顶级域，以及这些 TLD 的权威服务器在哪**。概念上就是：

```text
com.  → a.gtld-servers.net, b.gtld-servers.net, ...
org.  → ...
cn.   → ...
```

不是「全世界域名 → IP」的数据库。根是委派链条的起点，站在树根说「你想找 .com？往这边走」。

## root hints：DNS 的启动锚点

递归解析器第一次工作时并不知道任何东西，唯一的先验是内置的 **root hints** 文件（IANA 维护，列 13 个身份的地址）。由此引出一个漂亮的递归问题的解法：

```text
我要查域名 → 要找 DNS → DNS 自己也是域名 → ……
```

DNS 的答案：出生时只写死「根服务器地址」这一小段信任锚，其余全部通过 referral 逐级发现。结构与系统启动链同构：

```text
BIOS/UEFI → Bootloader → Kernel → 整个系统
root hints → Root → TLD → Zone → 整个命名空间
```

## 根全挂了会怎样

不是「瞬间没网」。递归缓存里的 TLD NS 与权威 NS 记录在 TTL 内继续可用；影响随缓存过期逐级显现。而 13 个身份、12 个运营者、约 2000 个 Anycast 实例要同时失效是极难事件。

## 缓存经济学（为什么感觉不到 DNS 延迟）

- 浏览器缓存 → OS 缓存 → 本地递归缓存，任一命中即止；
- 递归缓存连**中间路径**（.com NS、example.com NS）一起缓存，越用跳数越短；
- 热门域名的热缓存几乎常驻：**域名越热门，平均解析延迟越低**——与直觉相反；
- 浏览器 DNS prefetch、递归服务器对快过期热记录的后台 prefetch，把查询藏进用户等待之前。

## 来源

- IANA root hints 文件与根服务器身份列表；
- Root Server Technical Operations Association 实例统计（2026-08：2004 个）；
- ICANN 对根实例/Anycast 的公开定义；
- 整理自 2026-09-20 会话「DNS扩散原理解答」（结构重写，非逐字）。
