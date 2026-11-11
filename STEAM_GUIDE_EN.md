<!-- 指南網址：https://steamcommunity.com/sharedfiles/filedetails/?id=3829449879 -->
<!-- Steam guide source (English). The full description lives in this guide; the Workshop page only has a summary. Format and sync: pz-family-docs/release.md "完整說明：Steam 指南" -->
<!-- 標題：📖 Minidoracat Tesla Collection Mod Guide: Cars, Charging, Keys and the App -->
<!-- 摘要：A picture guide to Minidoracat Tesla Collection: the Model Y and Model 3 Performance, the Model Y L (six seats), the Model S and Model X Plaid (falcon wing doors and six seats), the Cybertruck Cyberbeast (cargo bed, Powershare home backup and the bed outlets), the battery and towing, the Wall Connector, the Mobile Connector and the V4 Superchargers at gas stations, the Tesla-style dashboard, key cards and phone keys, the Tesla app and Summon, Sentry and Camp Mode, Bioweapon Defense Mode and Chill, drive unit parts, and how it works with Vehicle Manager, the MiniMap, AutoDrive and Project Viewpoint, plus the sandbox options. -->
<!-- Screenshots: docs/screenshots/steam/en/, shot by guide-shots-sp in the family repo's e2e/MinidoracatTeslaFor42 (Bioweapon Defense and Chill only: --define part=feat, with hover.py for the radial's hover text; Cybertruck shots: guide-ct-sp; Model S / X: guide-sx-sp; Model Y L shots (33, 34): guide-yl-sp; Summon shots: phone-summon-sp; FSD: fsd-shot-sp; With other mods: guide-mods-sp; Project Viewpoint (31): vd-first-ModelS from this repo's one-off temp/oneoff/vp-detail-sp, cropped (80,40,1660,1080), same picture as zh, needs ZombieBuddy; V4 Supercharger (32): supercharger-sp's sc-EN-card / sc-CH-card, cropped (480,160,1480,990)) -->
=== 🚀 Quick start
[b]中文版：[/b] [url=https://steamcommunity.com/sharedfiles/filedetails/?id=3829449828]Minidoracat Tesla Collection 完整說明[/url]

Mod page (Steam Workshop):
https://steamcommunity.com/sharedfiles/filedetails/?id=3829501237
[olist]
[*] [b]Find a car[/b]: the Model Y and Model 3 park in parking lots, and the Model Y also turns up in upscale neighbourhoods; the Model Y L turns up in both, at the Model Y's chance; the Model S, Model X and Cybertruck only turn up in upscale neighbourhoods.
[*] [b]Get the key[/b]: a Tesla's car key turns into that car's Key Card when you pick it up.
[*] [b]Start it[/b]: sit in the driver's seat and click the power button at the top left of the dashboard (or start it the vanilla way).
[*] [b]Charge it[/b]: with Electrical 3, make a Tesla Wall Connector (Gen 3) and mount it on a powered wall, or set a Tesla Mobile Connector (Gen 3) on the floor; right-click it to plug in the charge cable. The Tesla V4 Superchargers next to gas stations fast-charge as soon as you plug in.
[*] [b]Phone key[/b]: sit in the car with the key card, right-click a Smartphone and choose Set Up as Phone Key; then right-click the phone key and choose Open Tesla App.
[/olist]
[list]
[*] [b]Optional mods[/b]:
[list]
[*] [url=https://steamcommunity.com/sharedfiles/filedetails/?id=3813972279]Minidoracat Vehicle Manager[/url]: vehicle claims; the Tesla keys, the app and Sentry follow its permissions
[*] [url=https://steamcommunity.com/sharedfiles/filedetails/?id=3792675881]Minidoracat MiniMap - AutoDrive[/url]: Summon in the app
[*] [url=https://steamcommunity.com/sharedfiles/filedetails/?id=3763913359]Minidoracat MiniMap[/url]: your Teslas on the minimap, navigate to your car
[*] [url=https://steamcommunity.com/sharedfiles/filedetails/?id=3809306528]Project Viewpoint[/url]: a 3D view; sitting in a Tesla shows the cabin details
[/list]
[*] [b]Singleplayer and multiplayer[/b]: both work; in multiplayer the server must enable this mod, and the server makes every decision.
[/list]
=== 🧰 The cars: Model Y and Model 3 Performance
{{img:01-cars-en.jpg}}
[list]
[*] [b]Top trims only[/b]: both are the Performance version; power, battery, badges and looks follow Tesla's own data.
[*] [b]Where they spawn[/b]: parking lots, both at the same chance; upscale neighbourhoods have the Model Y but not the Model 3.
[*] [b]Factory paints[/b]: 8 per car, one picked at random; the app's picture of the car follows the paint.
[*] [b]Performance[/b]: acceleration and top speed match the fastest vanilla sports car, grip and braking too; a full stop from 100 km/h takes about 27 tiles.
[*] [b]Real opening doors[/b]: the four doors, the liftgate (the trunk lid on the Model 3) and the hood open the way the real car's do, and other players see it.
[*] [b]See inside[/b]: the windows are clear glass: seats, dashboard and the people inside show; the glass still cracks and breaks.
[*] [b]Sound[/b]: Tesla's own recordings of the motor, the low-speed pedestrian warning and the reverse chime; much quieter than a vanilla car, so zombies hear it from much closer.
[/list]
[table]
[tr][th]Car[/th][th]Factory paints[/th][th]Front Trunk[/th][th]Rear Trunk[/th][/tr]
[tr][td]Model Y Performance[/td][td]Stealth Grey, Pearl White, Diamond Black, Quicksilver, Ultra Red, Glacier Blue, Marine Blue, Frost Blue[/td][td]12[/td][td]85[/td][/tr]
[tr][td]Model 3 Performance[/td][td]Stealth Grey, Pearl White, Diamond Black, Quicksilver, Ultra Red, Deep Blue, Marine Blue, Frost Blue[/td][td]7[/td][td]45[/td][/tr]
[/table]
[list]
[*] [b]EV parts[/b]: the mechanics window uses Tesla's part names: High Voltage Battery, Drive Unit, Low Voltage Battery, Hood, Front Trunk, Rear Trunk.
[*] [b]Front Trunk[/b]: open the hood first to reach what is inside. With the hood open, press E at the front of the car to close it.
[*] [b]High Voltage Battery[/b]: comes out without draining it first; the charge stays in the battery, and the Capacity shown on a removed battery is that charge in kWh, not wear. It cannot be repaired or crafted: its condition does not affect range, charging or starting, and you can only get one by taking it out of a Tesla; it fits only the same model.
[*] [b]Brakes[/b]: regenerative braking halves brake wear compared with a normal car.
[/list]
=== 🧰 Model S and Model X (Plaid)
{{img:27-sx-en.jpg}}
[list]
[*] [b]Top trim before the end of production[/b]: both are the Plaid, built to Tesla's last official specs and owner's manuals; the mechanics window shows 1,020 hp.
[*] [b]Where they spawn[/b]: upscale neighbourhoods only, at the Cybertruck's chance there (half the Model Y's); never in parking lots.
[*] [b]Performance[/b]: they pull harder than the Cybertruck, and the Model S has the quickest launch of them all; the heavier Model X launches a little slower than the Model S. Top speed, grip and braking match the other Teslas.
[*] [b]Battery[/b]: a 100 kWh High Voltage Battery; a full charge still goes as far as a full tank in a vanilla car of the same class. Empty to 90% takes about 8 hours on a Wall Connector and about 12 on a Mobile Connector (game time).
[*] [b]Paints[/b]: 8 per car, one picked at random: the last 6 US paints, plus Solid Black and Deep Blue from the Chinese market before the refresh; the app's picture of the car follows the paint.
[*] [b]Model S doors[/b]: the four doors, the powered liftgate that lifts with the rear glass (about 4 seconds) and the hood open the way the real car's do.
[*] [b]Seats[/b]: 4 in the Model S (the real car has 5; like every Tesla here, one per door); 6 in the Model X, see below.
[*] [b]Dashboard[/b]: each has its own top view, and clicking the car still opens its doors.
[*] [b]Towing[/b]: like every Tesla here, they tow trailers or other cars with the vanilla tow hitch (for the charge it uses, see Battery and range).
[/list]
[table]
[tr][th]Car[/th][th]Factory paints[/th][th]Front Trunk[/th][th]Rear Trunk[/th][/tr]
[tr][td]Model S Plaid[/td][td]Stealth Grey, Lunar Silver, Pearl White, Ultra Red, Diamond Black, Frost Blue, Solid Black, Deep Blue[/td][td]6[/td][td]45[/td][/tr]
[tr][td]Model X Plaid[/td][td]Stealth Grey, Lunar Silver, Pearl White, Ultra Red, Diamond Black, Frost Blue, Solid Black, Deep Blue[/td][td]17[/td][td]85[/td][/tr]
[/table]
[h3]Model X falcon wing doors and six seats[/h3]
{{img:28-mx-falcon-en.jpg}}
[list]
[*] [b]Falcon wing doors[/b]: the rear doors lift up: the upper half swings up from the roof and the lower half folds out at the elbow; fully open they still fit in a one-storey garage.
[*] [b]Opening them[/b]: click the rear half of the car on the dashboard to open or close that side's falcon wing door; Falcon Wing Doors on the app's Controls page opens or closes both at once.
[*] [b]Open means open[/b]: anyone can get in while they are open, so close them before you leave.
[*] [b]Locking[/b]: locking the car locks the falcon wing doors too.
[*] [b]Six seats[/b]: 2 in front, 2 captain's chairs in the second row, 2 in the third; both rear rows get in and out through the falcon wing doors.
[*] [b]Third row[/b]: it has its own boarding spot, so you can still get in when the second row is full.
[*] [b]Interact key[/b]: at a falcon wing door the interact key (keyboard or controller) takes the second row first, the third once the second row is taken; to pick a seat, use the seat panel.
[*] [b]Waiting for the door[/b]: a falcon wing door takes a moment to rise, and your character waits for it before climbing in.
[*] [b]Part names[/b]: the mechanics window uses the owner's manual names Left Falcon Wing Door and Right Falcon Wing Door.
[/list]
=== 🧰 Model Y L
{{img:33-modelyl-en.jpg}}
[list]
[*] [b]One version only[/b]: every Model Y L in the world is the same long-range, all-wheel-drive six-seater, built to the current China version (after the October 2026 refresh); there is no Performance. The mechanics window shows 502 hp (176 kW front plus 198 kW rear).
[*] [b]Where it spawns[/b]: parking lots and upscale neighbourhoods, at the same chance as the Model Y.
[*] [b]Performance[/b]: a little heavier than the Model Y and with less thrust, it launches slower than the Model Y; top speed, grip and braking match the other Teslas.
[*] [b]Battery[/b]: an 82 kWh High Voltage Battery (Tesla does not publish it; the figure comes from China's MIIT filing); a full charge still goes as far as a full tank in a vanilla car of the same class. Empty to 90% takes about 6 hours on a Wall Connector and about 10 on a Mobile Connector (game time); a Supercharger gives up to 250 kW and takes about 38 minutes from 10% to 90%.
[*] [b]Paints[/b]: 7, one picked at random; Cosmic Silver is exclusive to the Model Y L. The app's picture of the car follows the paint, and the app calls it Model Y L.
[*] [b]Doors[/b]: four ordinary doors (no falcon wing doors), the powered liftgate and the hood open the way the real car's do.
[*] [b]Looks[/b]: about 18 cm longer than the Model Y with a wheelbase 15 cm longer and a higher rear roofline; 19" Machina 2.0 wheels, a black extended rear spoiler, and MODEL Y with three slashes on the tailgate.
[*] [b]Charge port[/b]: in the left tail lamp, like the Model Y.
[*] [b]Bioweapon Defense Mode[/b]: it has a HEPA filter; see Bioweapon Defense Mode and Chill.
[*] [b]Dashboard[/b]: it has its own top view, and clicking the car still opens its doors.
[*] [b]Towing[/b]: like every Tesla here, it tows trailers or other cars with the vanilla tow hitch (for the charge it uses, see Battery and range).
[*] [b]Everything else[/b]: key card, phone key, the app, Sentry, Camp Mode, Chill and Summon work as on the other Teslas.
[/list]
[table]
[tr][th]Car[/th][th]Factory paints[/th][th]Front Trunk[/th][th]Rear Trunk[/th][/tr]
[tr][td]Model Y L[/td][td]Stealth Grey, Pearl White, Diamond Black, Ultra Red, Cosmic Silver, Glacier Blue, Marine Blue[/td][td]12[/td][td]85[/td][/tr]
[/table]
[h3]Model Y L six seats[/h3]
{{img:34-modelyl-seats-en.jpg}}
[list]
[*] [b]Six seats[/b]: 2 in front, 2 captain's chairs in the second row (with an aisle between them), 2 in the third.
[*] [b]Getting into the third row[/b]: through the rear doors; it has its own boarding spot, so you can still get in when the second row is full.
[*] [b]Interact key[/b]: at a rear door the interact key (keyboard or controller) takes a free second-row seat first, the third row once the second row is taken; to pick a seat, use the seat panel, where you can click a third-row seat directly.
[/list]
=== 🧰 Cybertruck (Cyberbeast)
{{img:23-cybertruck-en.jpg}}
[list]
[*] [b]Where it spawns[/b]: upscale neighbourhoods only, at half the Model Y's chance there; never in parking lots.
[*] [b]Top trim Cyberbeast[/b]: the mechanics window shows 845 hp, and it pulls harder than the Model Y and Model 3; top speed, grip and braking match the two cars.
[*] [b]Off road[/b]: on grass, dirt and other off-road ground it has more thrust and wears its tyres and suspension less, like the vanilla off-road vehicles.
[*] [b]Battery[/b]: a 123 kWh High Voltage Battery; a full charge still goes as far as a full tank in a vanilla car of the same class. Empty to 90% takes about 10 hours on a Wall Connector and about 15 on a Mobile Connector (game time); filling it on generator power burns about 1.6 times the Model Y's fuel.
[*] [b]Seats[/b]: 4 (the real truck has 5; like every Tesla here, one per door).
[*] [b]Charge port[/b]: above the left rear wheel; the charge cable runs there.
[*] [b]Paints[/b]: half spawn in factory stainless, the other half evenly in 11 wraps Tesla once sold; stainless and the satin wraps each have their own sheen, and the app's picture follows the paint.
[/list]
[table]
[tr][th]Car[/th][th]Paints[/th][th]Front Trunk[/th][th]Cargo Bed[/th][/tr]
[tr][td]Cybertruck Cyberbeast[/td][td]Stainless, Satin Stealth Black, Satin Ceramic White, Satin Rose Gold, Satin Tactical Green, Satin Dark Grey, Satin Forest Green, Satin Abyss Blue, Copper Tinted Clear, Satin Crimson Red, Satin Iridescent Purple, Slip Grey[/td][td]14[/td][td]110[/td][/tr]
[/table]
[h3]Cargo bed, tailgate and tonneau cover[/h3]
{{img:24-ct-bed-en.jpg}}
[list]
[*] [b]Capacity[/b]: Cargo Bed 110 (same as the vanilla pickup), Front Trunk 14.
[*] [b]Tailgate[/b]: folds down; use the interact key at the rear, click the rear of the car on the dashboard, or the tailgate icon on the app's home page.
[*] [b]Tonneau Cover[/b]: a powered roll-up cover, about 4 seconds to open or close; click the bed on the dashboard's car picture, or Tonneau Cover on the app's Controls page.
[*] [b]Reaching the bed[/b]: from the rear the tailgate or the tonneau must be open, from the sides the tonneau; not from inside the truck. A removed tailgate or tonneau counts as open.
[*] [b]Locking[/b]: locking the truck locks the tailgate and the tonneau too; a tonneau left open stays open when locked (like the real truck).
[*] [b]Part names[/b]: the mechanics window uses the owner's manual names Tailgate, Cargo Bed and Tonneau Cover.
[/list]
[h3]Bed lights and roof light bar[/h3]
[list]
[*] [b]Bed lights[/b]: on by themselves while the tailgate or the tonneau is open, off when both are shut.
[*] [b]Roof light bar[/b]: every Cybertruck has one; the driver picks Turn on Light Bar in the V radial menu. It lights the ground ahead, farther than the headlights.
[/list]
[h3]Armor Glass and the stainless body[/h3]
[list]
[*] [b]Windows[/b]: smashing a window from outside (Smash … in the V radial menu, or Smash Window in the mechanics window) takes 3 hits, with a heavy two-handed swing; a new window starts over, and bare hands still cut.
[*] [b]Sentry[/b]: with Sentry on, every hit sounds the alarm and tells the owner; see Sentry Mode.
[*] [b]Body[/b]: player weapons do less to the doors, hood, tailgate, tonneau and windshields than on a normal car; crashes and zombies do the usual damage.
[/list]
=== 🧰 Battery and range
[list]
[*] [b]Charge is fuel[/b]: the High Voltage Battery replaces petrol; driving uses charge and braking wins some back.
[*] [b]Range[/b]: a full battery goes as far as a full tank in a vanilla car of the same class; the sandbox option Range multiplier changes it, and it follows the vanilla sandbox option Gas Consumption too (2 = half as far, 0 = driving uses no charge and the dashboard shows ∞ range).
[*] [b]Out of charge[/b]: the motor stops and will not start until you charge.
[*] [b]Low Voltage Battery[/b]: the main battery tops it up while it holds 5% or more, so a car parked for a long time still starts.
[*] [b]Power in the car[/b]: climate, Bioweapon Defense Mode, Camp Mode and Sentry Mode use the main battery too; plugged into a powered charger, the charger supplies them instead, and on generator power that burns the generator's fuel.
[*] [b]Towing uses more[/b]: towing a trailer or another car, driving uses more charge for the weight behind you: about 1.5 times with a small trailer, about 3 times with an ordinary car (3 times at most), more with cargo in the trailer; standing still uses the same as before. The range on the dashboard and in the app drops to match, and you cannot Summon while towing.
[*] [b]Multiplayer speed limit[/b]: the server setting SpeedLimit defaults to 70 km/h; neither vanilla cars nor Teslas go faster.
[/list]
=== 🧰 Charging: the Wall Connector, the Mobile Connector and the cable
{{img:02-cable-en.jpg}}
[h3]Make a charger[/h3]
You learn the recipe automatically at Electrical 3; craft it next to a work surface such as a table.
[table]
[tr][th]Recipe[/th][th]Tools (kept)[/th][th]Materials[/th][th]Makes[/th][/tr]
[tr][td]Make Tesla Wall Connector[/td][td]Screwdriver, Pliers[/td][td]Electrical Wire 4, Scrap Electronics 3, Steel Sheet - Small 2, Screws 4[/td][td]Tesla Wall Connector (Gen 3) 1[/td][/tr]
[/table]
[list]
[*] [b]Mount it[/b]: place it like vanilla furniture, with Electrical 3 and a screwdriver in hand; picking it up needs the same. One charger a square (Wall Connector or Mobile Connector).
[*] [b]Grid power[/b]: the charger uses the grid when its square or a square next to it is inside a house (the same rule as a vanilla fridge); houses players build do not count.
[*] [b]Generator[/b]: after the power goes out it runs on a running generator nearby (the vanilla generator range). Generator power always burns that generator's fuel, the car's climate and Camp Mode while plugged in included: by default about one tank for a full charge, scaled by the sandbox options Charging fuel multiplier and Generator Fuel Consumption. Grid power is free.
[/list]
[h3]Mobile Connector[/h3]
A charger that works on the floor, no wall needed; slower than the Wall Connector.
{{img:15-mobile-gen-en.jpg}}
[table]
[tr][th]Recipe[/th][th]Tools (kept)[/th][th]Materials[/th][th]Result[/th][/tr]
[tr][td]Make Tesla Mobile Connector[/td][td]Screwdriver[/td][td]Car Battery Charger 1, Electrical Wire 3, Scrap Electronics 1[/td][td]Tesla Mobile Connector (Gen 3) 1[/td][/tr]
[/table]
[list]
[*] [b]Getting one[/b]: Electrical 2 learns the recipe (made next to a work surface); it also turns up on the shelves that stock car battery chargers (car supply stores, garages, gas stations and so on; not in other vehicles' trunks) at about half their chance (both are Mechanics loot); a newly spawned Tesla has a one-in-four chance of one in its Rear Trunk.
[*] [b]On the floor[/b]: place it like vanilla furniture; you place and pick it up with bare hands, no tool or skill needed.
[*] [b]Power[/b]: indoors where there is power (the grid, or a building in a generator's range; a roofed player-built base counts as indoors, though player-built houses get no grid) it works like the Wall Connector: grid first, then after the power cut the fuel of the generator powering it. Anywhere else it must sit within 2 tiles of a running, fuelled generator (same floor, diagonals count): it is plugged straight into that generator and burns its fuel, even when the server turns off the sandbox option Generator Working in Exterior. Outdoors in a generator's range with no generator next to it there is no power: the cable still plugs in but nothing charges, and right-clicking the charger shows a grey line saying so. Generator power burns fuel the same way indoors or plugged straight in: a full charge takes about one tank; it charges slower, so per hour it burns about 2/3 of what the Wall Connector does.
[/list]
{{img:03-charger-menu-en.jpg}}
[h3]Plug in and charge[/h3]
[list]
[*] [b]Plug in[/b]: stand at the charger, right-click it and choose Plug in charge cable: <car>; every Tesla the cable reaches is listed (cable length: about 6 tiles for the Wall Connector, 5 for the Mobile Connector, 2.5 for the Supercharger).
[*] [b]Who can plug in or unplug[/b]: anyone with this car's key, anyone once the car is hotwired, or anyone while the car is unlocked; locked and no key, the rows are grey (see the FAQ What can I do without the key?).
[*] [b]Motor on is fine[/b]: the car only has to stand still; you can also start it while plugged in.
[*] [b]No driving off plugged in[/b]: throttle or reverse says Unplug the charge cable first and the dashboard shows P; unplug and drive away.
[*] [b]Auto unplug[/b]: towed or pushed past the cable's reach, the car is unplugged and you are told.
[*] [b]Charging speed[/b]: 11.5 kW at the Wall Connector, 7.6 kW at the Mobile Connector; a Model Y or Model 3 takes about 6 and 9 in-game hours from empty to 90%, and cars with a bigger battery take longer in proportion; the sandbox option Charging speed multiplier changes it. A Supercharger is far faster, see V4 Supercharger.
[*] [b]Time skips count[/b]: charge is settled by the hours that passed, so sleeping or fast-forwarding loses nothing.
[*] [b]Other players see the cable[/b]: it hangs from the Wall Connector or the Supercharger to the ground (it leaves the Mobile Connector right on the ground) and runs to the car's charge port.
[*] [b]The holster[/b]: with no car plugged in, the Wall Connector's and the Supercharger's connector sits in its holster with the cable hung up; once a car is plugged in, the holster is empty. Other players see the same.
[/list]
{{img:04-charging-en.jpg}}
[h3]The charge card[/h3]
[list]
[*] [b]Open it[/b]: in the car press V and choose Charging Status, or right-click the charger and choose the same.
[*] [b]Shows[/b]: power, what this session added (km, kWh), time to the target, and what powers it: the grid, a generator, Powershare or a Cybertruck bed outlet. At a Supercharger the title says Supercharging and the power keeps changing with the charge.
[*] [b]Target[/b]: − / + move it 10% at a time, 50–100%; Daily is 50–90%, Trip 90–100%.
[*] [b]Buttons[/b]: stop / start charging, unplug, close; a controller works too. Without the right (car locked, no key) the target and these buttons are grey and the hover help says why.
[/list]
=== 🧰 V4 Supercharger
{{img:32-supercharger-en.jpg}}
[list]
[*] [b]Where[/b]: 2 to 4 Tesla V4 Superchargers stand next to gas stations, each with its parking spot in front. If you add the mod mid-save, the gas stations you already visited get theirs the next time they load; each station gets them only once, and posts taken away do not come back. They only go on empty pavement (gravel floors players lay count too), never on furniture or cars; on a multiplayer server none appear inside a safehouse.
[*] [b]Make one[/b]: Electrical 6 learns the recipe Make Tesla V4 Supercharger; craft it next to a work surface such as a table with a Screwdriver and Pliers (kept), Electrical Wire 12, Scrap Electronics 9, Steel Sheet - Small 6 and Screws 12.
[*] [b]Plug in[/b]: right-click it and plug in the charge cable like any charger. The cable reaches about 2.5 tiles (3 m in the real world), so park in the spot in front of the post.
[*] [b]Slower as it fills[/b]: it follows the real cars' DC fast-charging curve: fastest at a low charge, slowing down past half, and slow above 80%. Peak power follows Tesla's numbers: 325 kW for the Cybertruck, 250 kW for the other Teslas.
[*] [b]How long[/b]: 10% to 90% (game time) takes about 36 minutes for the Model Y and Model 3, about 38 for the Model Y L, about 47 for the Model S and Model X, and about 44 for the Cybertruck; the sandbox option Charging speed multiplier still applies.
[*] [b]Power[/b]: the same rule as a gas pump: outdoors on the grid it just works. After the power cut it charges at full speed within a generator's range or with a running, fuelled generator within 2 tiles (same floor); when the server turns off Generator Working in Exterior, only a generator within 2 tiles counts. With no power, right-clicking it shows a grey line saying so.
[*] [b]Fuel[/b]: each kWh burns the same fuel as on any charger, so a full charge still takes about one tank; but at this power it burns fuel much faster per hour: at 250 kW a full vanilla generator runs dry in about 19 minutes.
[*] [b]Take one home[/b]: picking one up or placing it takes Electrical 6 and a screwdriver; it weighs as much as a vanilla generator (40) and takes both hands, so drop other gear if you cannot pick it up. Once placed, the power rule above applies. A gas station's posts belong to nobody, so the car's key rules alone decide who may plug in or unplug; one you place yourself is yours (see the FAQ Someone else's car is plugged into my charger. What now?).
[*] [b]Destroy one[/b]: a vanilla sledgehammer's Destroy takes it down at any Electrical level; it is gone for good and drops nothing, and a car plugged into it is unplugged first. A server that allows sledgehammers only in safehouses applies that rule here too.
[*] [b]Solid[/b]: you cannot walk through it, and zombies do not break it.
[/list]
=== 🧰 Powershare and the bed outlets (Cybertruck)
{{img:25-ct-powershare-en.jpg}}
[h3]Powershare home backup[/h3]
[list]
[*] [b]What it is[/b]: in a blackout the Cybertruck powers your home, like the real Powershare home backup.
[*] [b]Turn it on[/b]: sitting in the truck, Turn on Powershare in the V radial menu, or the Powershare cell on the app's Controls page, then turn it on there. The same people who may plug in the charge cable may switch it (see the FAQ "What can I do without the key?").
[*] [b]When it powers the home[/b]: with Powershare on and the truck plugged into a Wall Connector, once the power there is out and no other generator feeds it, it starts by itself; it reaches as far as a vanilla generator. When the grid or another generator takes over it goes back to standing by and charges as usual.
[*] [b]Wall Connector only[/b]: on a Mobile Connector or with no cable it does not power the home, and the app reminds you to plug into a Wall Connector.
[*] [b]What the house uses, the truck pays[/b]: the house's use comes out of the Cybertruck's battery; the app shows the kW it gives now and how long it can keep going (in game time). It burns no fuel and makes no generator noise.
[*] [b]Discharge limit[/b]: 20% by default; − / + on the app's Powershare page move it 5% at a time (5–90%). At the limit it stops and tells whoever turned it on.
[*] [b]Other Teslas charge too[/b]: in a blackout, Teslas plugged into chargers in the house charge from the Cybertruck's battery (the charge card says Power: Powershare). What they get, the Cybertruck loses, kWh for kWh; together at most 11.5 kW, and once one is full or stopped the others can take all of it.
[*] [b]The Cybertruck itself[/b]: while powering the home its own charge card shows no power; it never charges itself.
[*] [b]Parked indoors[/b]: works too; deep inside a large indoor garage, with no outdoor spot within 8 tiles, Powershare shows Stopped with the reason, tells whoever turned it on, and tries again later.
[/list]
[table]
[tr][th]The app shows[/th][th]Meaning[/th][/tr]
[tr][td]Off[/td][td]Powershare is off[/td][/tr]
[tr][td]Standing by[/td][td]On; there is still power here, charging as usual[/td][/tr]
[tr][td]Powering the home[/td][td]Blackout; it is powering the home[/td][/tr]
[tr][td]Stopped[/td][td]The charge reached the discharge limit, or there is nowhere to supply from; the app says which[/td][/tr]
[/table]
[h3]Bed outlets: charge another Tesla[/h3]
{{img:26-ct-outlet-en.jpg}}
[olist]
[*] Turn on bed outlets in the V radial menu, or on the app's Powershare page.
[*] Lower the tailgate (a removed one counts).
[*] Set a Mobile Connector within 2 tiles of the bed, on the same floor.
[*] Plug another Tesla into that Mobile Connector; its charge card says Power: Cybertruck bed outlet.
[/olist]
[list]
[*] [b]Power[/b]: each car at the Mobile Connector's 7.6 kW, together at most 9.6 kW; once one is full or stopped the others can take all of it.
[*] [b]kWh[/b]: what the other car gets, the Cybertruck loses, down to the discharge limit (the same one as Powershare).
[*] [b]When it gives nothing[/b]: the tailgate is up, the Cybertruck has its own charge cable in, it is powering the home with Powershare, or the charge is at the limit; the app says why.
[/list]
[h3]Before removing this mod[/h3]
[list]
[*] [b]Turn Powershare off first[/b]: a Cybertruck powering the home when the game is saved leaves a vanilla generator behind after the mod is removed; it makes the vanilla noise, draws zombies, and only stops when its fuel runs out (30 days at most).
[/list]
=== 🧰 The Tesla-style dashboard
{{img:05-radial-en.jpg}}
[list]
[*] [b]Replaces the vanilla dashboard[/b]: in a Tesla you get the gear, speed, charge, range and live use / regen.
[*] [b]Power button[/b]: top left; click to start, click again to power off; powering off needs the car stopped.
[*] [b]Click the car to open doors[/b]: click the top view of the car on the dashboard to open or close that door, the liftgate or the hood (on the Cybertruck the bed is the tonneau cover, on the Model X the rear half is the falcon wing doors; the Model Y L has its own top view); a locked door unlocks first, and nothing opens while driving.
[*] [b]Quick keys[/b]: headlights, climate controls, radio, Camp Mode; a key that is on turns blue with an underline.
[*] [b]Reminders[/b]: a door open, charging, charged, no power at the charger, low battery, Camp or Sentry on show as one line below.
[*] [b]Hover help[/b]: every button and every area of the car picture says what it does when the mouse is over it.
[*] [b]V radial menu[/b]: adds Turn on Camp Mode, Charging Status and Turn on Chill (driver only); a car with a HEPA filter also has Turn on Bioweapon Defense Mode (see Bioweapon Defense Mode and Chill); the Cybertruck also has Powershare, the bed outlets and the light bar (the light bar for the driver only). When one is not available its icon is grey and the second line says why.
[*] [b]With AutoDrive[/b]: AutoDrive's autopilot card sits above the Tesla dashboard, and above the charge card while that is open.
[/list]
=== 🧰 Key card and phone key
{{img:06-car-menu-en.jpg}}
[h3]Key Card[/h3]
[list]
[*] [b]How you get one[/b]: a Tesla's car key becomes that car's Key Card, named after the car, even while you sit in it. A key in the ignition changes once you switch the car off and it comes back to you.
[*] [b]Tap to lock or unlock[/b]: outside the car, right-click the Tesla and choose Tap Key Card: Lock / Unlock; your character walks to the driver's door and taps it, and every door, the liftgate and the hood lock or unlock together.
[*] [b]Lights and sound[/b]: locking flashes once with a short horn chirp (zombies ignore it); unlocking flashes twice.
[*] [b]Wallet is fine[/b]: the card taps and starts the car from a wallet or bag too.
[*] [b]Starting[/b]: carried loose or on a key ring, the card goes into the ignition (the console's card reader) like a vanilla key; in a wallet or bag it stays there.
[/list]
{{img:07-pair-menu-en.jpg}}
[h3]Phone Key[/h3]
[list]
[*] [b]Where phones come from[/b]: the Smartphone is a new item, most common in electronics stores; sometimes in mall electronics, office desks and bedside tables. A newly spawned Tesla has a one-in-four chance of an unpaired one in its glove box.
[*] [b]Set it up[/b]: sit in the Tesla with its key card on you (or in the ignition), right-click the phone and choose Set Up as Phone Key; a phone in the glove box works too, it is taken out first. Without Vehicle Manager, sitting in a hotwired car works too, no card needed.
[*] [b]Walk up and it unlocks[/b]: pull a door handle with the phone key on you and the door unlocks and opens; a backpack or fanny pack is fine.
[*] [b]Starting[/b]: sit in the driver's seat and start; the phone can stay in a bag.
[*] [b]Walk-away lock[/b]: get out and walk about 6 tiles away with the phone; the doors lock, the lights flash once and the horn chirps.
[*] [b]When it does not lock[/b]: someone still inside, or a door or the trunk open; you are told why. The key card never locks by itself (nor does the real one).
[/list]
{{img:08-add-car-menu-en.jpg}}
[h3]One phone, several cars[/h3]
[list]
[*] [b]Add a car[/b]: sit in another Tesla with that car's key card, right-click the phone key and choose Add This Car (N Paired).
[*] [b]Remove a car[/b]: outside the car, right-click the phone key, Remove from Phone ▸ and pick one; remove them all and it is a plain phone again.
[*] [b]The cars go with the phone[/b]: hand the phone to someone and the cars it opens go with it, like a vanilla key.
[/list]
=== 🧰 The Tesla app
{{img:09-app-home-en.jpg}}
[list]
[*] [b]Open it[/b]: right-click the phone key and choose Open Tesla App; the phone appears on the right of the screen. An unpaired phone lists the option in red, with hover help on how to pair it.
[*] [b]Move it[/b]: hold any spot of the phone that is not a button and drag it elsewhere on the screen; it stays there and opens there next time (remembered on this computer, for each split-screen player).
[*] [b]Home[/b]: car name, battery and range, a status such as Parked · Locked, and a picture of the car in its paint.
[*] [b]Four quick icons[/b]: lock / unlock, stop / start charging, open / close the frunk, open / close the liftgate (the trunk on the Model 3); white when on, dim when not available.
[*] [b]Controller[/b]: D-pad moves, A presses, B goes back home from a page and closes the app from home.
[/list]
[table]
[tr][th]Page[/th][th]What it does[/th][/tr]
[tr][td]Controls[/td][td]Flash the lights to find the car, honk for a second (like the car's horn: nearby zombies hear it), open / close the frunk and the liftgate; the Model X adds the falcon wing doors (both at once); the Cybertruck adds the tonneau cover and Powershare (see Powershare and the bed outlets)[/td][/tr]
[tr][td]Location[/td][td]Arrow, distance, compass direction; Show on Map opens the world map; Navigate to Car with the MiniMap[/td][/tr]
[tr][td]Summon[/td][td]Only with AutoDrive; see Summon[/td][/tr]
[tr][td]Security[/td][td]Turn Sentry Mode on / off, see this car's Sentry Alerts[/td][/tr]
[tr][td]Charging[/td][td]Status, power, time to the target, stop / start charging[/td][/tr]
[/table]
{{img:10-app-pages-en.jpg}}
[h3]Connection[/h3]
[list]
[*] [b]While the grid is up[/b]: works at any distance. Generators and solar panels do not count as the grid.
[*] [b]After the power goes out[/b]: Bluetooth only, within 50 m of the car (sandbox App Bluetooth range after power cut (tiles); 1 tile = 1 m).
[*] [b]When it cannot reach the car[/b]: it shows the last recorded location, charge and status, with the buttons grey; after a power cut it also says how close to the car you need to be. Recording starts once you have looked at the car in the app.
[*] [b]Cars the game has not loaded[/b]: remote actions need the car in a loaded area (in singleplayer about 50 tiles around you); further away you see the last record only.
[*] [b]Multiplayer[/b]: only someone carrying this car's phone key sees where it is and controls it; the server checks every command again.
[/list]
[h3]Switching cars[/h3]
[list]
[*] [b]Car list[/b]: tap ▾ next to the car name on Home; each car shows its paint, charge and where it is (or how old the last record is); pick one to switch.
[*] [b]Vehicle Manager cars[/b]: with Vehicle Manager, Teslas you claimed or that are shared with you are listed too (tagged Vehicle Manager); one not added to this phone shows its location only, with the remote buttons dim.
[/list]
=== 🧰 Summon (needs AutoDrive)
{{img:11-summon-en.jpg}}
[list]
[*] [b]What you need[/b]:
[list]
[*] Minidoracat MiniMap - AutoDrive installed (it needs the MiniMap)
[*] AutoDrive's Autopilot Module installed in the car (Teslas leave the factory without one)
[*] This car's phone key on you
[/list]
[*] [b]Three kinds[/b]:
[list]
[*] Come to me: the car drives to you
[*] Pick a spot: tap a point inside the blue circle on the map, then press Go here
[*] Forward / Reverse: the car creeps straight ahead or back a short way, no steering
[/list]
[*] [b]Start and stop[/b]: tap once to start, tap the same button again to stop.
[*] [b]Screen[/b]: a small radar shows the car; below it, what the car is doing, how far it is and its speed; it says Arrived at the end, or why it stopped.
[*] [b]Range[/b]: 64 m by default (AutoDrive sandbox Summon range (tiles), 0 turns it off); below 1920×1080 the game computes car physics over a shorter distance, and the smaller of the two applies. After a power cut it is no further than the Bluetooth range (50 m by default), and the blue circle shrinks to match.
[*] [b]When you cannot summon[/b]: you are in the car, someone is in it, it is plugged in, towing or towed, its Low Voltage Battery is flat, it will not start, someone else is summoning it, it is out of range, or it has no Autopilot Module; the button turns grey with the reason.
[*] [b]While summoning[/b]: Sentry Mode turns off, the drive uses charge, and nearby players hear the motor and the pedestrian warning.
[*] [b]Closing the app is fine[/b]: reopen it and a running summon is still there and can be stopped; after a power cut you can still stop your own summon after the car leaves Bluetooth range.
[/list]
=== 🧰 Sentry Mode
{{img:12-sentry-alert-en.jpg}}
[list]
[*] [b]Turn it on[/b]: all doors locked, motor off, nobody inside; within 10 tiles outside, right-click the Tesla and choose Enable Sentry Mode, or use the app's Security page.
[*] [b]Charge[/b]: needs 20% or more; it uses about 0.25 kWh an hour and turns off below 20% with a notice (plugged into a powered charger it neither drains nor turns off).
[*] [b]Touch[/b]: someone pulls a door handle or tries to unlock: the headlights flash 3 times and the owner is told.
[*] [b]Damage[/b]: a smashed window, hotwiring or removed parts sound the vanilla alarm and the owner is told. A Cybertruck window takes 3 hits to break, and every hit sounds the alarm and tells the owner (the first two say the window was struck).
[*] [b]Any broken window counts[/b]: windows broken by zombies, crashes or weapon hits sound the vanilla alarm and tell the owner within about a game minute; in multiplayer a weapon hit sounds it at once. Fitting a new window in worse condition is not damage.
[*] [b]When the notice names someone[/b]: smashing a window with the Smash action names who did it; in multiplayer a weapon hit names the player only when they are the only one at the car (same floor, no other player or zombie within about 4 tiles, not split screen, a verified account). Zombies, crashes and anything else give a notice without a name, so nobody is blamed by mistake.
[*] [b]Hooked up to a tow[/b]: someone else uses the vanilla tow hitch (Attach … to … in the V radial menu) to hook the car to a trailer or behind another car: the vanilla alarm sounds and the owner is told "car hooked up to a tow".
[*] [b]One alarm per tow[/b]: while the alarm sounds (about 13 game minutes by default, as long as the vanilla alarm), the same car sounds and notifies only once, however often it is hooked up and to whatever.
[*] [b]Owners towing[/b]: when one of the owners below hooks it up, Sentry simply turns off instead.
[*] [b]Who counts as the owner[/b]: whoever turned it on, and anyone carrying this car's key, key card or phone key; with Vehicle Manager and a claimed car, only its Ride permission counts.
[*] [b]Offline owners[/b]: events wait until the owner logs in next.
[*] [b]Turning it off[/b]: unlocking with the key card, the phone key or the app turns Sentry off too.
[*] [b]Rammed in multiplayer[/b]: when another car hits a parked one, vanilla only counts the hit on the driver's own car, so the parked car takes no damage and nothing sounds.
[/list]
{{img:13-app-security-en.jpg}}
=== 🧰 Camp Mode
{{img:14-camp-en.jpg}}
[list]
[*] [b]Turn it on[/b]: sitting in the stopped car, press the dashboard's camp key or Turn on Camp Mode in the V radial menu; the motor may be running: it stops and the climate keeps going (with the motor running only the driver can turn it on).
[*] [b]Automatic climate[/b]: unless you set a temperature yourself, it heats or cools from the outside temperature to keep the cabin comfortable; turn the temperature knob and it follows yours.
[*] [b]Sleep[/b]: sleeping in the car while camping counts as an Average bed (Average, with Pillow with a pillow) instead of vanilla's bad seat; multiplayer servers need sleep allowed.
[*] [b]Screen entertainment[/b]: boredom of everyone awake in the car slowly goes down, about half as fast as watching TV.
[*] [b]Car outlet[/b]: right-click a Battery or a Car Battery in your inventory and choose Charge from car outlet; it uses the main battery: about 2 hours for a Battery, 5 for a Car Battery (in-game).
[*] [b]Cabin light[/b]: a warm white cabin light comes on, so others can tell from afar that someone is inside.
[*] [b]Turns off[/b]: when you start or drive off, nobody is inside, or the charge drops below the Camp Mode battery limit (20% by default); you are told.
[/list]
=== 🧰 Bioweapon Defense Mode and Chill
[h3]Bioweapon Defense Mode (HEPA filter)[/h3]
{{img:29-bdm-en.jpg}}
[list]
[*] [b]Which cars[/b]: the Model Y, Model Y L, Model S, Model X and Cybertruck have a HEPA filter; going by Tesla's owner's manual the Model 3 has none, and its V radial menu has no such slice.
[*] [b]Climate on means filtered[/b]: when enough corpses lie around to give you corpse sickness, sit in the car with the climate on and nobody inside gets any sicker.
[*] [b]Turn it on[/b]: in the car, pick Turn on Bioweapon Defense Mode in the V radial menu; anyone inside can. While it is on, the fan filters the air even with the climate knob at 0. Pick Turn off Bioweapon Defense Mode to stop it.
[*] [b]Needs power[/b]: it works only while the motor runs or in Camp Mode.
[*] [b]Charge[/b]: the same as running the climate; with the climate already on it uses nothing extra.
[*] [b]The stench moodle stays[/b]: it still shows for the corpses outside, but the sickness does not get worse; masks and clothing protect as in vanilla.
[/list]
[h3]Chill[/h3]
{{img:30-chill-en.jpg}}
[list]
[*] [b]Switching[/b]: the driver picks Turn on Chill in the V radial menu, and Turn off Chill to go back; it works while driving too.
[*] [b]Acceleration only[/b]: acceleration gets smooth and gentle, top speed stays. Every Tesla uses the same pull: the Model Y and Cybertruck both take about 16 seconds to 100 km/h (normally about 7 for the Model Y and 5 for the Cybertruck).
[*] [b]Dashboard[/b]: Chill shows next to the speed while it is on.
[*] [b]Stays with the car[/b]: still on when you get out and back in, or someone else drives.
[*] [b]No extra saving[/b]: charge use still depends on how you drive; Chill alone does not save charge.
[*] [b]Mechanics window[/b]: while it is on, the horsepower shown drops too, and comes back when you turn it off.
[/list]
=== 🧰 Drive unit parts
[list]
[*] [b]Repair[/b]: right-click the Drive Unit in the mechanics window and choose Repair Drive Unit; it takes Drive Unit Parts. Mechanics level, wrench, time and repair per part are the same as vanilla engine repair.
[*] [b]Take parts[/b]: Take Drive Unit Parts sets the drive unit's condition to 0 and gives you some parts.
[*] [b]No Spare Engine Parts[/b]: Teslas do not take vanilla Spare Engine Parts; other cars still do.
[*] [b]Getting them[/b]: take them from another Tesla or craft them; they are not in loot.
[/list]
[table]
[tr][th]Recipe[/th][th]Tools (kept)[/th][th]Materials[/th][th]Makes[/th][/tr]
[tr][td]Make Drive Unit Parts (learned automatically at Electrical 4)[/td][td]Screwdriver, Pliers[/td][td]Scrap Electronics 2, Electrical Wire 2, Copper Scrap 1[/td][td]Drive Unit Parts 2[/td][/tr]
[/table]
=== 🧰 With other mods
[h3]Vehicle Manager[/h3]
{{img:19-vm-menu-en.jpg}}
[list]
[*] [b]Claimed car[/b]: only Vehicle Manager's permissions count; carrying this car's key, key card or phone key no longer counts by itself.
[*] [b]Unclaimed car[/b]: this mod's rules apply; carry the key and you can use it.
[*] [b]Vehicle Manager menu[/b]: right-clicking a Tesla's Vehicle Manager menu adds Open Tesla App (only while you carry a phone key paired with it).
[*] [b]Cars not loaded[/b]: cars you claimed, and cars shared with you with the Location permission, show their last record in the app.
[*] [b]App car list[/b]: Teslas you claimed or that are shared with you are listed even before they are added to this phone (tagged Vehicle Manager), with their position; their remote buttons are dimmed.
[/list]
{{img:20-vm-app-en.jpg}}
[table]
[tr][th]Action[/th][th]Vehicle Manager permission[/th][/tr]
[tr][td]Key card tap, app lock / unlock, flash, honk, Sentry on / off, app falcon wing doors, Bioweapon Defense Mode[/td][td]Ride[/td][/tr]
[tr][td]App liftgate / trunk[/td][td]Trunk[/td][/tr]
[tr][td]App frunk[/td][td]Repair or Salvage[/td][/tr]
[tr][td]Plugging in or unplugging, the charge card, picking up or rotating a charger with the car plugged in, app stop / start charging[/td][td]Fuel (except the charger owner's unplug, charge card Stop, pick-up and rotate, see the FAQ; not the app)[/td][/tr]
[tr][td]App location and status[/td][td]Location[/td][/tr]
[tr][td]App Summon, Chill[/td][td]Drive[/td][/tr]
[tr][td]Setting up a new phone key without the key card[/td][td]Owner (cannot be shared)[/td][/tr]
[/table]
[h3]Minidoracat MiniMap[/h3]
{{img:21-minimap-nav-en.jpg}}
[list]
[*] [b]Car markers[/b]: the minimap and its world map show every Tesla on your phone (where the app last saw it); a marker fades after 10 minutes without a look in the app.
[*] [b]Navigate to Car[/b]: on the app's Location page, sets the minimap's destination to your car.
[*] [b]No double markers[/b]: a car Vehicle Manager already draws is not drawn again.
[/list]
[h3]Minidoracat MiniMap - AutoDrive[/h3]
{{img:22-summon-en.jpg}}
[list]
[*] [b]Summon[/b]: the app hands the driving to AutoDrive and the car drives itself to you; see Summon.
[/list]
{{img:01b-fsd-en.jpg}}
[list]
[*] [b]FSD view[/b]: while the car drives itself, the card draws its route and the cars and zombies around it; when you drive, it still shows what is ahead.
[*] [b]Dashboard spot[/b]: AutoDrive's cards sit above the Tesla dashboard by themselves.
[/list]
[h3]Project Viewpoint (3D view)[/h3]
{{img:31-viewpoint-en.jpg}}
[list]
[*] [b]Cabin details[/b]: sit in a Tesla and you see stitched seats, the steering wheel with its T badge, the centre screen with a map, air vents, cup holders, the phone mount, floor mats and the rear-view mirror; in all six cars and every seat.
[*] [b]Only the car you sit in[/b]: other cars keep the plain look, with a dark grey cabin.
[*] [b]Nothing changes without it[/b]: players without Project Viewpoint see the same picture and get the same performance as before.
[*] [b]Can vanish for a moment in multiplayer[/b]: when a part on the car you sit in is installed, removed or repaired, the details disappear and come back within one in-game minute.
[*] [b]No charge cable[/b]: Project Viewpoint's 3D view does not draw the charge cable; switch back to the vanilla view to see it.
[/list]
=== ⚙️ Sandbox options and defaults
On the Tesla Collection page of the sandbox settings.
[table]
[tr][th]Option[/th][th]Default[/th][th]Range[/th][th]What it does[/th][/tr]
[tr][td]Range multiplier[/td][td]1.0[/td][td]0.25–10.0[/td][td]How far a full battery drives; 1.0 = as far as a full tank in a vanilla car of the same class; vanilla Gas Consumption scales it too[/td][/tr]
[tr][td]Charging speed multiplier[/td][td]1.0[/td][td]0.1–10.0[/td][td]1.0 = official charger power (Wall Connector 11.5 kW, Mobile Connector 7.6 kW, Supercharger up to 250 kW, 325 kW for the Cybertruck); the Cybertruck's Powershare 11.5 kW and bed outlet 9.6 kW limits scale with it too[/td][/tr]
[tr][td]Charging fuel multiplier[/td][td]1.0[/td][td]0–10.0[/td][td]Generator fuel a Tesla burns, charging and the car's own loads while plugged in; 1.0 = about one tank for a full charge at the default Generator Fuel Consumption, 0 = no fuel[/td][/tr]
[tr][td]Camp Mode battery limit[/td][td]20[/td][td]10–20 (%)[/td][td]Below this charge Camp Mode cannot turn on, and while camping it turns off[/td][/tr]
[tr][td]App Bluetooth range after power cut (tiles)[/td][td]50[/td][td]0–64[/td][td]After the power goes out the app reaches the car within this many tiles only (1 tile = 1 m), Summon included; no limit while the grid is up; 0 = no link after the power cut[/td][/tr]
[/table]
Options elsewhere that also affect Teslas:
[table]
[tr][th]Option[/th][th]Where[/th][th]Effect[/th][/tr]
[tr][td]Summon range (tiles), default 64[/td][td]AutoDrive sandbox[/td][td]How far the app's Summon reaches; 0 turns Summon off[/td][/tr]
[tr][td]Virtual key for owners, default on[/td][td]Vehicle Manager sandbox[/td][td]Off: an owner without the key card cannot set up a new phone key[/td][/tr]
[tr][td]Gas Consumption[/td][td]Vanilla sandbox[/td][td]Multiplies the charge driving and Summon use (Range multiplier divides it): 2 = half the range, 0 = driving uses no charge; climate, Camp Mode and Sentry use the same as before[/td][/tr]
[tr][td]Generator Fuel Consumption[/td][td]Vanilla sandbox[/td][td]Multiplies with Charging fuel multiplier: how much generator fuel charging and the car's own loads burn[/td][/tr]
[tr][td]Electricity Shutoff[/td][td]Vanilla sandbox[/td][td]Once the grid is down, the app works over Bluetooth only (App Bluetooth range after power cut, 50 m by default)[/td][/tr]
[tr][td]SpeedLimit, default 70[/td][td]Multiplayer server settings[/td][td]Teslas, like vanilla cars, cannot go faster[/td][/tr]
[/table]
=== ⚠️ Known limitations
[list]
[*] [b]No grid in player-built houses[/b]: they do not count as rooms, so a charger there needs a generator.
[*] [b]Sentry only sees the vanilla tow hitch[/b]: other mods' ways of hauling a car off (lifting it onto a flatbed, for one) do not set it off.
[*] [b]Broken windows take a moment[/b]: a window broken by zombies or a crash sounds within about a game minute, and the notice names nobody.
[*] [b]The Cybertruck's roof light bar[/b]: the bar itself does not glow; what lights up is the ground ahead.
[*] [b]Powershare's reach[/b]: it follows the vanilla generator sandbox settings and cannot be set apart for the Cybertruck.
[*] [b]Double notices[/b]: with Vehicle Manager, one event may bring both its parking guard notice and a Sentry notice.
[*] [b]Summon[/b]:
[list]
[*] The pick page has a fixed zoom; a pin close to the car overlaps the car and player markers
[*] In split screen only the first player can summon
[*] Players who come within 120 tiles after a summon started do not hear that summon
[/list]
[*] [b]Multiplayer accounts[/b]:
[list]
[*] Sentry and Camp owner notices go by account name; on a Steam server the name is bound to the first Steam account that uses it, and a no-steam server cannot stop someone using another player's name
[*] Split-screen players 2–4 have no account: with the key they can use the car, but they get no owner notices, and cannot use a car claimed in Vehicle Manager
[*] Admins cannot rebind an account name; on a Steam friends game (player-hosted) the login name is the Steam display name, so after changing it, earlier notices, Sentry and Camp no longer count as yours
[/list]
[*] [b]One console line[/b]: in multiplayer the driver's console gets a container already has id line on each start; it is vanilla (normal cars too), and no key is duplicated or lost.
[/list]
=== ❓ FAQ: keys, summon and permissions
[h3]Where do I find a phone?[/h3]
[list]
[*] The Smartphone only comes from loot: most common in electronics stores, sometimes in mall and store electronics, office desks and bedside tables; a newly spawned Tesla has a one-in-four chance of one in its glove box.
[*] There is no recipe and you do not spawn with one; the vanilla cordless phone cannot be paired.
[/list]
[h3]I lost my key card. What now?[/h3]
{{img:18-hotwire-pair-en.jpg}}
[list]
[*] [b]You have a phone key[/b]: it is your spare key: door handles, starting from a bag and the app all still work.
[*] [b]The car is claimed in Vehicle Manager[/b]: the owner can sit in it and set up a new phone as the phone key (the server needs Vehicle Manager's Virtual key for owners on; shared players still need the card); the owner and anyone allowed to drive can also unlock and start it with Vehicle Manager's virtual key.
[*] [b]Neither[/b]: hotwire it like a vanilla car; without Vehicle Manager, sit in the hotwired car and set up a new phone as the phone key, and the app and Summon work again. Admins can get a key from the mechanics window's cheat options. With Vehicle Manager installed, an unclaimed car with both the card and the phone lost cannot pair a new phone.
[/list]
[h3]Does the key card protect my car?[/h3]
[list]
[*] No: key cards and phone keys work like vanilla keys; an unclaimed car opens for whoever holds them. To protect it, claim it with Vehicle Manager.
[/list]
[h3]What can I do without the key?[/h3]
{{img:17-locked-menu-en.jpg}}
Without Vehicle Manager:
[list]
[*] [b]Car unlocked[/b]: plug in or unplug the charge cable, set the target or stop charging on the charge card, and pick up or rotate a charger the car is plugged into.
[*] [b]Car locked[/b]: all of that needs this car's key; the menu is grey and says The car is locked: you need this car's key, and the server refuses too.
[*] [b]After hotwiring[/b]: it counts as the key in the ignition: plug in, unplug and use the charge card whether it is locked or not; sitting in it you can turn on Camp Mode and set up a phone as its phone key.
[*] [b]Not for Sentry[/b]: hotwiring alone does not make you the owner; a stranger's hotwire still sounds the alarm, tells the owner and cannot turn Sentry off. Setting up a phone key in the hotwired car, though, is like carrying its key, so that player can turn Sentry off; for real theft protection use Vehicle Manager.
[*] With Vehicle Manager: its rights decide, locked or not, hotwired or not.
[/list]
[h3]Someone else's car is plugged into my charger. What now?[/h3]
[list]
[*] [b]Who owns a charger[/b]: whoever placed it, and the owner and members of the safehouse it stands in.
[*] [b]The owner can[/b]: unplug the cable, press Stop on the charge card, and pick up or rotate the charger, whether that car is locked or not, with or without Vehicle Manager.
[*] [b]The owner cannot[/b]: plug in a car they have no right to, or change that car's target or resume its charging.
[/list]
[h3]What does Summon need?[/h3]
[list]
[*] Minidoracat MiniMap - AutoDrive (with the MiniMap), an Autopilot Module in the car, and this car's phone key on you.
[*] Nobody in the car, not plugged in, within range; a grey button says why.
[*] With Vehicle Manager, the Drive permission for that car.
[/list]
[h3]With Vehicle Manager, who decides permissions?[/h3]
[list]
[*] Claimed car: Vehicle Manager alone (see the table in With other mods); someone who picks up the key card or phone key cannot unlock it or turn Sentry off.
[*] Unclaimed car: this mod's key rules.
[*] Exception: the walk-away lock with the phone key only ever locks, and does not ask Vehicle Manager.
[/list]
=== ❓ FAQ: charging, the app and removal
[h3]Why does the charger have no power?[/h3]
{{img:16-mobile-nopower-en.jpg}}
[list]
[*] Wall Connector on the grid: its square or one next to it must be inside a house, and the grid still up.
[*] Wall Connector after the power cut: a running, fuelled generator nearby (the vanilla generator range).
[*] Mobile Connector: indoors where there is power; anywhere else within 2 tiles of a running, fuelled generator, also when the server turns off Generator Working in Exterior. Outdoors in a generator's range with no generator next to it there is no power, and right-clicking it shows a grey line saying so.
[*] Supercharger: like a gas pump, it has power outdoors on the grid; after the power cut it needs to be within a generator's range or within 2 tiles of a running, fuelled generator. With no power, right-clicking it shows a grey line saying so.
[*] The charge card shows the current source.
[/list]
[h3]Why won't it drive while plugged in?[/h3]
[list]
[*] Like the real car, it stays in P while the cable is in; unplug it and drive away.
[/list]
[h3]The app buttons are grey, or it only shows the last record?[/h3]
[list]
[*] After the power cut it is Bluetooth only, within 50 m (servers can change it in the sandbox: App Bluetooth range after power cut); a car outside the loaded area also shows its last record only.
[*] With Vehicle Manager, buttons you have no permission for do not work.
[/list]
[h3]I added the mod mid-save and see no Teslas, phones or Superchargers?[/h3]
[list]
[*] Teslas appear only in areas loaded for the first time after that, and phones only in containers nobody searched yet, so go somewhere new. The gas stations' Superchargers are different: stations you already visited get theirs the next time they load, and with Electrical 6 you can make one.
[/list]
[h3]What should I do before removing this mod?[/h3]
[list]
[*] [b]Back up the save first[/b]: once the save is loaded without this mod and saved, the changes below stay in it, and adding the mod back does not undo them.
[*] [b]Items vanish[/b]: key cards, phones, phone keys, drive unit parts and chargers not yet placed vanish on the next load, in inventories, containers and cars alike; they do not turn into other items, and vanilla items stay. An offline player loses them the next time they log in.
[*] [b]Teslas become other vehicles[/b]: each car stays on its spot facing the same way, but its type is picked at random from every vehicle with wheels, vanilla, wrecked or from other mods (tests turned them into vans, a wrecked pickup and sedan, and another mod's utility truck). The new car's gas tank slot is empty, with no tank and no fuel, and its keys are gone too: treat it like a car whose key was lost.
[*] [b]The replacement car keeps the Tesla's pulling power[/b]: the engine force is saved with the car, so the new type drives with the Tesla's force, not its own (tested: a Model Y became a van at 626 hp where that van has 400; a Model 3 left in Chill became a pickup at 310 hp where that pickup has 420). Its top speed is the new type's. An admin's full vehicle repair sets the force back to the new type's.
[*] [b]Things in the car[/b]: whatever is in the Front Trunk is always lost (vanilla cars have no such slot). Rear Trunk, seats and glove box: one that somebody opened keeps its contents if the new type has the same slot; one nobody ever opened is emptied and refilled with the new type's random loot. If the new type lacks the slot, its contents are lost too.
[*] [b]Placed chargers[/b]: Wall Connectors, Mobile Connectors and Superchargers (the gas stations' too) turn into invisible objects that cannot be picked up and stay on that square without blocking it; a plugged cable disappears too.
[*] [b]A Cybertruck's Powershare[/b]: turn it off first; one powering the home at save time stays as a vanilla generator (vanilla noise, draws zombies) until its fuel runs out, 30 days at most.
[*] [b]The server's Tesla data[/b]: app records, offline notices and phone pairings are in gos_MinidoracatTeslaApp.bin in the save folder, the charger list in gos_MinidoracatTeslaCharger.bin. Without the mod the game neither reads nor changes them; leaving them there is harmless.
[*] [b]Steps for server admins[/b]:
[olist]
[*] Tell players to unplug the cables, pick up their chargers (the picked-up chargers vanish later too, but no blank object is left on the square), turn off their Cybertrucks' Powershare, and move anything they want to keep out of the Teslas' Front and Rear Trunks, Cargo Beds, seats and glove boxes.
[*] Shut the server down and back up the whole save folder Zomboid/Saves/Multiplayer/<server name>/.
[*] In the server settings file Zomboid/Server/<server name>.ini, remove MinidoracatTeslaFor42 from Mods= and this mod's Workshop ID from WorkshopItems=.
[*] Start the server. Players join as usual; the server console shows extra lines such as cannot create item and item == null, skipped bytes for the dropped Tesla items, which are not errors.
[/olist]
[*] [b]Single player[/b]: back up the save, remove this mod from that save's mod list, then load it.
[/list]
=== 💬 Reporting issues
[list]
[*] [b][url=https://github.com/Minidoracat/MinidoracatTeslaFor42/issues]GitHub Issues[/url][/b]
[*] [b][url=https://discord.gg/Gur2V67]Discord[/url][/b]: please include
[list]
[*] Game mode (singleplayer / multiplayer)
[*] What happened and the steps to reproduce it
[*] Error messages (if any)
[/list]
[*] [b]Translations[/b]: please report translation issues.
[/list]
