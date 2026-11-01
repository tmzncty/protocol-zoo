# Protocol species: `tus`

## 展签

- **历史用途**：把「大文件上传中断了要重传整个文件」这件事，变成「从断点接着传」。
- **定义层次**：application（HTTP 之上的可恢复上传约定，不是传输层协议）。
- **出生语境**：2016 年前后，浏览器端大文件上传（视频、数据集）在移动网络与代理环境下频繁中断；当时的通用做法是分片 + 客户端自己记账，各家格式不兼容。
- **当前状态**：alive/narrow —— 主要活在对象存储网关、Uppy 这类前端上传框架、以及自建上传服务里。
- **证据等级 (`evidence_level`)**：`static`（基于公开规范的文档重建；本仓**尚未**做自己的抓包或互通实验）。
- **现代替代/存续原因**：S3 multipart upload 覆盖「直传对象存储」场景；tus 存续是因为它**不绑定后端**，一个实现可以挂到任意存储上。

## 机制（规范层，v1.0.0 核心）

```text
POST   /files            → 创建资源，响应 Location: <upload-url>（creation 扩展）
HEAD   <upload-url>      → 返回 Upload-Offset / Upload-Length（断点信息）
PATCH  <upload-url>      → Content-Type: application/offset+octet-stream
                           Upload-Offset: <当前偏移>
                           响应 204 + 新的 Upload-Offset
```

三个关键语义：

1. **偏移是唯一的进度真值**。客户端不信自己的内存计数，每次续传前先 `HEAD` 问服务器。
2. **偏移不匹配必须拒绝**（409），而不是「尽力而为」。这保证并发/重放不会写花数据。
3. **长度可未知**（`Upload-Defer-Length`），适合边生成边上传的流。

扩展：`termination`（DELETE 取消）、`concatenation`（分片并行上传后拼接）、`checksum`（分片校验）。

## 隐含假设

- **线缆/拓扑 (`topology_assumption`)**：任意 HTTP 路径，中间允许代理；不假设长连接。
- **寻址 (`addressing_model`)**：每个上传资源一个 URL，服务端负责持久化该 URL 与状态。
- **发现 (`discovery_model`)**：无发现机制，客户端由应用直接告知端点。
- **信任 (`trust_model`)**：**协议本身没有身份**。认证/授权完全交给外层（cookie、token、签名 URL）。
- **状态 (`state_model`)**：服务端必须持久保存偏移；这是它与「纯转发」的根本差别。
- **失败 (`failure_model`)**：以「偏移不一致 → 409 → 客户端重新 HEAD」为恢复路径。
- **带宽/算力 (`bandwidth_assumption`)**：为大文件优化；小文件用它会多出 HEAD/PATCH 的往返。
- **中间盒 (`middlebox_assumption`)**：依赖 HTTP 语义可穿透；但**请求体大小上限**与**超时**是常见杀手。
- **死亡压力 (`death_pressure`)**：对象存储的原生 multipart 更省事（不必自建状态服务）。
- **幸存后代 (`surviving_descendants`)**：分片上传 + 偏移协商这套思路被广泛吸收（S3 multipart、各种「可续传下载」实现）。

## 既有实现

- 服务端：`tusd`（Go，官方参考实现）；若干语言移植。
- 客户端：`tus-js-client`（纯协议库，无 UI）；Uppy 内置 tus 上传插件（UI 全家桶 + tus 作为上传方式之一）。

**不要为本展品重写生产实现**——用 `tusd` + `tus-js-client` 即可完成一次可复现实验。

## 实验入口（尚未执行）

```text
1) 本地起 tusd（只绑 127.0.0.1）
2) 用 curl 走一遍 POST → HEAD → PATCH(前 N 字节) → 断开 → HEAD → PATCH(续传)
3) 观察：偏移不匹配时的 409；Upload-Length 缺失时的行为
4) 抓包只看 HTTP 头，不落文件体
```

## 安全

- 无认证：**任何能访问 upload-url 的人都能续写/覆盖**；生产必须叠 token 或签名 URL。
- 分片拼接扩展要防「拼接顺序/归属」被篡改。
- 存储侧要防路径穿越与配额耗尽——上传长度可声明，实际写入要按配额截断。

## 资料

- tus.io 的协议规范（v1.0.0）与扩展文档；`tusd` 仓库 README。
- 本展品的判断边界：**没有**本仓自己的抓包，也没有跨实现互通记录；凡涉及具体实现行为的描述，落地前需按版本复核。
