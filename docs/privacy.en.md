# MimiSubStore Privacy Policy

Updated: 30 October 2026 (version 1)

Developer: Zhang Shibo ("we"). Contact: feedback QQ group 1127250124.

MimiSubStore ("the app") is a subscription management and format-conversion tool that runs entirely on your device. Its design principle is simple: **we collect no personal information, and your data stays on your device.** Please read this policy before use.

## 1. Information we collect

- **We collect no personal information.** No registration or account is required; we do not collect your name, phone number, device identifiers, location, usage behaviour or crash data, and the app contains no third-party analytics, advertising, push or crash-reporting SDKs.
- **Data you save:** subscriptions, collections, files, scripts, sync configurations and app settings you add are stored only in the app's private directory on your device. They are never uploaded to us and we cannot access them.
- **Run log:** access records (visitor IP, request path, User-Agent, status code) and run events are kept in memory only and cleared when the app exits; sensitive parameters (such as tokens inside subscription URLs) are redacted before being logged. The log leaves the app only when you explicitly tap "copy" or "save as file".

## 2. Network connections

The app connects only to the following, always triggered by your actions or configuration:

- Remote subscription, script, rule and sync-service addresses you added yourself;
- This project's GitHub repository (github.com, api.github.com and GitHub download hosts), only when you check or install Sub-Store / app updates, or when "check on launch" is on; depending on the download route you select, requests may pass through public accelerators such as ghfast.top or gh-proxy.com. These requests contain none of your subscription data, but those services process your IP address under their own policies;
- When you enable LAN access, the app serves subscription downloads on your local network, under your control.

## 3. Permissions

| Permission | Purpose | Can be turned off |
| --- | --- | --- |
| INTERNET | Fetching your remote subscriptions and checking for updates | In system settings (remote features then stop working) |
| GET_NETWORK_INFO | Showing this device's LAN addresses | In system settings |
| KEEP_BACKGROUND_RUNNING | Keeping the local service alive when you enable "keep running in background" | By turning that switch off in the app |

The app does not request camera, microphone, location, contacts, SMS or storage permissions. The clipboard is only written when you tap a copy button and is never read; files are picked and saved only through the system file picker.

## 4. Storage and security

- Data is stored in the app sandbox for as long as you keep it; uninstalling the app, or "Service → About → Delete all data", removes everything (deleting data also removes downloaded component updates).
- Please note: subscription content (including node credentials) is stored as app data without additional encryption — keep your device and backup files safe. The local service uses HTTP and the backend has no login; do not enable LAN access on untrusted networks.

## 5. Sharing with third parties

- We never sell, share or transfer your information to any third party, because we do not hold it.
- Exception: a sync service you configure yourself (such as GitHub Gist) is contacted directly by the Sub-Store backend under your configuration, and that service's own privacy policy applies.

## 6. Your rights

- You can view, edit, export or delete all of your data at any time in the app (Sub-Store backup/export, and "Delete all data").
- You can withdraw consent under "Service → About → Withdraw consent": the service stops and the app exits, and consent is asked again on the next launch. Deleting data is separate — use "Delete all data" or uninstall.
- Questions about this policy: use the contact above.

## 7. Minors

The app is intended for adults. Persons under 18 should not use it.

## 8. Changes

When this policy changes, the app will show it on launch and ask you to confirm again; the version and date at the top of this page will be updated.
