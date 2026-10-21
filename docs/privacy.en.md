# MimiSubStore Privacy Policy

Updated: October 22, 2026 (version 1)
Effective: October 22, 2026

MimiSubStore ("the app") is developed and provided by the individual developer Zhang Shibo ("we"). The app is a HarmonyOS client for the open-source subscription manager Sub-Store: Sub-Store's backend and web interface both run locally on your device to manage and convert your own proxy subscriptions (Surge, Loon, Quantumult X, Stash, Clash / mihomo, sing-box and other formats) and to serve subscription downloads on this device or your LAN. **The app is only a local tool. It does not provide any proxy server, node, subscription, VPN or circumvention service, and provides no network content.**

We process information in line with the Personal Information Protection Law of the People's Republic of China and other laws. This policy explains what the app processes, how, and your rights; section 10 covers privacy-related disclaimers. Please read it carefully, especially the parts in bold. This policy and the MimiSubStore User Agreement together govern your use of the app. The Chinese version prevails.

## 1. Overview

1. The app **needs no registration or sign-in and has no accounts**.
2. The app **does not collect or upload** any personal information, device identifiers (such as OAID or UDID), location, contacts, usage statistics or behavioural data, and does no profiling, personalisation or ad tracking.
3. We **run no server that provides data services to the app**; nothing you save in the app is sent to us.

## 2. Information kept only on your device

The following is entered, imported or produced by you and **kept in the app's private sandbox**; it is not sent to us:

1. Sub-Store data: your subscriptions and collections (names, subscription URLs or local node content, User-Agent, node operations and scripts, icons, etc.), files, sync settings (such as a GitHub Gist token, only if you enter one), share tokens, archives and Sub-Store settings, and the remote subscriptions and scripts Sub-Store caches for speed. Node data may contain server addresses, ports, UUIDs, passwords and keys.
2. App settings: theme, accent colour, a copy of your background image, language, server port, LAN access, background running and autostart options.
3. Web storage of the Sub-Store interface: preferences the interface saves in the built-in web component (such as its language and display options), kept only in the app's web data directory.
4. Run log: service events (start, stop, port errors, background task), Sub-Store backend log output, and records of subscription downloads and requests from other devices (time, client IP, path, status, client User-Agent), kept in memory only (at most 2000 entries) for the Server page and cleared when the app exits.
5. Access password and security questions (optional): if you set an app access password, the app **does not store the password or answers themselves**, only salted hashes (PBKDF2-HMAC-SHA256, a separate random salt for each) plus the question texts, in the system Asset Store, readable only by the app. Nobody, including us, can recover your password from the hashes.
6. System log: runtime information is written to the system log (hilog) for debugging; the app never reads or uploads it.

## 3. Network access and permissions

| Permission | Purpose |
| --- | --- |
| Internet (ohos.permission.INTERNET) | Run the local Sub-Store service; fetch the remote subscriptions, scripts and rules you add; reach the sync services you configure; serve subscription downloads on this device or your LAN |
| Network info (ohos.permission.GET_NETWORK_INFO) | Read this device's LAN IP address to show LAN subscription addresses |
| Background running (ohos.permission.KEEP_BACKGROUND_RUNNING) | Only when you turn on "keep running in background" and start the service: request a continuous task so the service keeps answering after the app goes to the background |
| Biometrics (ohos.permission.ACCESS_BIOMETRIC) | Only after you set an access password and turn on fingerprint unlock: unlock the app with the system fingerprint prompt |

1. Outgoing connections **go only to addresses you add or configure in Sub-Store**: remote subscription URLs, script and rule URLs, and sync services you enable (such as GitHub Gist). Some images in the Sub-Store interface (such as empty-state illustrations and icons) may load from public image hosts used by the open-source project; those requests carry none of your subscription data. **Sub-Store component updates:** when you tap “Check for updates” or “Update now” in Settings → Sub-Store update, or leave “Check on startup” on (at most once a day), the app downloads the update manifest and files from this app's GitHub repository (github.com/zhisibi/substoer-ho), possibly relayed by public mirrors such as ghfast.top or gh-proxy.com depending on the download route you choose. These requests carry only an app version identifier, none of your subscription data. Apart from that, the app never connects to our servers.
2. **The local service** listens on 127.0.0.1 only (this device) by default, port 3000. With "Allow LAN access" on, devices on the same LAN **can only reach subscription download links (/download, /share)**; only if you also turn on "Web UI on the LAN" can other devices open the interface and call the backend API. **The Sub-Store backend has no login, and subscriptions contain node passwords and keys: turn on LAN access only on trusted networks and do not share subscription links with people you do not trust.** The service uses unencrypted HTTP; others on the same network may intercept it.
3. The app **requests no camera, microphone, location, contacts or storage permission**.

## 4. Device capabilities

1. Clipboard: written only when you tap Copy (or similar) in the Sub-Store interface; the app never reads the clipboard by itself.
2. Files: restoring a backup or importing a file in Sub-Store uses the system picker, where you choose the file; downloading a backup or exporting a configuration uses the system Save dialog, where you choose the location. **Backups and exported files may contain plain-text passwords and keys; keep them safe.**
3. Opening other apps or web pages: when you tap a link to another website or a client import link (such as clash:// or sing-box://) in Sub-Store, the system opens the browser or that app; how the receiving side handles it is governed by its own privacy policy.
4. Continuous task and notification: with background running on, the system shows a persistent notification while the service runs; it disappears when the service stops.
5. Fingerprint unlock: enrolment, matching and storage are handled entirely by the HarmonyOS user authentication service in the device's secure environment; **the app cannot obtain and does not store any fingerprint image or template**.

## 5. Third-party SDKs, open-source components and services

1. The app **integrates no third-party SDK** (no analytics, ads, push, sign-in or crash reporting).
2. The app bundles the backend and web interface of the open-source Sub-Store project (see the open-source notice in the User Agreement); they run locally and send no data to their authors or to us.
3. Third-party services you configure in Sub-Store (subscription providers, script hosts, GitHub Gist, etc.) process your requests under their own policies.
4. The update check queries HUAWEI AppGallery only when you tap Settings › About › Check for updates, processed by Huawei under its privacy policy.

## 6. Storage, retention and security

1. Location: everything above stays on your device.
2. Retention: until you delete it in the app or uninstall the app; the run log is cleared when the app exits.
3. Security: data lives in the app's private sandbox that other apps cannot read; the service listens on the local address only by default, so other devices cannot reach the management API; you can set an app access password and fingerprint unlock. Please protect your device with a screen lock. Note that other apps on the same device can reach the local service on 127.0.0.1.

## 7. Autostart and launching other apps

1. The app does not start at boot and is not woken by other apps in the background. "Start the service when the app opens" applies only when you open the app yourself (the interface needs the service) and can be turned off on the Server page.
2. The app opens other apps or web pages only when you tap to do so.

## 8. Your rights

1. Access and correction: view and edit what you saved in the Sub-Store interface and the app settings at any time.
2. Deletion: delete items in Sub-Store, or use Settings › Data & privacy › Erase all data to delete all Sub-Store data at once; uninstalling the app deletes everything.
3. Withdrawing consent: Settings › Data & privacy › Withdraw consent stops the service and quits the app; you will be asked to consent again next time. Withdrawal does not affect processing done before it.
4. As we hold none of your information, there is no account to close.

## 9. Minors

The app is intended for adults aged 18 or over with full civil capacity and the ability to manage networks. **Minors under 18 must not download, install or use it.** The app collects no personal information and cannot tell a user's age. A guardian who finds a minor using it can have them erase the data and uninstall the app, or contact us by email.

## 10. Privacy-related disclaimers

1. **The app only processes, on this device, subscriptions and nodes you add yourself; it does not provide, review or store them on any server and is not responsible for their content.** You alone judge, and bear full responsibility for, whether their sources are lawful and authorised. You must obey the laws of the People's Republic of China and of where you are, including the Cybersecurity Law, the Data Security Law, the Personal Information Protection Law and the Interim Provisions on the Administration of International Networking of Computer Information Networks, and must not use the app to evade lawful network supervision or for any illegal activity.
2. **Scripts:** Sub-Store can run scripts you add (such as node operation scripts). They run on this device, can access the network, and may read, change or send your subscription content. Use only scripts you trust; you bear the consequences of what they do.
3. **Third-party services and apps:** subscription providers, node servers, script and rule providers, sync services, and the clients you import subscriptions into are provided or run independently by third parties under their own privacy policies, which we cannot control and are not responsible for.
4. **LAN service:** the service uses unencrypted HTTP and the backend has no login. You decide whether to turn on LAN access or the LAN web UI on a given network and whom to give subscription links; you bear any resulting disclosure.
5. **Data loss:** data stays only on your device and we cannot back it up or recover it. Uninstalling, erasing data, changing or resetting the device, or system faults may lose it permanently; back up regularly with Sub-Store's backup feature and keep backups safe. To the extent permitted by law, we are not liable for data loss or disclosure.
6. Nothing in this section excludes or limits liability that cannot be excluded or limited under applicable law.

## 11. Changes

When this policy changes we update it in the app and on the website with the new date and version; for material changes affecting your rights we will notify you in the app and ask for your consent again.

## 12. Contact

Developer: Zhang Shibo (individual developer)
Email: zhisibi@gmail.com

For any questions, comments or complaints about this policy or personal information protection, email us; we reply within 15 working days.
