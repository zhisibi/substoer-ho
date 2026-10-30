# 咪咪SubStore (MimiSubStore) · Sub-Store for HarmonyOS

[Sub-Store](https://github.com/sub-store-org/Sub-Store) 的**第三方、非官方** HarmonyOS NEXT 客户端：Sub-Store 后端和管理界面都在手机本地运行，不需要服务器，也不需要 Node.js。

> **本项目由 AI（Hark Agent）开发。** 代码未经专业安全审计，按“现状”提供、不作任何担保，请阅读 [免责声明](docs/disclaimer.md)。与 Sub-Store 项目及其作者无隶属或授权关系。

- 当前版本 1.4.0（versionCode 1004000）；包名 `com.zhisibi.mimisubstore`（沿用，便于升级覆盖安装）
- 安装包内置 Sub-Store 后端 2.42.6、前端 2.34.1；之后可在 app 里一键更新到上游最新版（见“组件更新”）
- 本应用只是本地工具，不提供任何代理服务器、节点、订阅或 VPN 服务
- 下载：[Releases](https://github.com/zhisibi/substoer-ho/releases)（未签名 HAP，需要用自己的证书签名后安装）

## 功能

打开应用就是原版 Sub-Store 管理界面（ArkWeb 打开 `http://127.0.0.1:<端口>/?api=<同地址>`）；外部链接和 `clash://`、`sing-box://` 等导入链接交给系统，文件选择、下载“另存为”、剪贴板都接到系统能力。右下角的按钮进入**服务管理**（配色与 Sub-Store 前端一致；分组均可按类别折叠）：

| 分组 | 内容 |
| --- | --- |
| 服务 | 启动 / 停止、运行时长与请求数、本机与局域网地址（点按复制） |
| 端口与访问控制 | 端口、允许局域网访问、局域网也可打开管理界面 |
| 后台与自动启动 | 后台继续运行（长时任务）、打开应用时自动启动服务 |
| 外观 | 全局主题（跟随系统 / 浅色 / 深色）、主题色（6 种）、背景（纯色 + 4 种渐变）、导航栏沉浸光感（顶栏悬浮玻璃胶囊 + 网页底栏玻璃胶囊，可关闭） |
| 语言 | 跟随系统 / 中文 / English |
| Sub-Store 更新 | 后端与前端版本、检查 / 立即更新、恢复内置版本、下载线路、启动时检查 |
| 日志与声明 | 完整运行日志（筛选、复制、保存 .log）、免责声明 |
| 关于 | 版本、开发者 张世博、问题反馈（QQ群 1127250124，点按复制群号）、检查应用更新（GitHub Release）、上游项目、免责声明与隐私说明、开源许可、清除数据、撤回同意 |

首次启动需同意《免责声明与隐私说明》，并可查看独立的《隐私政策》（docs/privacy.md）与《用户协议》（docs/terms.md，中英文，应用内“日志与声明”中可打开）；之后每次启动都会弹出声明，可勾选“不再提示”（声明更新后会再次提示）。

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

Sub-Store 更新很频繁，所以后端和前端可以在 **服务管理 → Sub-Store 更新** 里单独更新：

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

## 发布应用版本

1. 改 `AppScope/app.json5` 的版本号（`CoreVersion` 变了就同时改 `core/ssc/api.go` 与 `AppInfo.ets` 的 `CORE_VERSION`），在 `docs/CHANGELOG.md` 写一节 `## <版本>`；
2. 把 HAP 放进 `dist` 分支的 `app/v<版本>/`、内核放进 `core/v<版本>/`（以及 `core/latest/`）；
3. 推送标签 `v<版本>`，`.github/workflows/app-release.yml` 自动创建 Release。app 的“关于 → 检查更新”读取最新的 `v*` Release。

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
entry/src/main/ets/   ArkTS：views/StoreView（Sub-Store 网页）、pages（Index、ManagePage 服务管理、LogPage、MiscPages 协议与许可）、common
docs/                 隐私政策、用户协议、免责声明、开源许可、更新日志（scripts/gen-legal.py 生成 LegalText.ets）
icon-src/             图标生成脚本 make_icon.py
i18n/                 中英文案（scripts/gen-i18n.py）
```

## 许可

- Sub-Store 后端：[AGPL-3.0](https://github.com/sub-store-org/Sub-Store/blob/master/LICENSE)；Sub-Store 前端：[GPL-3.0](https://github.com/sub-store-org/Sub-Store-Front-End/blob/master/LICENSE)。
- 本仓库包含本应用对 Sub-Store 的全部修改和构建脚本（AGPL-3.0 要求的对应源代码）；其余第三方组件见 `docs/licenses/`。
- 本仓库代码以 AGPL-3.0 发布（见 `LICENSE`）。应用内“关于 → 开源许可”列出全部组件及许可证全文，并给出本仓库地址作为对应源代码。
- Sub-Store 名称及其后端、前端的权利归 Sub-Store 项目及其贡献者所有；本项目为第三方移植，不代表官方。
- 开发者：Hark Agent（AI）。问题反馈：[Issues](https://github.com/zhisibi/substoer-ho/issues)
