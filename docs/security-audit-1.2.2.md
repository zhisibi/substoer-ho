# 咪咪SubStore（substoer-ho）全量安全审查报告（只读审计）

- 审计对象：`~/workspace/substoer-ho`，HEAD `205656b`（1.2.2，rename to 咪咪SubStore）
- 审计日期：2026-10-30
- 审计方式：静态代码审查，只读，未改动任何源码（本报告文件除外，未提交 git）
- 范围：`core/ssc/*.go`（server/engine/update/polyfill/yaml/api）、`core/main.go` + `core/napi.c`、entry ArkTS（StoreView / SsUpdate / FileUtil / Log / Prefs / Server / Store / LogPage / ManagePage）、`entry/src/main/module.json5`、`.github/workflows/*.yml` 及 `core/substore/prepare.sh`、`scripts/fetch-core.sh`
- 严重度：高 = 可直接导致订阅/节点凭据泄露、任意代码或管理面失控；中 = 需一定前提但可造成泄露/劫持/拒绝服务；低 = 纵深防御、健壮性或维护性问题

---

## 结论摘要

| 级别 | 数量 | 条目 |
|---|---|---|
| 高 | 4 | H1 LAN 下载无鉴权可枚举；H2 更新信任根无签名（镜像可协同篡改）；H3 goja 脚本与后端同 VM 无隔离无中断；H4 loopback 被等同于完全可信（同机任意 App 可调全量 API） |
| 中 | 7 | M1 LAN 明文 HTTP 传订阅；M2 日志泄漏订阅 token；M3 `$Plugins.Requests` 无 SSRF 边界；M4 WebView 白名单放行 data:/javascript: 且桥注入所有页面；M5 CI 供应链（写令牌暴露给上游依赖安装）；M6 前端更新启用时不复验哈希；M7 文件名路径穿越边角（上传/下载命名不一致） |
| 低 | 7 | L1 polyfill 切片越界 panic；L2 YAML 别名展开 DoS 回退；L3 napi.c 健壮性；L4 `allowLAN` 死字段；L5 无限流与大超时资源占用；L6 敏感数据明文落盘与「清除数据」不删已下载代码；L7 版本号不一致与发布校验和自产自验 |

上架前必须处理（建议）：H1、H2、H3 至少做缓解与显著提示；M2、M4。H4 与 M1 是 Sub-Store 类应用的固有形态，可通过默认关闭 LAN、显著警示、加可选访问令牌来降级。

---

## 专项核查（任务指定 5 问）

### 1) LAN 模式下 /download、/share 是否真无鉴权且可被枚举？——是，确认

- `core/ssc/server.go:314-322`

```go
func isBackendPath(p string) bool {
	return p == "/api" || strings.HasPrefix(p, "/api/") || strings.HasPrefix(p, "/download/") || strings.HasPrefix(p, "/share/")
}
func isPublicPath(p string) bool {
	return strings.HasPrefix(p, "/download/") || strings.HasPrefix(p, "/share/")
}
```

- `core/ssc/server.go:367-371`（非本机请求的唯一闸门）

```go
if !local && !lanUI && !isPublicPath(p) {
	http.Error(cw, "403 forbidden: only subscription links (/download, /share) are reachable from other devices", http.StatusForbidden)
	return
}
```

即：只要绑定 `0.0.0.0`（`lanAccess=true`），任何同网设备对 `/download/<订阅名>`、`/share/...` 无需任何令牌/口令即可请求；闸门只按「路径前缀 + 来源是否 loopback」区分，不校验 token、签名或订阅名随机性。订阅名由用户在 Sub-Store 里自取（常见为机场名、地区名等可猜词），可字典枚举，命中即返回完整转换结果（含全部节点密码/UUID）。`/share/` 仅在用户在 Sub-Store 内另行配置了 share token / AGE 公钥时才在后端内部生效（内置后端 `findShareToken` 逻辑，默认未配置即明文直出）；`/download/` 本身无此机制。访问会被记入运行日志（远程访问不豁免日志），但无失败限流/锁定（见 L5）。

### 2) 更新下载是否只走 https 且校验哈希？镜像 http 明文风险？——哈希有，https 与真实性没有

- 哈希：后端/前端文件下载后与 manifest 比对 SHA-256，不符即拒装：
  - `core/ssc/update.go:253` `if sha256Hex(b) != strings.ToLower(man.Backend.SHA256) {`
  - `core/ssc/update.go:285` 前端同理。
  - 已装后端每次启用时也复验：`core/ssc/update.go:74-83` `activeBackend`。
- 但信任根是 manifest 本身，而 manifest 无任何签名校验：
  - `core/ssc/update.go:135-165` `fetch()` 按 mirrors 顺序拼接 `u = strings.TrimRight(m, "/") + "/" + url` 拉取 manifest 与文件；`checkCompat`（`update.go:193-203`）只校验 `schema/hostApi/minCore`，不校验 manifest 来源、签名、URL 域名与 scheme。
  - `core/ssc/update.go:244-249` 安装时直接 `fetch(man.Backend.URL, ...)`——manifest 说去哪下就去哪下，`http://` 也照单全收（`http.NewRequest` 不限制 scheme，`fetch` 全程无 `https` 强校验；Go 客户端默认跟随重定向，亦可被 https→http 降级）。
- 镜像线路（ArkTS 侧）：`entry/src/main/ets/common/SsUpdate.ets:18`

```ts
const MIRRORS: string[] = ['https://ghfast.top', 'https://gh-proxy.com'];
```

  默认线路 0「自动」为 `['', ghfast.top, gh-proxy.com]`（`SsUpdate.ets:62-73`）：GitHub 直连失败（国内常见）即自动改走第三方镜像。镜像当前是 https，明文 http 风险不在字面，而在**真实性**：镜像（或其被劫持/MITM 时）可同时改写 manifest 与文件并重算 SHA-256，哈希完全自洽，客户端无法分辨——SHA-256 在此只防传输损坏/单文件替换，不防发布通道造假。另外镜像可完整看到设备 IP 与更新查询（隐私面）。
- 后端「试运行」不构成隔离：`core/ssc/update.go:261` `e := NewEngine(tmp, b, ...)` 在正式安装前已在本进程、同等宿主能力下执行了一遍下载到的 JS（试运行目录为空数据目录，但 `$Plugins.Requests` 网络能力是活的）。

### 3) goja 脚本算子的沙箱边界？——与后端同 VM、同全局、无超时中断，等于本机代码执行

- 构建时刻意保留全局 eval：`core/substore/build-hm.js:16-17`

```js
// direct eval makes every enclosing scope dynamic; indirect eval is enough (only globals are read)
c = c.replace(/(^|[^A-Za-z0-9_$.])eval\(/g, '$1(0,eval)(');
```

  Sub-Store 的 Script Operator / Script Filter / 同步脚本等用户脚本正是经此通道执行。
- 脚本与后端跑在**同一个** goja Runtime：`core/ssc/engine.go:96-97` 只注册了 console 原生模块（无 fs/os/process 原生模块，这是好的下限），但 `engine.go:187` `vm.RunProgram(prog)` 后，后端把全量分发入口挂在全局：补丁 `core/substore/substore-hm.patch`（express.js）`globalThis.__ssDispatch = (req) => dispatch(req);`。任何被 eval 的脚本可直接调用 `__ssDispatch` 发起任意 `/api/*` 请求（含 `/api/storage` 全量备份导出、增删订阅、同步配置），也可改写/挂钩全局对象、污染后续请求处理。
- 宿主能力经 `$Plugins` 全量暴露给脚本：`core/ssc/engine.go:159` `plugins.Set("SubStoreCache", cache)`（全部持久化 KV 读/写/删，含其他订阅与 Gist 凭据）、`engine.go:166` `plugins.Set("Requests", ...)`（任意外联，见 M3）、`Notify`。
- 无执行超时/中断：全仓 `grep Interrupt` 在 `core/ssc/*.go` 无结果；`engine.go:298` 的 `time.After(timeout)` 只是让等待的 HTTP 调用方放弃，goja 事件循环一旦被脚本死循环占住，后端整体永久卡死，只能重启进程。
- 触发面：脚本来源不止用户手写——远程订阅自带的 process 算子、他人分享的订阅/组合、Gist 同步下来的 artifacts/scripts 都可携带脚本。结论：**「导入一条带脚本的订阅」≈「运行对方提供的 JS 并授予其全部订阅数据 + 内网/外网请求能力」**，与上游 Sub-Store 在 Surge/Loon 等宿主中的脚本模型相比，这里的宿主能力面更大（全量存储 + 全量 API），上架文案与导入确认中必须明示，且应考虑默认禁用脚本类算子（见修复建议）。

### 4) WebView 是否允许任意外链 / data / javascript、混合内容？——外链走系统（好），但 data:/javascript: 被当「本地」放行（坏）

- `entry/src/main/ets/views/StoreView.ets:86-90`

```ts
function isLocalUrl(url: string): boolean {
  const l = url.toLowerCase();
  return l.startsWith('http://127.0.0.1:') || l.startsWith('http://localhost:') || l.startsWith('about:') ||
    l.startsWith('blob:') || l.startsWith('data:') || l.startsWith('javascript:');
}
```

- `StoreView.ets:242-250` `onLoadIntercept`：非「本地」一律 `openExternal()` 交系统并拦截（这一点是对的，外部 http/https 不会在 WebView 内加载）；但 `data:`/`javascript:` 被判为本地而在 WebView 内放行——`javascript:` 在当前页上下文执行、`data:text/html` 可渲染任意 HTML，均可触及下述桥与注入脚本。且 `127.0.0.1:` 只匹配前缀、**不限本应用端口**，设备上其他本地服务页面同样算「本地」。
- 桥与注入的作用域是全部页面：`StoreView.ets:211-217`

```ts
.javaScriptProxy({ object: this.bridge, name: 'SubStoreHost', methodList: ['copy'], controller: WebHolder.controller })
.javaScriptOnDocumentStart([{ script: CLIPBOARD_JS, scriptRules: ['*'] }])
```

  桥只有 `copy()`（只能写剪贴板、不能读，影响有限，见正向项），但注入范围 `['*']` + 上述放行面意味着任何能进 WebView 的内容都能调用它覆写剪贴板（pastejacking 素材）。
- Web 配置其余项：`StoreView.ets:202-204` `javaScriptAccess(true)`（前端必需）、`domStorageAccess(true)`（前端必需）、`fileAccess(false)`（好）、`geolocationAccess(false)`（好）。代码未显式设置 `mixedMode`，混合内容行为依赖 ArkWeb 平台默认（默认禁止），属未声明依赖，建议显式写死（见 M4）。

### 5) 日志 / 剪贴板是否带出订阅 URL 中的 token？——会，两条路径脱敏都只做了一半

- 服务端访问日志的脱敏只覆盖顶层同名参数：`core/ssc/server.go:382-396` `redactPath` 仅对 query 中 key 恰为 `token`/`key`/`secret` 的做 `q.Set(k, "***")`；形如 `/download/x?url=https://机场/sub?token=…` 的 token 嵌在 `url=` 参数值里、或参数名为 `auth`/`access_token`/`api-key`/`age-secret-key` 时均原样入日志。
- 后端（引擎）事件日志走另一条路且不经 `redactPath`：后端 console 输出经 `engine.go` 的 `Log/Warn/Error` 打印器 → `server.go` 的 `s.Event(...)` 直接入运行日志；后端内部打印远程订阅 URL 用的 `dn()`（内置 `core/ssc/assets/backend.js`）只脱敏 `age-secret-key=` 参数与 AGE 密钥本体，不脱敏一般订阅 `?token=`。
- 日志可整本带出：`entry/src/main/ets/pages/LogPage.ets:68-96` 「复制全部」经 `FileUtil.copyText(this.allText())` 进系统剪贴板、「保存为文件」导出 `.log`；用户按排障习惯把日志发给他人/群聊即连带发出 token。剪贴板桥本身只写不读（`FileUtil.ets:82-87`、`StoreView.ets:50-58`），ManagePage 复制的是用户点按的服务地址（不含订阅路径，`ManagePage.ets:95-97` 会把所复制文本同时 toast 全文显示，复制订阅相关文本时注意同屏泄露）。

---

## 高危

### H1 LAN 模式 /download、/share 无鉴权，订阅名可枚举
- 位置/证据：见专项 1（`server.go:314-322, 367-371`；绑定来源 `entry/src/main/ets/common/Server.ets` 中 `q['host'] = store.lanAccess ? '0.0.0.0' : '127.0.0.1'`）。
- 影响：开启 LAN 后同网任意设备（含被入侵的 IoT、公共/共享 Wi-Fi 他人）可批量猜订阅名下载全部节点凭据；`lanUI`（管理面）默认关且有二次警示，但下载面没有同等级警示——`ManagePage.ets` 对 lanUI 的警示文案明确写了「后端没有账号密码」，对 lanAccess 只有功能描述。
- 修复：① 给 `/download`、`/share` 增加可选（建议 LAN 时强制）访问令牌：如服务端生成随机 token，链接形如 `/download/<name>?token=<随机>`，本机 UI 复制时自动拼上，校验失败 404 且加限流；② 或至少在开启 LAN 时弹出与 lanUI 同级警示并默认缩短开启时长（退出/定时自动关）；③ 订阅名枚举失败（404）做指数退避/统一延时。

### H2 更新通道无签名，镜像可协同篡改（SHA-256 自证无效）
- 位置/证据：见专项 2（`update.go:135-165, 193-203, 244-285`；`SsUpdate.ets:18, 62-73`；`AppReleasesURL` 应用更新检查 `update.go:415, 435` 同样经 `fetch()` 走镜像且无签名，虽只打开页面危害较低）。
- 影响：一旦默认线路落到第三方镜像且镜像作恶/被劫持，用户点一次「安装更新」即装入攻击者后端 JS 并在 H3 的宿主能力下常驻运行（试运行还会先行联网执行一次）。GitHub 直连通道同样问题较小但仍无发布者签名，仓库/令牌失守即全量用户中招（见 M5）。
- 修复：① manifest 加离线签名（Ed25519 公钥内置于 App/核心，私钥离线保管，工作流只拿签名私钥的受控注入或改为本地/受控环境签名发布）；② `fetch()` 强制 https-only、禁止重定向降级、part URL 域名白名单（仅 github.com / objects.githubusercontent.com 等）；③ 默认线路改为「直连优先且镜像需用户显式选择」，镜像模式下在 UI 明示「镜像可看到并可替换更新内容（已签名校验）」——有了 ① 之后此提示才成立。

### H3 goja 脚本与后端同 VM：脚本算子 = 全权代码执行，且可永久卡死后端
- 位置/证据：见专项 3（`build-hm.js:16-17`；`engine.go:96-97, 159, 166, 187, 269-300`；`substore-hm.patch` 的 `__ssDispatch` 全局注册）。
- 影响：恶意/被污染的订阅、组合、同步脚本可读取全部订阅与同步凭据、调用任意 API 改/删数据、向任意地址发请求（M3）、覆写全局逻辑做持久化后门（数据在 KV 中跨重启保留）；死循环脚本让后端不可用且无自愈。
- 修复：① 脚本在独立 goja Runtime 中执行（与后端 VM 物理隔离），只传入节点数组与受限 `$` 工具，禁止触达 `$Plugins.SubStoreCache/__ssDispatch` 等全局；② 每次脚本执行设 `vm.Interrupt` 看门狗（如 10s）与内存上限，超时即终止并记日志；③ 增加设置项「允许脚本类算子」默认关，开启时对含脚本的订阅导入做显著确认；④ 至少把 `__ssDispatch`、`$Plugins` 在脚本求值期间临时摘除/冻结（Object.freeze + 求值后恢复），作为过渡缓解。

### H4 loopback 即完全可信：同机任意应用可无鉴权调用全量管理 API
- 位置：`core/ssc/server.go:301-306, 342-371`

```go
func isLoopback(ip string) bool {
	p := net.ParseIP(ip)
	return p != nil && p.IsLoopback()
}
```

  `handle()` 对 loopback 来源不做任何附加校验即放行全部 `isBackendPath`（含 `/api/*` 的增删改、`/api/storage` 全量备份、脚本执行触发）。
- 影响：HarmonyOS 上回环端口不按应用隔离；设备上任意其他 App（或其内嵌 WebView/浏览器页面在 CORS 之外用原生请求）只要知道端口（默认端口固定，见 `Store.ets` 的 `DEFAULT_PORT`）即可在服务运行期间读取全部订阅、导出备份、增删数据或触发脚本。浏览器网页受同源/CORS 限制较难直接读取响应（后端 CORS 由上游逻辑控制），但原生应用无此限制。
- 修复：① 核心启动时生成一次性随机管理令牌，经 NAPI 通道（不经 URL）交给 ArkTS，Web UI 的 `?api=` 之外另由前端注入 `Authorization`/自定义头，`handle()` 对 `/api/*`（至少写操作与 `/api/storage`、同步类）校验该令牌；`/download` 本机访问可维持便利但应与 H1 一并纳入令牌策略评估；② 或随机化默认端口并仅作缓解（单独不够）。

---

## 中危

### M1 LAN 传输为明文 HTTP，订阅内容在局域网内裸奔
- 位置：`Server.ets` 的 `localBase()` 恒为 `http://` + `server.go:161` 起监听明文 HTTP。
- 影响：LAN 下载时节点密码/UUID 以明文过网，同网嗅探（公共 Wi-Fi、被入侵路由器/AP）即可截获，与 H1 叠加。
- 修复：LAN 开启提示中明示明文风险；进阶可为 LAN 模式生成自签证书提供 https 链接（客户端需信任，体验成本高），或引导用户改用同机直连/加密分享（AGE 分享链接后端已支持，应在 UI 引导）。

### M2 日志脱敏不完整，订阅 token 可经日志复制/导出外泄
- 位置/证据：见专项 5（`server.go:382-396`；`engine.go` console 打印器与后端 `dn()` 的覆盖范围；`LogPage.ets:68-96`）。
- 修复：① 在 Go 层入日志前做统一脱敏（事件与访问两路）：正则掩盖 URL 中 `token|key|secret|auth|password|passwd|access_token|api[-_]?key|age-secret-key` 参数值，并对 `url=` 等参数的值做 URL 解析后递归脱敏、截断；② 后端日志回调 `s.Event` 入口统一过同一脱敏函数；③ LogPage 导出/复制时二次提示「日志可能含订阅链接参数」。

### M3 `$Plugins.Requests` 无出站边界（SSRF / 内网探测 / 任意代理）
- 位置：`core/ssc/engine.go:166-245`

```go
plugins.Set("Requests", func(opts map[string]interface{}) *goja.Promise { ... })
...
if px, ok := o["Proxy"].(string); ok && px != "" {
	if pu, err := url.Parse(px); err == nil {
		client = &http.Client{Transport: &http.Transport{Proxy: http.ProxyURL(pu)}}
	}
}
...
req, err := http.NewRequest(strings.ToUpper(method), u, body)
```

  URL scheme/host 不设限：可请求 `http://127.0.0.1:<本服务端口>/api/...` 自我调用、`http://192.168.0.1/` 等内网管理面、云元数据类地址；可任意设置请求头（含把订阅凭据发往第三方）；默认客户端跟随重定向，https 订阅地址可被重定向降级到 http 并把 URL 中的 token 带到明文请求行。
- 修复：① 默认拒绝目标为 loopback/链路本地/RFC1918 的请求，仅当该请求源于用户手填的订阅地址（而非脚本）时放行并记日志；② 禁止脚本指定 `Proxy` 或仅允许用户在设置中预置的代理；③ 对跨主机的 https→http 重定向拒绝并记录。

### M4 WebView 加载白名单与桥注入范围过宽
- 位置/证据：见专项 4（`StoreView.ets:86-90, 202-217, 242-250`）。
- 影响：`data:`/`javascript:` 页面可在 WebView 内执行；`127.0.0.1` 任意端口页面被视为可信并获得剪贴板桥与文档起始注入脚本；外部内容一旦借道进入（恶意订阅名/文件内容触发前端渲染问题时）放大 XSS 后果。
- 修复：① `isLocalUrl` 改为精确匹配本服务源：`http://127.0.0.1:<当前端口>/` 与 `about:blank`，`data:`/`javascript:` 直接拦截（返回 true 并提示），`blob:` 仅放行本源创建的下载场景（如 ArkWeb 允许区分则按来源判断）；② `javaScriptProxy` 与 `javaScriptOnDocumentStart` 的 `scriptRules` 收敛为本服务源；③ 显式 `.mixedMode(MixedMode.None)` 写死平台默认。

### M5 CI 供应链：写权限令牌与上游依赖安装同处一个 Job，Action 未按 SHA 固定
- 位置：`.github/workflows/substore-assets.yml:30-45`

```yaml
permissions:
  contents: write
...
jobs:
  build:
    env:
      GH_TOKEN: ${{ github.token }}
```

  同一 Job 内 `core/substore/prepare.sh:14` `git clone --depth 1 --branch $BACKEND_TAG …Sub-Store.git`（按 tag 克隆，未校验 commit）、`prepare.sh:21` `npx -y pnpm@11.0.9 install`（执行上游依赖的安装脚本，环境中带 `GH_TOKEN`）、`prepare.sh:26` `curl -fsSL … dist.zip`（前端产物未校验哈希即打包发布）；Actions 均为大版本标签引用：`substore-assets.yml:47, 64, 69` `actions/checkout@v4`、`actions/setup-node@v4`、`actions/setup-go@v5`，`app-release.yml:25` 同。
- 影响：上游仓库/tag/任一 npm 依赖或被劫持的 Action 一旦作恶，可借 Job 内令牌向本仓库 Release 推送被投毒的 backend.js/web.zip——与 H2（客户端无签名校验）叠加即完整投毒链。
- 修复：① 拆 Job：构建 Job `permissions: contents: read` 且不注入写令牌、产物走 artifact；发布 Job 才 `contents: write` 且只做上传与（H2 的）签名；② 所有 `uses:` 固定到 commit SHA；③ 上游按 commit 拉取并核对预期哈希，前端 dist.zip 校验上游公布的校验和；④ pnpm 安装加 `--ignore-scripts`（如构建确需脚本再白名单）。

### M6 前端（web）更新启用时不复验完整性，与后端不一致
- 位置：`core/ssc/update.go:85-93`

```go
func activeWeb(dataDir string) (fs.FS, string, bool) {
	dir := filepath.Join(updRoot(dataDir), "web")
	if v, ok := readInstalled(dir); ok {
		if st, err := os.Stat(filepath.Join(dir, "dist", "index.html")); err == nil && !st.IsDir() {
			return os.DirFS(filepath.Join(dir, "dist")), v.Version, true
		}
	}
```

  对比后端 `activeBackend`（`update.go:74-83` 每次启用都比对 `version.json` 中 SHA-256）：web 只看 `dist/index.html` 存在，安装后文件被改动（其他漏洞写入、同步工具篡改、存储损坏）不会被发现，Web UI 是接触全部订阅数据的界面，其 JS 被换即等于管理面被换。
- 修复：安装时把每个文件（或整包清单）的哈希写入 version.json，`activeWeb` 启用前抽验 `index.html` 与主 JS chunk 的哈希，不符即回退内置前端并记事件；成本低的做法是保留原始 `web.zip` 在 update 目录，启用前比对整包 SHA。

### M7 文件选择/下载落盘的文件名净化不一致，存在边角穿越
- 位置：
  - 上传：`entry/src/main/ets/views/StoreView.ets:261` `const dest = dir + '/' + FileUtil.nameFromUri(u);`，而 `FileUtil.ets:90-97` 的 `nameFromUri` 是**先按最后一个 `/` 切分、再 `decodeURIComponent`**——解码后可再出现 `/`、`..`（如 `%2e%2e%2f`），`dest` 拼出 `cache/uploads/` 之外的路径，随后 `copyUriToAsync` 向其写入用户所选文件内容。触发者是机主自己选的文件，影响限于本应用沙箱，故定中低；但与下载侧形成对照——下载侧 `StoreView.ets:126-139` 对 `getSuggestedFileName()` 做了 `[\\/:*?"<>|\n\r] → _` 净化，却仍放过纯 `..`/`.` 文件名（`path = dir + '/' + name` 后 `item.start(path)`）。
  - `FileUtil.ets:115-123` `copyUriToAsync` 对 `dest` 不做规范化校验。
- 修复：文件名统一走一个 `sanitizeFileName()`：先 decode、再取 basename、替换路径分隔与控制字符、拒绝 `.`/`..`/空名并限长；落盘前断言规范化后的绝对路径仍在目标目录前缀内。

---

## 低危 / 纵深防御

### L1 polyfill `bytesOf` 切片不做边界校验，可被构造数据 panic
- `core/ssc/polyfill.go:97` `return buf.Bytes()[off : off+ln]`：`byteOffset/byteLength` 来自 JS 侧对象，越界即 panic；运行在后端事件循环线程上，后果为后端崩溃/重启。修复：取 min 并校验 `off, ln` 范围，非法返回 nil。

### L2 YAML 别名/合并键展开的资源消耗与回退路径
- `core/ssc/yaml.go:40` 深度上限 200（好），但别名展开（`yaml.go:50, 107-130`）无总节点数上限，锚点指数膨胀文档会先在原生解析里耗内存/CPU，失败后又回退到慢速 JS 解析器（`yamlToJSON` 返回 false 的路径）二次放大；订阅内容来自远程，属于低成本 DoS。修复：限制输入字节数与展开后节点总数，超限直接报错不回退。

### L3 napi.c 健壮性
- `core/napi.c` `getStr`：`malloc` 返回值未判空即写；`CallAsync` 未检查 `napi_create_async_work/queue` 失败路径（Job 泄漏、deferred 永不 resolve 时 ArkTS 侧 Promise 悬挂）。均只影响本进程稳定性，无跨界利用面。修复：补判空与失败回收。

### L4 `allowLAN` 为死字段，放行逻辑与命名脱节
- `core/ssc/server.go:77, 192` `allowLAN` 在 `Start()` 中赋值后全仓无任何读取；真正的闸门由绑定地址 + `lanStatic` + 路径前缀决定。日后维护者误以为改它能控权会埋雷。修复：删除该字段或让闸门显式引用它（`if s.allowLAN && isPublicPath(p)`），并加注释说明绑定即边界。

### L5 无请求限流与较宽的资源上限
- `server.go:188-189` HTTP 超时齐全（好），但 `dispatch` 允许 32MB  body（`server.go:400` `io.LimitReader(r.Body, 32<<20)`）、单请求最长 150s 引擎等待（`server.go` dispatch 调用处 / `engine.go:298`），LAN 侧无并发/频率限制，配合 H1 可做枚举与资源占用。修复：LAN 来源加基础限流与并发上限，`/api` 写操作单独限流。

### L6 敏感数据明文落盘；「清除全部数据」不删已下载的更新代码
- 存储：后端 KV 为明文 JSON 文件（每 key 一文件）存于应用沙箱 `filesDir/substore/store/`，`engine.go` 的 `NewKV/Set` 用目录 `0700`、文件 `0600`（在沙箱内是合理基线），内含订阅 URL（含 token）、节点密码、同步/Gist 凭据等——市场隐私声明须按「本地明文存储订阅凭据」如实描述；`Prefs.ets:1` 自注「Plain (non-secret) settings」且实际只存端口/LAN/语言等非密项（好）。
- 清除：`server.go:236-238` `Reset` 只 `os.RemoveAll(filepath.Join(dataDir, "store"))`，`<dataDir>/update/` 下已下载的 backend.js/web 与 `backend.bad` 不删；若用户因「订阅/脚本可疑」而清除数据，下载来的代码仍在并会继续被加载。修复：Reset 同时删除 `update/` 并回到内置版本，或在清除确认文案中明示并提供「同时恢复内置版本」。

### L7 版本锚点不一致与发布校验和自产自验
- `core/ssc/api.go` `CoreVersion = "1.2.0"` 与 App `1.2.2`（`AppScope/app.json5`）不一致，而更新兼容判定 `checkCompat` 用 `CoreVersion` 与 manifest `minCore` 比对（`update.go:193-203`），版本锚漂移会使兼容结论失真。另 `app-release.yml:51` 的 `SHA256SUMS` 是发布 Job 内对收集到的文件现算的，与 dist 分支原有校验和无关，只防传输损坏、不防来源替换（与 H2 同根）。修复：核心版本与 App 版本建立单一来源/CI 校验；发布说明中把校验和定位为损坏校验而非真实性证明，真实性走 H2 的签名。

---

## 正向项（已做对、勿在整改中回退）

1. 权限最小化：`module.json5` 仅 `INTERNET`、`GET_NETWORK_INFO`、`KEEP_BACKGROUND_RUNNING` 三项，均有 reason 与 usedScene；文件访问全走系统选择器，无存储权限直读。
2. 引擎出站 TLS 默认校验开启且脚本关不掉：`engine.go:116-124` `httpClient` 为 `TLSClientConfig: &tls.Config{}`（系统校验），`doRequest` 不解析后端的 `insecure/strictSSL` 选项，无 `InsecureSkipVerify`（全仓无此字符串）。
3. 更新文件级 SHA-256 校验 + 后端试运行失败自动回退内置版本：`update.go:253, 285`、`server.go` 中 `engine()` 的 downloaded backend 启动失败 `markBackendBad` 回退逻辑；`activeBackend` 每次启用复验哈希。
4. zip 解压防穿越与总量上限：`update.go:336-372` `unzipDist` 用 `path.Clean("/"+name)[1:]` 规范化、条目按普通文件写出（不创建符号链接）、解压累计上限 128MB、剔除 sw.js/workbox 等。
5. 服务端基础卫生：`server.go:188-189` 读写/空闲超时齐全；请求体 32MB、引擎响应 64MB、manifest 1MB 等多处 `LimitReader`；来源判断只信 `RemoteAddr`，不信 `X-Forwarded-For`（`server.go` `clientIP`）；静态文件服务 `path.Clean` 防穿越（`serveStatic`）。
6. `redactPath` 至少覆盖了 `token/key/secret` 三个高频参数名、日志条数上限 2000 且事件截断 4000 字符（`server.go` `Event/addLog`）——M2 是在其上补全，不是推倒。
7. WebView：`fileAccess(false)`、`geolocationAccess(false)`；外部链接一律交系统打开（`StoreView.ets:242-250`）；剪贴板桥只写不读、方法面仅 `copy`。
8. `lanUI` 默认关、开启前有明确的「无账号密码、同网可改删」警示与确认（ManagePage）；`lanAccess` 默认关（`Store.ets` 中两开关默认 false）。
9. 仓库卫生：未发现硬编码密钥/口令/私钥（全仓检索仅测试假数据与文档）；签名材料被 `.gitignore` 排除（`*.p12/*.cer/*.p7b/*.csr`、`.so` 产物）；`scripts/fetch-core.sh` 下载核心时校验 SHA256SUMS（真实性局限见 L7）。
10. YAML 原生解析有深度上限、超 2^53 整数与 NaN/Inf 回退等护栏（`yaml.go:40, writeScalar`）；日志模块 `Log.ets` 有明确「密码/token 不入日志、用 mask()」的成文约定（问题在后端引擎日志未走此约定，见 M2）。

---

## 整改优先级建议（供排期）

1. 上架前：H2（签名 + https-only + 域名白名单）、M4（白名单收敛）、M2（统一脱敏）、H1/H4 至少完成令牌方案或强警示 + 默认关闭策略复核、H3 完成「脚本开关默认关 + Interrupt 看门狗」过渡缓解。
2. 上架后一版内：H3 脚本 VM 隔离、M3 出站边界、M5 CI 拆分与 SHA 固定、M6 前端启用复验、M7 文件名统一净化。
3. 常规迭代：L1–L7。

*本报告基于静态审查；goja 运行时行为、ArkWeb 默认 mixedMode、后端 bundle 内部逻辑以其上游 Sub-Store 代码为准，标注「以后端内部逻辑为准」处建议结合真机/动态验证复核。*
