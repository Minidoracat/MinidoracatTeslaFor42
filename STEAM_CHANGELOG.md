[h1]Minidoracat Tesla Collection for B42 42.22.2-0.10.0[/h1]
[i]2026-11-21[/i]

[b]English summary[/b]
[list]
[*] New vehicle: the Tesla Semi (Long Range) and a 53 ft dry van trailer, white only. Each parks on its own in long parking lots; the new sandbox option Semi and trailer spawn chance sets how often (default 1.5%, 0 for none).
[*] It drives like a truck: about 18.5 seconds to 100 km/h on its own, about 25 with an empty trailer, about 105 km/h flat out. 822 kWh battery; a V4 Supercharger gives it up to 1,200 kW, 10% to 90% in about 80 minutes.
[*] Hitching: the 53 ft trailer only hitches to a Semi. Back up to it, stand beside the fifth wheel, press V and pick Attach … to …; at a standstill the driver's seat has it too. Trailer cargo is 300.
[*] Sentry Mode now watches a towed trailer: a stranger unhitching it or taking it away flashes the lights and tells the owner who.
[*] Multiplayer towing fixes for every Tesla with any trailer: the car not moving right after hitching, the trailer dropping when the driver reconnects, a set stuck with a player who disconnected just after hitching, and a player walking up during a hitch seeing the trailer unhitched.
[*] Looks: the Cybercab's panel gaps, wordmark and light bar no longer break into dotted lines; opened doors on the other seven cars show body colour on their edges; tall hats hide correctly when seated.
[/list]

[h3]✨ 新增[/h3]
[list]
[*] [b]第九台特斯拉：Tesla Semi[/b]：電動半掛卡車，照 2026 年量產的 Semi Long Range 做，只有白色。Semi 與 53 呎拖車各自停在夠長的停車場，不會掛在一起；沙盒新選項「Semi 與拖車生成機率」（預設 1.5%，0＝不生成），舊存檔探索過的地方也會補一次。
[*] [b]開起來像卡車[/b]：0 到 100 km/h 單車頭約 18.5 秒、掛空拖車約 25 秒，最高約 105 km/h；官方沒有公布極速，這是遊戲裡定的手感。
[*] [b]駕駛座在正中間[/b]：兩扇車門、兩個座位，右後方一張折疊座。沒有前車廂、後行李廂和手套箱，新車附贈的手機放在駕駛座、行動充電器放在折疊座。
[*] [b]電池與充電[/b]：822 kWh，全車系最大。V4 超級充電座對 Semi 最高 1,200 kW，10% 到 90% 約 80 分鐘；壁掛式與行動充電器也能充，但要充很久。充電口在車身左側、駕駛艙後方下面。
[*] [b]53 呎廂式半拖車[/b]：白色，照 Tesla 官網主圖裡那台做，貨艙容量 300（原版拖車 100）。只能掛在 Semi 後面，Semi 也拖不了原版拖車和別的車。
[*] [b]掛接與卸下[/b]：把 Semi 倒到拖車前、鞍座對準拖車前端，站在鞍座旁按 V 鍵，圓盤選「將…連結至…」；車停穩時坐在駕駛座也能掛接與卸下。卸下選「分離…」。
[*] [b]儀表與 App[/b]：儀表有 Semi 自己的車子圖，掛著拖車時後面畫出拖車；App 首頁是上鎖與充電，控制頁是閃燈與鳴喇叭。卡片鑰匙、手機鑰匙、哨兵、露營、舒適模式都和別台特斯拉一樣；沒有生物武器防禦模式。
[/list]

[h3]🔄 變更[/h3]
[list]
[*] [b]哨兵模式顧到拖車[/b]：開著哨兵的特斯拉，被陌生人卸下拖車或被別台車把拖車掛走時，會閃燈並通知車主是誰（不響警報）；陌生人拆拖車上的零件會響警報。九台車拖任何拖車都適用。
[/list]

[h3]🔧 修正[/h3]
[list]
[*] [b]多人伺服器掛上拖車後馬上上車發動，車開不動[/b]：以前要熄火再發動。現在特斯拉會自己恢復，最多等遊戲一分鐘。
[*] [b]多人伺服器開車拖著拖車時斷線，連回來拖車掉了[/b]：0.1.0 起就有，Semi 拖車折得很彎時最常發生。現在重新連線後拖車會好好掛著。
[*] [b]多人伺服器有人掛上拖車後馬上斷線，別人開不走那組車[/b]：以前要等他連回來。現在有玩家加入伺服器時會恢復，有人發動那台特斯拉時最多等遊戲一分鐘就能開。
[*] [b]多人伺服器有人掛上拖車時，剛走近的玩家看到拖車沒掛上[/b]：以前要走遠再回來或自己坐上駕駛座才恢復。現在拖車在你的畫面上出現時就會補掛上。
[*] [b]坐在特斯拉上時帽子藏錯[/b]：有些高帽子穿出車頂，有些不會穿出的帽子卻被藏起來。現在照各車的車內重新算過。
[*] [b]Cybercab 的板縫、字樣與燈條斷成點線[/b]：拉近斜看時，車頂後緣、前蓋與車門的板縫、Cybercab 字樣的細筆畫、車頭燈條兩端都斷斷續續。現在都是連續的線。
[*] [b]Cybercab 打開車門時的雜點[/b]：門板厚度那一面的深色短虛線與亮金點、A 柱旁邊的白條、擋風玻璃下緣兩角的淺藍小三角都沒有了。
[*] [b]其他七台打開車門時門邊有一段深色[/b]：現在開門才看得到的門邊改成車身顏色，關門的外觀不變。
[/list]

[h3]• 已知限制[/h3]
[list]
[*] [b]多人伺服器開不到 Semi 的最高速[/b]：伺服器設定 SpeedLimit 預設 70，掛空拖車最高約 65 km/h；原版車與其他特斯拉一樣受這個限制。
[*] [b]撞到障礙物時拖車可能脫鉤[/b]：拖著拖車撞上路障這類東西的那一刻，拖車可能脫開，要重新掛接。
[*] [b]高速急煞時拖車會甩[/b]：拖車裝了貨、從最高速全力煞車時偶爾甩歪，不會脫鉤或翻車。
[*] [b]拖車的尾燈不會亮[/b]：開大燈時拖車後面的燈不亮，只有煞車燈跟著車頭亮；原版拖車也是這樣。
[/list]
