# MimiSubStore User Agreement

Updated: October 22, 2026 (version 1)
Effective: October 22, 2026

Welcome to MimiSubStore ("the app"), developed and provided by the individual developer Zhang Shibo ("we"). Please read this agreement carefully, **especially the disclaimer, limitation of liability, governing law and dispute resolution clauses in bold**. By tapping "Agree", installing or using the app you accept this agreement and the MimiSubStore Privacy Policy; if you do not agree, do not install or use the app.

## 1. What the app is

A HarmonyOS client for the open-source subscription manager Sub-Store (https://github.com/sub-store-org/Sub-Store ): it runs the Sub-Store backend and web interface locally on your device to add and combine subscriptions, operate on nodes (filter, rename, sort, scripts, etc.), convert formats (Surge, Loon, Quantumult X, Stash, Clash / mihomo, sing-box, Shadowrocket, v2rayN and more), and serve subscription downloads over HTTP on this device or your LAN. The service, port, background running, appearance and access password features are ours; Sub-Store's features and interface come from its open-source project, with only the changes needed to run in this app.

**The app is only a local tool running on your device. It does not provide, bundle, sell or recommend any proxy server, node, subscription, account, VPN, acceleration, circumvention or other network access service, operates no server, provides no network content and connects to no proxy network.** All subscriptions and nodes are added by you; use the generated subscriptions with a separate proxy client. We have no cooperation or financial relationship with any provider of nodes or subscriptions, and are not affiliated with, authorized, sponsored or endorsed by the Sub-Store project or its authors.

The app is free, with no ads and no in-app purchases.

## 2. Eligibility

- You must be an individual aged 18 or over with full civil capacity. **Persons under 18 must not download, install or use the app.**
- You must make sure installing and using the app is lawful where you are; if local law prohibits or restricts such software, stop using and uninstall it immediately.

## 3. Compliance with law and acceptable use

- **You are solely responsible for all subscriptions, nodes and scripts you add, manage, generate and distribute, including their sources, content and use.** Manage only nodes and subscriptions you own or are lawfully authorized to use.
- You must comply with the laws of the People's Republic of China and of your jurisdiction, including but not limited to the Cybersecurity Law, the Data Security Law, the Personal Information Protection Law, the Interim Provisions on the Administration of International Networking of Computer Information Networks and the rules on telecommunications and internet administration, as well as the rules of the network you use.
- **You must not use the app to circumvent lawful network supervision, to establish or use international networking channels without authorization, or for any illegal purpose**, including endangering network security, infringing others' rights, spreading illegal information, network attacks or fraud.
- You must not use the app to provide, share or sell network access, proxy or circumvention services to others, distribute, share or sell other people's nodes or subscriptions, or promote anything commercially in the app's name.
- Everything you do with the app, and its consequences, is your own decision and responsibility.

## 4. Local service, scripts and data safety

- By default the service listens on 127.0.0.1 only (this device) over unencrypted HTTP, and **the Sub-Store backend has no login**. With "Allow LAN access" on, devices on the same network can download subscription links; with "Web UI on the LAN" on, any device on the same network can view, change or delete your Sub-Store data. **Whether to turn these on, on which network, and whom to give links to is your decision and your risk.** Other apps on the same device can also reach the service on 127.0.0.1.
- Subscriptions contain node passwords and keys. Keep subscription links, share tokens, exported files, backups and sync tokens safe and never share them with people you don't trust. **You bear the consequences of leaked links, tokens or files.**
- Sub-Store can run scripts you add. They run on this device, can access the network and process your subscription content; **use only scripts you trust, and you bear the consequences of what they do.** The JavaScript engine built into the app differs from official runtimes such as Node.js, so a few features that rely on Node.js-specific capabilities (such as some network probes or GeoIP databases) may be unavailable or behave differently.
- HarmonyOS may pause or end the service in the background even with a continuous task; we are not responsible for failed subscription updates caused by that.
- **Your data exists only on your device and we cannot back it up or recover it.** Uninstalling, clearing data, replacing or resetting the device, system failures or mistakes can lose it permanently; back up regularly with Sub-Store's backup feature. We are not liable for data loss.

## 5. Third-party apps and services

- The subscription providers and node servers you add, the clients you import subscriptions into (including sing-box, Clash / mihomo, Stash, Surge, Quantumult X, Loon, Shadowrocket, v2rayN, MaoMo, MaoBox and MaoRay), script and rule providers, and sync services such as GitHub Gist are provided or operated independently by third parties, which are responsible for their content, legality, security, privacy and availability. **Any dispute between you and a third party is for you and that party to resolve; we are not liable.**
- Client formats change between versions; generated configs are not guaranteed to work with every client or version. Sub-Store's features, compatibility and fixes follow its open-source project, and the bundled version may lag behind the latest upstream release.

## 6. Disclaimer of warranties

- **The app is provided "as is" and "as available", without warranties of any kind, express or implied, including merchantability, fitness for a particular purpose, non-infringement, security, stability, accuracy or availability.** We do not warrant that the app meets your needs, runs uninterrupted, timely, securely or error-free, or that any defect will be fixed.
- We are not responsible for the legality, security, privacy or availability of any node, subscription, server or configuration you use, or for any data carried through those nodes or third-party clients.

## 7. Limitation of liability and indemnity

- **To the maximum extent permitted by law, we are not liable for any direct, indirect, incidental, special or consequential loss (including data loss, privacy disclosure, business interruption or lost profits) arising from using or being unable to use the app, mistakes, misconfiguration, data loss or disclosure, network conditions, third-party apps or services, system limits or force majeure, even if advised of the possibility.** Our total liability to you shall in no event exceed what you paid for the app (it is free, so zero).
- Nothing in this agreement excludes or limits liability that cannot be excluded or limited under applicable law.
- If your breach of law or of this agreement, or illegal use of the app, causes us any third-party claim, administrative penalty or other loss, you shall compensate us for it, including reasonable legal fees and costs.

## 8. Intellectual property

The app's own design, icon and code belong to the developer; the Sub-Store name, backend and web interface belong to the Sub-Store project and its contributors. Open-source components belong to their authors under their licenses (section 9). mihomo, Clash, sing-box, Surge, Quantumult X, Loon, Shadowrocket, Stash, v2rayN, Huawei and HarmonyOS are names and marks of their respective owners; the app only generates compatible configuration formats or states compatibility and is not affiliated with, authorized, sponsored or endorsed by them.

## 9. Open-source software

| Component | Purpose | License |
| --- | --- | --- |
| Sub-Store backend (sub-store-org/Sub-Store) | Subscription parsing, processing and conversion (bundled, adapted) | AGPL-3.0 |
| Sub-Store front-end (sub-store-org/Sub-Store-Front-End) | Web interface (bundled) | GPL-3.0 |
| goja / goja_nodejs | JavaScript engine that runs the Sub-Store backend on the device | MIT |
| Go runtime and standard library | Core runtime, HTTP service | BSD-3-Clause |
| Sub-Store backend dependencies (lodash, yaml, js-base64, jsrsasign, etc.) | Bundled into the backend | Their own licenses (MIT, etc.) |

The Sub-Store backend is released under AGPL-3.0 and the web interface under GPL-3.0. Under these licenses you are entitled to the complete source code of the Sub-Store components in the app, including our changes: email us and we will provide the source, our changes and the build scripts free of charge. Full license texts: Settings › About › Open-source licenses.

## 10. Distribution, changes and termination

- Get the app only from official channels (AppGallery once listed, or https://aimm.886423.xyz/cats/ ); packages from other sources may be tampered with, at your own risk.
- We may release new versions, and older ones may no longer be maintained; we may change, suspend or end development, maintenance or distribution of the app at any time without notice.
- We may update this agreement and publish it in the app and on the website; material changes require your consent again. If you do not agree, stop using and uninstall the app.
- If you breach this agreement, or local law does not allow using the app, your permission to use it ends automatically and you must stop using and uninstall it.
- You may stop using and uninstall the app at any time, which deletes all its data on your device.

## 11. Governing law and disputes

- **This agreement is governed by the laws of the People's Republic of China (for this purpose excluding the laws of the Hong Kong and Macao SARs and Taiwan, and excluding conflict-of-law rules).**
- **Disputes arising from this agreement or the app shall first be settled through friendly negotiation; failing that, either party may sue in the competent people's court where the developer is located.**

## 12. Miscellaneous

- If any clause is held invalid or unenforceable, the rest remain in force, and that clause is applied as closely to its intent as the law allows.
- Not exercising or delaying a right is not a waiver of it.
- Headings are for convenience only. The Chinese version prevails; this English version is for reference.

## 13. Contact

Developer: Zhang Shibo (individual developer) — zhisibi@gmail.com
Website: https://aimm.886423.xyz/cats/

We reply within 15 working days.
