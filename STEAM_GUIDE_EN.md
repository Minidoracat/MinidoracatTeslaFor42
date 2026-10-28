<!-- Steam guide source (English). The full description lives in this guide; the Workshop page only has a summary. Format and sync: pz-family-docs/release.md "完整說明：Steam 指南" -->
<!-- 標題：📖 Minidoracat Tesla Collection Mod Guide: Cars, Charging, Keys and the App -->
<!-- 摘要：A picture guide to Minidoracat Tesla Collection: the Model Y and Model 3 Performance, the battery, the Wall Connector and the Mobile Connector, the Tesla-style dashboard, key cards and phone keys, the Tesla app and Summon, Sentry and Camp Mode, drive unit parts, and how it works with Vehicle Manager, the MiniMap and AutoDrive, plus the sandbox options. -->
<!-- Screenshots: docs/screenshots/steam/en/, shot by guide-shots-sp in the family repo's e2e/MinidoracatTeslaFor42 (Summon shots: phone-summon-sp) -->
=== 🚀 Quick start
[b]中文版：[/b] [url=XXXX]Minidoracat Tesla Collection 完整說明[/url]

Mod page (Steam Workshop):
https://steamcommunity.com/sharedfiles/filedetails/?id=XXXX
[olist]
[*] [b]Find a car[/b]: Teslas park in parking lots; the Model Y also turns up in upscale neighbourhoods.
[*] [b]Get the key[/b]: a Tesla's car key turns into that car's Key Card when you pick it up.
[*] [b]Start it[/b]: sit in the driver's seat and click the power button at the top left of the dashboard (or start it the vanilla way).
[*] [b]Charge it[/b]: with Electrical 3, make a Tesla Wall Connector (Gen 3) and mount it on a powered wall, or set a Tesla Mobile Connector (Gen 3) on the floor; right-click it to plug in the charge cable.
[*] [b]Phone key[/b]: sit in the car with the key card, right-click a Smartphone and choose Set Up as Phone Key; then right-click the phone key and choose Open Tesla App.
[/olist]
[list]
[*] [b]Optional mods[/b]:
[list]
[*] [url=https://steamcommunity.com/sharedfiles/filedetails/?id=3813972279]Minidoracat Vehicle Manager[/url]: vehicle claims; the Tesla keys, the app and Sentry follow its permissions
[*] [url=https://steamcommunity.com/sharedfiles/filedetails/?id=3792675881]Minidoracat MiniMap - AutoDrive[/url]: Summon in the app
[*] [url=https://steamcommunity.com/sharedfiles/filedetails/?id=3763913359]Minidoracat MiniMap[/url]: your Teslas on the minimap, navigate to your car
[/list]
[*] [b]Singleplayer and multiplayer[/b]: both work; in multiplayer the server must enable this mod, and the server makes every decision.
[/list]
=== 🧰 The cars: Model Y and Model 3 Performance
{{img:01-cars-en.jpg}}
[list]
[*] [b]Top trims only[/b]: both are the Performance version; power, battery, badges and looks follow Tesla's own data.
[*] [b]Where they spawn[/b]: parking lots, both at the same chance; upscale neighbourhoods have the Model Y only.
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
[*] [b]Front Trunk[/b]: open the hood first to reach what is inside.
[*] [b]High Voltage Battery[/b]: comes out without draining it first; the charge stays in the battery.
[*] [b]Brakes[/b]: regenerative braking halves brake wear compared with a normal car.
[/list]
=== 🧰 Battery and range
[list]
[*] [b]Charge is fuel[/b]: the High Voltage Battery replaces petrol; driving uses charge and braking wins some back.
[*] [b]Range[/b]: a full battery goes as far as a full tank in a vanilla car of the same class; the sandbox option Range multiplier changes it.
[*] [b]Out of charge[/b]: the motor stops and will not start until you charge.
[*] [b]Low Voltage Battery[/b]: the main battery tops it up while it holds 5% or more, so a car parked for a long time still starts.
[*] [b]Power in the car[/b]: climate, Camp Mode and Sentry Mode use the main battery too; plugged into a powered charger, the charger supplies them instead.
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
[*] [b]Generator[/b]: after the power goes out it burns the fuel of a running generator nearby (the vanilla generator range). Charging burns that generator's fuel: about one tank for a full charge, scaled by the sandbox option Generator Fuel Consumption.
[/list]
[h3]Mobile Connector[/h3]
A charger that works on the floor, no wall needed; slower than the Wall Connector.
[table]
[tr][th]Recipe[/th][th]Tools (kept)[/th][th]Materials[/th][th]Result[/th][/tr]
[tr][td]Make Tesla Mobile Connector[/td][td]Screwdriver[/td][td]Car Battery Charger 1, Electrical Wire 3, Scrap Electronics 1[/td][td]Tesla Mobile Connector (Gen 3) 1[/td][/tr]
[/table]
[list]
[*] [b]Getting one[/b]: Electrical 2 learns the recipe (made next to a work surface); it also turns up on the shelves that stock car battery chargers (car supply stores, garages, gas stations and so on; not in other vehicles' trunks) at about half their chance (both are Mechanics loot); a newly spawned Tesla has a one-in-four chance of one in its Rear Trunk.
[*] [b]On the floor[/b]: place it like vanilla furniture; you place and pick it up with bare hands, no tool or skill needed.
[*] [b]Power[/b]: indoors where there is power (the grid, or a building in a generator's range; a roofed player-built base counts as indoors, though player-built houses get no grid) it works like the Wall Connector: grid first, then after the power cut the fuel of the generator powering it. Anywhere else it must sit within 2 tiles of a running, fuelled generator (same floor, diagonals count): it is plugged straight into that generator and burns its fuel, even when the server turns off the sandbox option Generator Working in Exterior. Outdoors in a generator's range with no generator next to it there is no power: the cable still plugs in but nothing charges, and right-clicking the charger shows a grey line saying so. On a generator a full charge also takes about one tank of fuel; it charges slower, so per hour it burns about 2/3 of what the Wall Connector does.
[/list]
{{img:03-charger-menu-en.jpg}}
[h3]Plug in and charge[/h3]
[list]
[*] [b]Plug in[/b]: stand at the charger, right-click it and choose Plug in charge cable: <car>; every Tesla the cable reaches is listed (cable length: about 6 tiles for the Wall Connector, 5 for the Mobile Connector).
[*] [b]Who can plug in or unplug[/b]: anyone with this car's key, anyone once the car is hotwired, or anyone while the car is unlocked; locked and no key, the rows are grey (see the FAQ What can I do without the key?).
[*] [b]Motor on is fine[/b]: the car only has to stand still; you can also start it while plugged in.
[*] [b]No driving off plugged in[/b]: throttle or reverse says Unplug the charge cable first and the dashboard shows P; unplug and drive away.
[*] [b]Auto unplug[/b]: towed or pushed past the cable's reach, the car is unplugged and you are told.
[*] [b]Charging speed[/b]: 11.5 kW at the Wall Connector, 7.6 kW at the Mobile Connector; empty to 90% takes about 6 and 9 in-game hours; the sandbox option Charging speed multiplier changes it.
[*] [b]Time skips count[/b]: charge is settled by the hours that passed, so sleeping or fast-forwarding loses nothing.
[*] [b]Other players see the cable[/b]: it hangs from the Wall Connector to the ground (it leaves the Mobile Connector right on the ground) and runs to the car's charge port.
[/list]
{{img:04-charging-en.jpg}}
[h3]The charge card[/h3]
[list]
[*] [b]Open it[/b]: in the car press V and choose Charging Status, or right-click the charger and choose the same.
[*] [b]Shows[/b]: power, what this session added (km, kWh), time to the target, and whether the grid or a generator powers it.
[*] [b]Target[/b]: − / + move it 10% at a time, 50–100%; Daily is 50–90%, Trip 90–100%.
[*] [b]Buttons[/b]: stop / start charging, unplug, close; a controller works too. Without the right (car locked, no key) the target and these buttons are grey and the hover help says why.
[/list]
=== 🧰 The Tesla-style dashboard
{{img:05-radial-en.jpg}}
[list]
[*] [b]Replaces the vanilla dashboard[/b]: in a Tesla you get the gear, speed, charge, range and live use / regen.
[*] [b]Power button[/b]: top left; click to start, click again to power off; powering off needs the car stopped.
[*] [b]Click the car to open doors[/b]: click the top view of the car on the dashboard to open or close that door, the liftgate or the hood; a locked door unlocks first, and nothing opens while driving.
[*] [b]Quick keys[/b]: headlights, climate controls, radio, Camp Mode; a key that is on turns blue with an underline.
[*] [b]Reminders[/b]: a door open, charging, charged, no power at the charger, low battery, Camp or Sentry on show as one line below.
[*] [b]Hover help[/b]: every button and every area of the car picture says what it does when the mouse is over it.
[*] [b]V radial menu[/b]: adds Turn on Camp Mode and Charging Status; when one is not available its icon is grey and the second line says why.
[*] [b]With AutoDrive[/b]: AutoDrive's autopilot card sits above the Tesla dashboard, and above the charge card while that is open.
[/list]
=== 🧰 Key card and phone key
{{img:06-car-menu-en.jpg}}
[h3]Key Card[/h3]
[list]
[*] [b]How you get one[/b]: a Tesla's car key becomes that car's Key Card, named after the car.
[*] [b]Tap to lock or unlock[/b]: outside the car, right-click the Tesla and choose Tap Key Card: Lock / Unlock; your character walks to the driver's door and taps it, and every door, the liftgate and the hood lock or unlock together.
[*] [b]Lights and sound[/b]: locking flashes once with a short horn chirp (zombies ignore it); unlocking flashes twice.
[*] [b]Wallet is fine[/b]: the card taps from a wallet too; to start the car, carry it loose or on a key ring.
[*] [b]Starting[/b]: the card goes into the ignition (the console's card reader) like a vanilla key.
[/list]
{{img:07-pair-menu-en.jpg}}
[h3]Phone Key[/h3]
[list]
[*] [b]Where phones come from[/b]: the Smartphone is a new item, most common in phone shops; sometimes in mall electronics, office desks and bedside tables.
[*] [b]Set it up[/b]: sit in the Tesla with its key card on you (or in the ignition), right-click the phone and choose Set Up as Phone Key. Without Vehicle Manager, sitting in a hotwired car works too, no card needed.
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
[*] [b]Home[/b]: car name, battery and range, a status such as Parked · Locked, and a picture of the car in its paint.
[*] [b]Four quick icons[/b]: lock / unlock, stop / start charging, open / close the frunk, open / close the liftgate (the trunk on the Model 3); white when on, dim when not available.
[*] [b]Controller[/b]: D-pad moves, A presses, B goes back home from a page and closes the app from home.
[/list]
[table]
[tr][th]Page[/th][th]What it does[/th][/tr]
[tr][td]Controls[/td][td]Flash the lights to find the car, honk for a second (like the car's horn: nearby zombies hear it), open / close the frunk and the liftgate[/td][/tr]
[tr][td]Location[/td][td]Arrow, distance, compass direction; Show on Map opens the world map; Navigate to Car with the MiniMap[/td][/tr]
[tr][td]Summon[/td][td]Only with AutoDrive; see Summon[/td][/tr]
[tr][td]Security[/td][td]Turn Sentry Mode on / off, see this car's Sentry Alerts[/td][/tr]
[tr][td]Charging[/td][td]Status, power, time to the target, stop / start charging[/td][/tr]
[/table]
{{img:10-app-pages-en.jpg}}
[h3]Connection[/h3]
[list]
[*] [b]While the grid is up[/b]: works at any distance.
[*] [b]After the power goes out[/b]: Bluetooth only, within 30 m of the car.
[*] [b]When it cannot reach the car[/b]: it shows the last recorded location, charge and status, with the buttons grey; recording starts once you have looked at the car in the app.
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
[*] [b]Range[/b]: 64 m by default (AutoDrive sandbox Summon range (tiles), 0 turns it off); below 1920×1080 the game computes car physics over a shorter distance, and the smaller of the two applies.
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
[*] [b]Damage[/b]: a smashed window, hotwiring or removed parts sound the vanilla alarm and the owner is told.
[*] [b]Who counts as the owner[/b]: whoever turned it on, and anyone carrying this car's key, key card or phone key; with Vehicle Manager and a claimed car, only its Ride permission counts.
[*] [b]Offline owners[/b]: events wait until the owner logs in next.
[*] [b]Turning it off[/b]: unlocking with the key card, the phone key or the app turns Sentry off too.
[*] [b]No zombie detection[/b]: zombies do not attack an empty car anyway.
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
[list]
[*] [b]Claimed car[/b]: only Vehicle Manager's permissions count; carrying this car's key, key card or phone key no longer counts by itself.
[*] [b]Unclaimed car[/b]: this mod's rules apply; carry the key and you can use it.
[*] [b]Vehicle Manager menu[/b]: right-clicking a Tesla's Vehicle Manager menu adds Open Tesla App (only while you carry a phone key paired with it).
[*] [b]Cars not loaded[/b]: cars you claimed, and cars shared with you with the Location permission, show their last record in the app.
[/list]
[table]
[tr][th]Action[/th][th]Vehicle Manager permission[/th][/tr]
[tr][td]Key card tap, app lock / unlock, flash, honk, Sentry on / off[/td][td]Ride[/td][/tr]
[tr][td]App liftgate / trunk[/td][td]Trunk[/td][/tr]
[tr][td]App frunk[/td][td]Repair or Salvage[/td][/tr]
[tr][td]Plugging in or unplugging, the charge card, picking up or rotating a charger with the car plugged in, app stop / start charging[/td][td]Fuel (except the charger owner's unplug, charge card Stop, pick-up and rotate, see the FAQ; not the app)[/td][/tr]
[tr][td]App location and status[/td][td]Location[/td][/tr]
[tr][td]App Summon[/td][td]Drive[/td][/tr]
[tr][td]Setting up a new phone key without the key card[/td][td]Owner (cannot be shared)[/td][/tr]
[/table]
[h3]Minidoracat MiniMap[/h3]
[list]
[*] [b]Car markers[/b]: the minimap and its world map show every Tesla on your phone (where the app last saw it); a marker fades after 10 minutes without a look in the app.
[*] [b]Navigate to Car[/b]: on the app's Location page, sets the minimap's destination to your car.
[*] [b]No double markers[/b]: a car Vehicle Manager already draws is not drawn again.
[/list]
[h3]Minidoracat MiniMap - AutoDrive[/h3]
[list]
[*] [b]Summon[/b]: the app hands the driving to AutoDrive; see Summon.
[*] [b]Dashboard spot[/b]: AutoDrive's cards sit above the Tesla dashboard by themselves.
[/list]
=== ⚙️ Sandbox options and defaults
On the Tesla Collection page of the sandbox settings.
[table]
[tr][th]Option[/th][th]Default[/th][th]Range[/th][th]What it does[/th][/tr]
[tr][td]Range multiplier[/td][td]1.0[/td][td]0.25–4.0[/td][td]How far a full battery drives; 1.0 = as far as a full tank in a vanilla car of the same class[/td][/tr]
[tr][td]Charging speed multiplier[/td][td]1.0[/td][td]0.1–10.0[/td][td]1.0 = official charger power (Wall Connector 11.5 kW, Mobile Connector 7.6 kW)[/td][/tr]
[tr][td]Camp Mode battery limit[/td][td]20[/td][td]10–20 (%)[/td][td]Below this charge Camp Mode cannot turn on, and while camping it turns off[/td][/tr]
[/table]
Options elsewhere that also affect Teslas:
[table]
[tr][th]Option[/th][th]Where[/th][th]Effect[/th][/tr]
[tr][td]Summon range (tiles), default 64[/td][td]AutoDrive sandbox[/td][td]How far the app's Summon reaches; 0 turns Summon off[/td][/tr]
[tr][td]Virtual key for owners, default on[/td][td]Vehicle Manager sandbox[/td][td]Off: an owner without the key card cannot set up a new phone key[/td][/tr]
[tr][td]Generator Fuel Consumption[/td][td]Vanilla sandbox[/td][td]How fast a charger burns generator fuel after the power goes out[/td][/tr]
[tr][td]Electricity Shutoff[/td][td]Vanilla sandbox[/td][td]Once the grid is down, the app works over Bluetooth within 30 m only[/td][/tr]
[tr][td]SpeedLimit, default 70[/td][td]Multiplayer server settings[/td][td]Teslas, like vanilla cars, cannot go faster[/td][/tr]
[/table]
=== ⚠️ Known limitations
[list]
[*] [b]No grid in player-built houses[/b]: they do not count as rooms, so a charger there needs a generator.
[*] [b]Sentry ignores zombies[/b]: it only reacts to players touching or damaging the car.
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
=== ❓ FAQ
[h3]Where do I find a phone?[/h3]
[list]
[*] The Smartphone only comes from loot: most common in phone shops, sometimes in mall and store electronics, office desks and bedside tables.
[*] There is no recipe and you do not spawn with one; the vanilla cordless phone cannot be paired.
[/list]
[h3]I lost my key card. What now?[/h3]
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
[*] [b]Older chargers[/b]: chargers placed before this feature have no owner on record and follow the normal rules; pick one up and place it again to record you (if you can pick it up).
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
[h3]Why does the charger have no power?[/h3]
[list]
[*] Wall Connector on the grid: its square or one next to it must be inside a house, and the grid still up.
[*] Wall Connector after the power cut: a running, fuelled generator nearby (the vanilla generator range).
[*] Mobile Connector: indoors where there is power; anywhere else within 2 tiles of a running, fuelled generator, also when the server turns off Generator Working in Exterior. Outdoors in a generator's range with no generator next to it there is no power, and right-clicking it shows a grey line saying so.
[*] The charge card shows the current source.
[/list]
[h3]Why won't it drive while plugged in?[/h3]
[list]
[*] Like the real car, it stays in P while the cable is in; unplug it and drive away.
[/list]
[h3]The app buttons are grey, or it only shows the last record?[/h3]
[list]
[*] After the power cut it is Bluetooth only, within 30 m; a car outside the loaded area also shows its last record only.
[*] With Vehicle Manager, buttons you have no permission for do not work.
[/list]
[h3]I added the mod mid-save and see no Teslas or phones?[/h3]
[list]
[*] Teslas spawn only in areas loaded for the first time after that, and phones only in containers nobody searched yet. Go somewhere new.
[/list]
[h3]What should I do before removing this mod?[/h3]
[list]
[*] [b]What disappears[/b]: key cards, phones and phone keys, drive unit parts and charger items vanish on the next load; the Teslas in the save lose their car type, the game turns them into other vehicles, and Front Trunk contents are lost.
[*] [b]Placed chargers[/b]: Wall Connectors and Mobile Connectors turn into invisible objects that cannot be picked up and stay on that square.
[*] [b]Steps[/b]: unplug the cables and pick up every charger; take everything out of the Teslas' Front and Rear Trunks; then remove the mod.
[*] [b]Leftover data is harmless[/b]: the server's Tesla save (app records, offline notices) stays but nothing reads it.
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
