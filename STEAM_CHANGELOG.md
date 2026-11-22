[h1]Minidoracat Tesla Collection for B42 42.22.2-0.11.0[/h1]
[i]2026-11-22[/i]

[b]English summary[/b]
[list]
[*] New upgrades for all nine Teslas (not the 53 ft trailer): Vehicle Mechanics has a new Upgrades category with two slots, Protection and Fridge. Both start empty; craft the parts or find them as loot.
[*] Car Fridge: capacity 12, in the trunk (the bed on the Cybertruck, the cab on the Semi). Right-click the car or use the V radial menu to switch Cool, Freeze or Off. It runs on the high-voltage battery and turns itself off at 20%.
[*] Protection: the Reinforcement Kit about halves crash damage and cannot be seen; the Bull Bar Kit cuts it by about three quarters and adds a steel bull bar, shaped for each car.
[*] The Semi's 53 ft trailer now holds 1000 instead of 300, trailers already on your map included. A full trailer is slower and harder to stop.
[*] The Cybertruck no longer rolls over when you steer hard above 100 km/h. The bumper headlights on the Model Y and Model Y L now light up.
[*] Vehicle Mechanics fixes: it opens with the key card in a bag, it no longer closes itself on the 53 ft trailer, and on servers with VehicleManager the hood and the drive unit now follow its permissions.
[/list]

[h3]✨ 新增[/h3]
[list]
[*] [b]升級件[/b]：九台特斯拉的維修介面最下面多一個「升級件」分類，有「防護件」與「車用冰箱」兩個位置（53 呎拖車沒有）。新車和舊存檔裡的車都是空的，要自己做或從戰利品找。裝拆防護件要扳手或棘輪扳手，車用冰箱不用工具，都不看技工等級。
[*] [b]車用冰箱[/b]：容量 12，裝在行李廂（Cybertruck 在車斗，Semi 在駕駛室）。在車外對車按右鍵選「車用冰箱」，或坐在車上按 V 鍵圓盤，切換「冷藏」「冷凍」「關閉」。冷藏時食物壞得和家裡通電的冰箱一樣慢；冷凍約 4 到 4.5 小時結凍，結凍後不會壞。食物要直接放進冰箱，袋子裡的不算。
[*] [b]冰箱用車上的電[/b]：開著時遊戲一天約用 1.4 kWh，插著有電的充電線時不扣車上的電。電量低於 20% 會自動關閉並通知你；哨兵模式也開著時，兩者合計把電用到 20% 就一起關閉。拆卸前要先清空。
[*] [b]防護件[/b]：車身補強套件外觀看不出來，撞車的車損約減半；防撞桿套件在車外看得到鋼管防撞桿（九台各有自己的造型），車損約減少四分之三，但很重。兩種擇一。殭屍也比較難打破車窗；已經破掉的車窗和車燈不會復原。
[*] [b]配方與戰利品[/b]：製作車身補強套件（金工 3 級）、防撞桿套件（金工 5 級）、車用冰箱（電工 4 級，要一個空的手提保溫箱），等級到了自動學會。兩種套件也會出現在修車廠、五金行與車庫，車用冰箱會出現在露營用品店、汽車用品店與電器行。
[/list]

[h3]🔄 變更[/h3]
[list]
[*] [b]Semi 的 53 呎拖車貨艙從 300 加大到 1000[/b]：已經在地圖上的拖車讀檔後也會變成 1000，裡面的貨不受影響；多人伺服器更新後重啟即可。裝得越滿越難開：加速變慢、煞車距離變長。載到 1000 上下時，急煞前先把車頭擺正，不然拖車會往旁邊摺；摺到底不會脫鉤，方向盤回正往前開一小段就能拉直。
[/list]

[h3]🔧 修正[/h3]
[list]
[*] [b]Cybertruck 高速急打方向盤會翻車[/b]：時速 100 以上急打方向盤很容易翻車。現在降低了重心，同樣的操作車身只會稍微傾斜；加速、極速與外觀不變。時速 120 連續變換車道仍可能把車甩到打轉（Model Y 和原版車也一樣），但實測沒有再翻車。
[*] [b]Model Y、Model Y L 保桿上的主頭燈不亮[/b]：原本開大燈只有前蓋邊緣的燈條亮，現在保桿兩側的主頭燈也會亮。
[*] [b]卡片鑰匙放在皮包或袋子裡時，「車輛資訊」按了沒反應[/b]：車鎖著時，角色走到車頭就停下，視窗沒打開，要鑰匙的零件也裝拆不了。現在卡片鑰匙放在皮包、背包裡也能打開「車輛資訊」、裝拆這些零件，多人伺服器也一樣。
[*] [b]沒有鑰匙時按「車輛資訊」會說明原因[/b]：以前角色走到車頭就停下、什麼也沒說；現在頭上會顯示「前蓋已上鎖」。
[*] [b]Semi 的 53 呎拖車「車輛資訊」一打開就自己關掉[/b]：現在角色會走到拖車側邊靠後輪的位置，視窗不會再自己關掉，最後一軸的輪胎也能拆裝。
[*] [b]搭配 VehicleManager 的伺服器[/b]：只有「搭乘」權限的人按「車輛資訊」，不會再把前蓋留成沒鎖；有「安裝修理」權限的人在虛擬鑰匙開著（預設）時打得開「車輛資訊」。修理驅動單元要有「安裝修理」、拆取驅動單元零件要有「拆零件」權限，以前不看權限。
[/list]
