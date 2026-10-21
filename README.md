# 咪咪SubStore · Sub-Store for HarmonyOS

HarmonyOS NEXT 上的 [Sub-Store](https://github.com/sub-store-org/Sub-Store) 客户端：Sub-Store 后端和管理界面都在手机本地运行，不需要服务器，也不需要 Node.js。

- 包名 `com.zhisibi.mimisubstore`，当前版本 1.1.0（versionCode 1001000），开发者张世博
- 安装包内置 Sub-Store 后端 2.42.6、前端 2.34.1；之后可在 app 里一键更新到上游最新版（见下文“组件更新”）
- 本应用只是本地工具，不提供任何代理服务器、节点、订阅或 VPN 服务

## 功能

| 页面 | 内容 |
| --- | --- |
| Sub-Store | 默认首页，就是原版 Sub-Store 管理界面（ArkWeb 打开 `http://127.0.0.1:<端口>/?api=<同地址>`）。外部链接和 `clash://`、`sing-box://` 等导入链接交给系统；文件选择、下载“另存为”、剪贴板都接到系统能力 |
| 服务 | 电源按钮、本机 / 局域网订阅地址、端口、局域网访问、局域网管理界面、后台运行、打开应用自动启动、运行日志；“完整日志”页可按后端 / 访问 / 错误筛选，一键复制全部或保存为 .log |
| 设置 | Sub-Store 更新、访问密码与指纹、外观、语言、清除全部数据、关于与开源许可 |

访问控制：默认只监听 `127.0.0.1:3000`。开启“允许局域网访问”后其他设备只能访问订阅链接（`/download`、`/share`）；再开启“局域网也可打开管理界面”才放行管理界面和 `/api`（Sub-Store 后端没有登录验证，界面会二次确认）。

## 架构

```
ArkWeb (Sub-Store-Front-End)  ──HTTP──▶  Go net/http 127.0.0.1:3000   (libmimisubstore.so, NAPI)
                                           ├─ /api /download /share ─▶ goja（纯 Go 的 JS 引擎）里运行的 Sub-Store 后端
                                           │                            $Plugins.SubStoreCache → filesDir/substore/store/*.json
                                           │                            $Plugins.Requests      → Go http.Client
                                           │                            __hm_yamlParse         → Go yaml.v3（原生解析大 YAML）
                                           └─ 其他路径 ─▶ 前端静态文件（内置 go:embed，或下载的更新）
```

为让上游后端跑在 goja 里做的适配（`core/substore/`）：

- `substore-hm.patch`
  - `src/vendor/express.js`：路由在同一个 JS 运行时里并发处理请求（每个请求独立的 `__done`，全局 `__ssDispatch`），不必每次重新加载 1.3 MB 脚本；
  - `src/utils/yaml.js`：有 `__hm_yamlParse` 时用 Go 原生解析 YAML。机场 / edgetunnel 返回的 Clash 配置常有上万行规则，JS 解析器在 goja 里要几十秒并卡住整个后端，原生解析只要零点几秒，结果与 JS 解析逐字节一致，遇到特殊文档自动退回 JS 解析。
- `build-hm.js`：esbuild 打包为 ES2020 IIFE，并把所有直接 `eval(` 改成间接 `(0,eval)(`（直接 eval 会让 goja 崩溃：stash index out of range）。
- 传给上游路由的 URL 必须是完整的 `http://host/path`（上游 `extractURL` 只认完整 URL）；同源请求的 `Origin` 头会被去掉（上游非 Node 环境的 CORS 白名单没有 127.0.0.1）。

## 组件更新（不用重装 app）

Sub-Store 更新很频繁，所以后端和前端可以在 **设置 → Sub-Store 更新** 里单独更新：

1. 本仓库的 GitHub Actions（`.github/workflows/substore-assets.yml`）每 6 小时检查 [Sub-Store](https://github.com/sub-store-org/Sub-Store/releases) 和 [Sub-Store-Front-End](https://github.com/sub-store-org/Sub-Store-Front-End/releases) 的最新正式版；
2. 有新版本就用 `core/substore/prepare.sh`（和安装包同一套补丁）构建后端，`core/substore/smoke.sh` 冒烟测试（网页、建本地 / 远程订阅、下载 ClashMeta、sing-box、Surge、QX、Loon、V2Ray）；
3. 通过后发布 Release `substore-<后端>-<前端>`（`backend.js`、`web.zip`），并更新 Release `substore-latest` 里的 `manifest.json`（版本、下载地址、SHA-256、`hostApi`、`minCore`）。

app 端（`core/ssc/update.go` + `entry/.../common/SsUpdate.ets`）：

- 下载线路：自动（先 GitHub，失败再走 ghfast.top、gh-proxy.com）、直连 GitHub、加速镜像优先；
- 每个文件按清单校验 SHA-256；新后端先在临时目录里试运行，成功才替换；装好后自动重启服务、刷新网页；
- 文件放在 `filesDir/substore/update/`，内置版本始终保留在 .so 里：下载的后端启动失败会自动退回内置版本，也可以手动“恢复内置版本”；
- `hostApi` 与内核不一致、或 `minCore` 高于当前内核时拒绝安装后端（需要先更新 app），前端仍可单独更新；
- “启动时检查更新”默认开启，每天最多检查一次。

手动触发构建：Actions → Sub-Store assets → Run workflow（可指定上游 tag，或勾选 force 重建）。注意 GitHub 会在仓库 60 天无提交后暂停定时任务，届时手动运行一次即可恢复。

## 构建

需要：Node 22、OpenHarmony 版 Go 1.26 工具链（`GOOS=openharmony`）、HarmonyOS SDK / DevEco Studio。

1. `core/substore/prepare.sh`：按 `BACKEND_TAG` / `FRONTEND_TAG` 拉取上游，打补丁、打包后端、下载前端 dist，写入 `core/ssc/assets/`（仓库里已带当前版本的产物，不升级可跳过）。
2. `core/build-core.sh`：交叉编译 `core/out/libmimisubstore.so`，复制到 `entry/libs/arm64-v8a/`。
   不想编译内核，可以直接取预编译版：`scripts/fetch-core.sh`（从 `dist` 分支下载与 `CORE_VERSION` 对应的 .so 并校验 SHA-256）。
3. DevEco Studio 打开项目，配置自己的签名后编译 HAP。

主机测试（Linux / macOS，普通 Go 即可）：

```bash
cd core
go run ./cmd/hostrun /tmp/ss 3000          # 浏览器打开 http://127.0.0.1:3000/?api=http://127.0.0.1:3000
bash substore/smoke.sh                     # 冒烟测试
go test ./ssc/
```

## 目录

```
core/                 Go 内核（NAPI：napi.c + main.go）
  ssc/                engine.go（goja + $Plugins）、server.go（HTTP、访问控制、日志）、update.go（组件更新）、yaml.go
  ssc/assets/         内置的 backend.js 与前端 web/（prepare.sh 生成）
  substore/           prepare.sh、substore-hm.patch、sub-store-hm.js、build-hm.js、smoke.sh
  cmd/hostrun/        主机测试服务器
entry/src/main/ets/   ArkTS：views（Sub-Store / 服务 / 设置）、pages（完整日志、Sub-Store 更新、协议…）、common
docs/                 隐私政策、用户协议、开源许可（scripts/gen-legal.py 生成到 rawfile）
i18n/                 中英文案（scripts/gen-i18n.py）
```

## 许可

- Sub-Store 后端：[AGPL-3.0](https://github.com/sub-store-org/Sub-Store/blob/master/LICENSE)；Sub-Store 前端：[GPL-3.0](https://github.com/sub-store-org/Sub-Store-Front-End/blob/master/LICENSE)。
- 本仓库包含本应用对 Sub-Store 的全部修改和构建脚本（AGPL-3.0 要求的对应源代码）；其余第三方组件见 `docs/licenses/`。
- 本仓库代码以 AGPL-3.0 发布（见 `LICENSE`）。
- 联系：zhisibi@gmail.com
