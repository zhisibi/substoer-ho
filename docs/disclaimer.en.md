# SubStore HO Disclaimer & Privacy Notice

Updated: October 22, 2026 (version 2)

Please read this notice before using SubStore HO ("the app"). By continuing to use it you confirm that you have read, understood and agreed to all of it; if you do not agree, stop using and uninstall the app. The app is open source under AGPL-3.0, and nothing here limits your rights under that license.

## 1. Developed by AI

- **The app was developed by AI (Hark Agent)**, including its code, interface, documentation and build scripts, and is published as open source on GitHub by the project maintainer. AI-generated code may contain bugs, security vulnerabilities or unexpected behavior and has not been professionally audited.
- The full source code is at https://github.com/zhisibi/substoer-ho ; you can review, build and verify it yourself.

## 2. Unofficial client

- The app is a third-party HarmonyOS client for the open-source Sub-Store project (https://github.com/sub-store-org/Sub-Store ). **It is not an official Sub-Store product and has no affiliation, authorization, sponsorship or partnership with the Sub-Store project or its authors.** The name "Sub-Store" and its backend and web UI belong to the Sub-Store project and its contributors.
- The bundled Sub-Store backend is modified to run on HarmonyOS and may behave differently from the official version; please do not report problems with this app to the Sub-Store authors.

## 3. A local tool only

- **The app only runs subscription management and conversion on your device. It does not provide, bundle, sell or recommend any proxy server, node, subscription, VPN or network acceleration service, operates no servers and provides no network content.**
- Subscriptions, nodes and scripts are all added by you; you alone judge and are responsible for their source, legality and use.

## 4. Lawful use

- You must comply with the laws of the People's Republic of China and of where you are. **Do not use the app to evade lawful network regulation or for any illegal activity**, and do not provide, share or sell network access, proxy services or other people's nodes and subscriptions.
- Do not use the app if you are under 18.

## 5. Privacy

- **Nothing is collected:** no registration or account; no personal information, device identifiers, location or usage statistics are collected or uploaded; no third-party SDKs (analytics, ads, push, crash reporting) are included.
- **Data stays on the device:** your subscriptions, nodes, scripts, sync tokens and app settings are stored only in the app's private directory and never sent to the developer. Run logs (including visiting devices' IP, path and User-Agent) are kept only in memory and cleared when the app exits.
- **Network connections:** the app only connects to addresses you add or configure in Sub-Store (remote subscriptions, scripts, rules, sync services). In addition, only when you check for or run a Sub-Store update, keep "check for updates at launch" on, or check for app updates under About, it contacts this project's GitHub repository (github.com, api.github.com), possibly via public mirrors such as ghfast.top or gh-proxy.com depending on the route you pick. These requests carry none of your subscription data, but those services process your IP address under their own policies.
- **Permissions:** only network, network state (to show the LAN address) and background running (when you enable "keep running in background"). No camera, microphone, location, contacts or storage permission. The clipboard is written only when you tap copy; files are picked by you through the system picker.
- **Deletion and withdrawal:** under Service management → About you can clear all data or withdraw consent; uninstalling deletes all data.

## 6. Risks

- The local service uses unencrypted HTTP and the Sub-Store backend has no login. With LAN access on, devices on the same network can download subscriptions; with "open the web UI from LAN" on, anyone there can view and change your data. Other apps on the same device can also reach the service on 127.0.0.1. Enable these only on trusted networks.
- Subscriptions contain node passwords and keys; keep subscription links, share tokens, backups and exports safe.
- Sub-Store can run scripts you add; scripts can read, modify or send your subscription content. Use only trusted scripts.
- Data lives only on your device and the developer cannot back it up or recover it; back up regularly with Sub-Store's backup feature.
- HarmonyOS may pause or stop the service after the app moves to the background.
- Component update files are checked by SHA-256, but the availability and security of third-party network services cannot be guaranteed.

## 7. No warranty and limitation of liability

- **The app is provided free and "as is", without any express or implied warranty**, including merchantability, fitness for a particular purpose, security, stability, accuracy and continued availability, consistent with the no-warranty terms of AGPL-3.0 / GPL-3.0.
- **To the maximum extent permitted by law, the developer and project maintainer are not liable for any direct or indirect loss arising from the use of or inability to use the app** (including data loss, leaked subscriptions or keys, device or network problems, disputes with third-party services, and legal liability from unlawful use).

## 8. Open-source licenses

The app is open source under AGPL-3.0 and bundles the Sub-Store backend (AGPL-3.0), web UI (GPL-3.0) and other open-source components; see Service management → About → Open-source licenses. The complete source code, including the modifications to Sub-Store, is at https://github.com/zhisibi/substoer-ho .

## 9. Updates and contact

This notice may change with new versions; you will be shown it again at launch after it changes. For questions, open an issue at https://github.com/zhisibi/substoer-ho/issues , and do not post your subscription links, nodes or tokens.
