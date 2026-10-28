# Minidoracat Tesla Collection

特斯拉電動車與充電設備：用電池行駛、在充電座充電，附特斯拉風格儀表、哨兵與露營模式

Project Zomboid Build 42 MOD。

## 功能

-

## 多人身分的限制

- 哨兵、露營的車主通知與離線通知以帳號名認人。Steam 伺服器上，帳號名在角色建立或上線後一遊戲分鐘內綁定那位玩家的 Steam 帳號，之後別的 Steam 帳號用同一個名字收不到通知；no-steam 伺服器沒有可以比對的帳號，無法防止冒名。
- 分割畫面的第二～四位玩家不算任何帳號（帶著鑰匙時照常能用車）。
- 還沒綁定的名字，改過的客戶端有機會搶先綁定。搶到的名字底下沒有特斯拉的通知可拿，但那位玩家之後收不到通知；本 MOD 沒有管理員改綁的功能。
- 名字還沒綁定、底下卻已經存著離線通知的玩家（例如伺服器先以 no-steam 開過再改成 Steam），要建立新角色才會綁定；在那之前他完全收不到特斯拉通知，自己開的哨兵、露營也不算車主開的。
- Steam 好友連線（由玩家主持的合作遊戲）的登入名就是 Steam 顯示名稱，遊戲不驗證：還沒綁定的名字，誰先用它加入就綁給誰。
- 遊戲本身登入流程的已知問題（需要改過遊戲程式的客戶端）也可能讓還沒綁定的名字被綁走；已綁定的名字不受影響。

## 安裝

- Steam Workshop：（首次上傳後補上連結）
- 手動安裝：把 `MOD/MinidoracatTeslaFor42/Contents/mods/MinidoracatTeslaFor42` 複製到 `%USERPROFILE%\Zomboid\mods\` 並將資料夾改名為 `MinidoracatTeslaFor42`

## 開發

- `link_workshop.bat`：手動同步、唯讀狀態與歸檔卸載；MOD 以實體副本放入 `Zomboid\Workshop\` 與 `Zomboid\mods\`，不使用目錄連結
- `PZ_Test.bat`：暗色點選視窗，啟動前增量同步目前 MOD 與家族依賴；首次預設 no-Steam，之後記住各專案的選擇。需要換檔但遊戲仍在執行時拒絕同步與新啟動，不停止既有遊戲；完整驗證與資料邊界見 `../pz-family-docs/tools.md`
- `Publish_Workshop.bat`：發布到 Steam Workshop（需 Steam 用戶端已登入；可選擇只更新內容／封面／簡介；首發仍走遊戲內上傳器）

## 版本

版本號格式：`{PZ 版本}-{mod 版本}`（例 `42.21.0-0.1.0`），詳見 [CHANGELOG.md](CHANGELOG.md)。

## 作者

Minidoracat — [Discord](https://discord.gg/Gur2V67) | [Twitch](https://www.twitch.tv/minidoracat)
