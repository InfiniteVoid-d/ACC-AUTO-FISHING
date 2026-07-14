# Walkthrough: Auto Fisher Development Cycle (v1 - v10)

We successfully developed and polished a high-performance Auto Fisher script for **Anime Card Collection (Fish It! minigame)**. The final version (v10) uses an advanced upvalue-manipulation exploit to bypass the click minigame entirely with zero input lag, featuring an interactive UI slider to control the catch delay.

## Progression Summary

### v1 - v2: The Foundation & Click Simulation
- **V1:** Implemented basic click simulation using `VirtualInputManager`.
- **V2:** Upgraded with a custom UI, dual-mode toggle (Legit/Blatant), parallel casting options, and stats tracking.
- **Result:** Blatant mode was silenty rejected by the server because firing `FishCaught` instantly (0.3s) triggered server-side safety checks.

### v3 - v5: Input Lag Mitigation
- **V3 - V4:** Added multiple strategies (Turbo clicking, Direct catch with wait delays, UI manipulation). 
- **Findings:** Discovered the game's minigame loop is purely client-side but relies on internal state variables rather than visual progress bar sizes. Spamming clicks at extremely high speeds (`0.001s`) flooded the client's input queue, freezing UI button interactions.
- **V5:** Resolved input lag by adjusting click delays to `0.02s` and using `RenderStepped:Wait()`. Locked in perfect casting values (`1.0`).

### v6 - v8: The Upvalue Exploit
- **V6:** Located the `RenderStepped` loop inside `FishHandler` in client memory. Discovered upvalues:
  - `UV[6]` (`v17`): Current progress score.
  - `UV[8]` (`v18`): Target score needed to catch.
- **V7:** Tried to freeze `UV[6]` at 50% using a `task.wait(0.1)` loop during the delay to prevent escapes.
- **V8 (The Breakthrough):** Realized that setting `UV[6]` in a loop was too slow since the game drains progress every frame. Instead, v8 targeted the drain rate upvalues directly:
  - `UV[15]` (`v19`): Passive drain rate.
  - `UV[14]` (`v26`): Active hold drain rate.
- **Result:** Setting both drain rates to `0` froze the progress bar at 50% visually with zero CPU overhead, resolving the escape bug.

### v9 - v10: State Machine Sync & UI Slider
- **V9:** Fixed the 3-7s random bite delay bug. The script now monitors the minigame status upvalue (`UV[1]`) in the background and only fires the exploit when the game is actively running.
- **V10 (Final):** Added an interactive UI slider to adjust `InstantCatchDelay` from `0.1s` to `5.0s` dynamically.

## Verification & Testing
- Tested at **0.1s delay** in *Anime Card Collection*.
- Confirmed: Zero input lag, no client freezes, no fish escapes, and perfect catches every time.

---

## v56 and Bug Fixes: Scoping & Background Automation Lifecycles

In the v56 update, we addressed critical scoping and lifecycle management issues that were causing parts of the exploit and the background automation to malfunction.

### 1. Hook Scoping Bug (The "FishEscaped" Blocker)
- **Problem:** The local variables `autoFishing` and `Config` were referenced inside the client-side namecall metatable hook closure before they were declared. This caused the compiler to treat them as global variables (which remained `nil`). Consequently, the safety checks in the hook would never pass, rendering the blatantly instant strategy unsafe as `FishEscaped` signals were never blocked.
- **Solution:** Forward-declared `local autoFishing = false` and `local Config` at the very top of the script (before line 18) so they are in scope for the namecall hook. Removed the redundant `local` qualifiers from their lower definitions.

### 2. Background Task Lifecycle and Toggles
- **Problem:** Features like *Collect Map Tokens*, *Dragon Balls*, *Auto Wish*, *Auto Roll*, *Auto Raid*, and *Auto Voyage* shared a single background thread (`collectTokensThread`). Toggling any of these options off would invoke `cancelCollectTokensThread()`, killing the thread entirely and stopping all other concurrent features. Additionally, the checks on startup and `startAutoFish` only evaluated 4 of the 6 features, leaving *Auto Voyage* and *Auto Wish* dead on initialization.
- **Solution:**
  - Upgraded `startAutoCollectTokensLoop()` to calculate `anyActive` dynamically, shutting down only if all 6 features are disabled.
  - Allowed `startAutoCollectTokensLoop()` to return early if the thread is already running, preventing duplicated tasks.
  - Refactored UI toggles to call the thread manager `startAutoCollectTokensLoop()` directly rather than canceling the thread.
  - Expanded the startup checks to include all 6 features.
  - Refactored `stopAutoFish()` to only call `cancelCollectTokensThread()` if neither *Auto Raid* nor *Auto Voyage* is active.

---

## v57: Game Update Fix — Reliable Instant Catch via Sound Hooks

In the v57 update, we resolved a critical failure where the instant catch strategy failed to catch fish after the game's server-side update.

### 1. The Instant Catch Failure (Server-Side Validation)
- **Problem:** The server now validates that a fish cannot be caught before the bite minigame actually starts (which has a random 3-7s delay after casting). Firing the `FishCaught` remote immediately after casting would lead to a server-side rejection, resulting in a `"FishEscaped"` event.
- **Solution:** Instead of waiting blindly after casting, we hooked into the client's `FishAlert` sound object (`ReplicatedStorage.Assets.Sounds.Fish.FishAlert.Played`).
- **Implementation:**
  - When `StartFishing` is received, we establish a connection listening for the `FishAlert.Played` event.
  - When the sound plays (signaling the minigame has officially begun), we wait for the user's custom `InstantCatchDelay` (default 1.2s) and then fire `FishCaught`.
  - Added cleanups to disconnect the `_G.BiteConnection` on script stopping/re-runs to avoid memory leaks.

---

## v58: Cooking & Rod Crafting Ingredient Protection

In the v58 update, we introduced dynamic ingredient protection to prevent the auto-sell duplicates module from selling fish required for cooking recipes or rod crafting.

### 1. Ingredient Scraping
- **Problem:** If a player enabled "Sell Duplicate Fish", the script would blindly sell any fish where count > 1. This destroyed valuable ingredients needed for cooking fish luck recipes or crafting new rods.
- **Solution:** We introduced `getRequiredIngredients()` which queries the game's `FishConfig` (specifically `FishConfig.Recipes` and `FishConfig.Rods`) dynamically at runtime.
- **Implementation:**
  - Scrapes the maximum amount needed for any ingredient across all recipes and rods.
  - Updates `sellDuplicates()` to keep the exact count of each required ingredient in inventory.
  - Keeps 1 copy of any non-ingredient fish for the player's index/collection.
  - Added a `"Protect Ingredients"` toggle in the GUI Automation tab with the corresponding config setting.

---

## v59: Pet Quests Automation

In the v59 update, we added the "Auto Pet Quests" feature to automatically complete pet quests before their 3-hour refresh countdown expires.

### 1. Quest Logic and Automation
- **Problem:** Pet quests refresh every 3 hours (`PetQuestRefreshTime = 10800`). If a player doesn't complete them in time, they miss out on Pet Tokens.
- **Solution:** We integrated a background scanner that reads the player's active pet quests and automatically progresses them.
- **Implementation:**
  - Added the `"Auto Pet Quests"` toggle in the UI (renamed the card to "PETS & QUESTS AUTOMATION").
  - Automatically handles the three major types of quests:
    1. **Potion Crafting Quests:** Automatically crafts `HatchTime1` or `Luck1` using card packs if the player has the required ingredients.
    2. **Tower Quests:** Automatically teleports/starts a Tower run when the quest is active and the player is not currently in the tower.
    3. **Place Packs Quests:** Automatically places owned card packs from inventory onto the conveyor belt to be opened.
  - Shifts subsequent UI cards down by 18 pixels to accommodate the new toggle in the Pets card.

---

## v60: Auto Pack Opener and Luau Register Optimization

In the v60 update, we resolved a Luau compiler limit issue and implemented a fully automated "Auto Pack Opener" system.

### 1. Luau 200 Register Limit Optimization
- **Problem:** Adding the new "AUTO PACK OPENER" card and shifting layout elements introduced more local variables in the outer script scope. Inherited by the button click nested `do ... end` block, this pushed the local registers beyond Luau's limit of 200, causing a compilation crash on loading (`Out of local registers when trying to allocate raidModesList`).
- **Solution:** Converted 50+ GUI element variables and forward-declared functions from `local` to globally bound variables. Deleting the redundant forward declarations freed up dozens of local registers, bringing the file scope register count down to a highly stable ~130.

### 2. Auto Pack Opener System
- **Problem:** Opening card packs manually is a chore: packs must be equipped, placed on a grid-locked base floor, left to hatch, and then collected by pressing "E".
- **Solution:** Created the `"AUTO PACK OPENER"` card containing:
  - `"📦 Auto Place/Open Packs"` (toggle)
  - `"🎯 Target Pack:"` (text input to define target pack name, default `"Ghoul"`)
  - `"🧪 Auto Apply Potions"` (toggle)
- **Implementation:**
  - **Auto Placement:** Checks the player's current placed packs count against `MaxPlacements`. If there is space and target packs are owned in inventory, the script programmatically equips it to slot 1, equips the tool on the character, places it on the floor via `Card:FireServer("Place")`, and unequips the tool.
  - **Auto Potion Speedup:** If enabled and packs are hatching, the script automatically applies any owned hatch time potions (`HatchTime3` -> `HatchTime2` -> `HatchTime1`) via `Potion:FireServer("Apply")`.
  - **Teleport Collection:** Scans `workspace.Plots[plotName].Packs` for ready pack models. When it detects a `ProximityPrompt` with the `"Open Pack"` action, it teleports the player's HumanoidRootPart directly to the pack, fires the prompt (via `fireproximityprompt` or fallback event triggers), waits, and returns the player to their original position instantly.

---

## v61: Stackable Cooking Ingredient Preservation

In the v61 update, we modified the ingredient protection logic to allow stacking recipe durations infinitely.

### 1. Complete Ingredient Preservation
- **Problem:** In v58, ingredient protection only kept the maximum count required to cook a recipe or craft a rod once (e.g., keeping only 5 Tilapia). However, cooking multiple times stacks the luck duration (e.g., stacking 1,000+ Tilapia/Tuna allows for hours of stacked cooking luck). The previous auto-sell duplicates logic sold off all copies beyond the single-craft requirement, destroying the player's ability to stack luck.
- **Solution:** Modified `sellDuplicates()` to evaluate if a fish name is listed *anywhere* in the cooking recipes or rod crafting requirements configuration.
- **Implementation:**
  - This allows players to hoard thousands of Tilapia, Tuna, and other ingredients to stack their cooking luck durations indefinitely, while still automatically purging duplicates of non-ingredient fish.

---

## v62: UI/UX Mobile Rework & Advanced Automation

In the v62 update, we completely revamped the UI/UX to make it friendly for mobile and tablet players, and implemented full Auto Cooking and Auto Rod Upgrading automation.

### 1. Collapsible Sidebar & Scrolling Container Layouts
- **Responsive Layout:**
  - Added a touch-friendly `☰` hamburger menu button in the top-left of the title bar to collapse/expand the sidebar frame dynamically via tween animations.
  - On PC, the sidebar starts opened. On mobile/touch devices, the script automatically detects the platform and starts with the sidebar collapsed, maximizing screen space for mobile controls.
  - Converted the `"Fishing"` and `"Conveyor"` tabs from static frames into `ScrollingFrames` with customized canvas boundaries. Touch users can now scroll effortlessly to configure settings without UI overlap.
  - Increased button heights and toggle touch targets to 24px (standard mobile target size) to ensure fingers can comfortably tap options.

### 2. UI Scale Factor Slider
- **UIScale Implementation:**
  - Added a `UIScale` object to the parent frame structure.
  - Implemented an interactive "UI Scale" slider in the `"AUTOMATION MODULES"` card. Dragging or tapping the slider dynamically scales the entire UI frame from `0.7x` (compact) to `1.5x` (large).
  - Designed the slider knob to support touch drag inputs via `UserInputService.InputChanged` for touchscreen devices.

### 3. Auto Cooking Manager
- **Automation Loop:**
  - Added `"🍳 Auto Cooking Manager"` toggle and `"🎯 Cooking Target"` cycle selection button in a new `"COOKING & ROD AUTOMATION"` card.
  - When enabled, the background thread checks if you have the required Fish Tokens and unequipped/unlocked ingredients for your target dish. If met, it fires the `Fish:Cook` remote. This allows stacking luck buffs infinitely in the background while you fish!

### 4. Auto Rod Crafter
- **Automation Loop:**
  - Added `"🎣 Auto Upgrade Rod"` toggle to the `"COOKING & ROD AUTOMATION"` card.
  - When enabled, the background thread automatically checks if you meet the requirements to craft the next rod in the progression path. If requirements are met, it fires the `Fish:CraftRod` remote.
  - It also automatically equips your best owned rod using `Fish:EquipRod` if it isn't currently equipped.

---

## v63: Robux Purchase Prompt Prevention

In the v63 update, we resolved a critical issue where the auto-buy packs feature triggered annoying Robux purchase/top-up prompts when the player had insufficient Yen.

### 1. Multiplied Price & Suffix Parsing
- **Problem:** Previously, our auto-buy check only evaluated the base price of normal packs against the player's Yen. If a pack was Gold (5x), Emerald (10x), Void (25x), Diamond (60x), or Rainbow (140x), the check failed to account for the multiplier, thinking the player could afford it when they actually couldn't. Additionally, price tags on the conveyor models like `"$120OC"` parsed as a raw number of `120`, leading to false positives. Firing the `BuyPack` remote with insufficient funds caused the server to automatically prompt a Robux top-up window.
- **Solution:** 
  - Created a robust abbreviation suffix parser (`parseAbbreviatedNumber`) that translates suffixes (K, M, B, T, Q, QN, S, SP, OC, N) into actual raw numbers for exact comparisons.
  - Multiplied the base pack price by the corresponding mutation multiplier dynamically in `getPackPrice(packType, mutation)`.
  - Added a strict price validation gate. If the price cannot be resolved or parsed, the script skips the pack as a safety measure.
  - If the player's Yen is less than the actual multiplied cost, it logs the difference in the debug logs and aborts the purchase remote call, preventing the annoying Robux prompt from ever popping up.

---

## v64: Persistent Configuration Saving & Loading

In the v64 update, we implemented automatic settings preservation so that the player's custom configurations carry over seamlessly between script executions.

### 1. JSON-Based Configuration File
- **Problem:** Every time the player executed the script (due to reconnects, lobby changes, or starting a new play session), they had to manually re-configure all their toggles, wish types, egg selections, and targets, which was tedious and time-consuming.
- **Solution:** 
  - Created a robust serialization block using Roblox's native `HttpService:JSONEncode` and `HttpService:JSONDecode`.
  - Added `loadSettings()` at startup to check if `AnimeCardCollection_Config.json` exists in the executor's workspace folder (using `isfile` and `readfile`). If found, it programmatically merges the saved key-value pairs back into the active `Config` table, including recursively restoring the nested `SelectedItems` selection maps.
  - Safe-wrapped all file reads/writes in `pcall` gates to ensure that if a player runs the script in an environment without file I/O permissions, the script falls back cleanly to defaults instead of crashing.

### 2. Periodic Autosave Daemon
- **Debounced Save Loop:**
  - Instead of adding saving lines to 50+ individual button click connections (which would clutter the code and increase the top-level register count beyond the 200 limit), we implemented a lightweight, periodic background daemon (`task.spawn`).
  - Every 2 seconds, the daemon performs a fast JSON check on the `Config` table. If it detects a difference from the last saved state, it writes the updated table to disk (debounced autosaving). This handles all sliders, toggles, text boxes, and dropdown values effortlessly with 100% coverage and zero UI lag.

---

## v65: Separate Exclusions & Auto All Cooking Manager

In the v65 update, we split the ingredient protection system into separate Cooking and Rod crafting toggles, and added a smart "Auto All" cooking target.

### 1. Split Ingredient Protection Toggles
- **Problem:** Previously, the single "Protect Ingredients" option locked 100% of both cooking and rod crafting ingredients. If a player wanted to sell off common fish duplicates (like Roach or Chub) to make cash while still keeping Tilapia/Tuna for cooking luck, they couldn't. 
- **Solution:** 
  - Split the configuration into `Config.ProtectCookingIngredients` and `Config.ProtectRodIngredients`.
  - Added two separate UI toggles in the Automation Modules card: `"🍳 Protect Cooking"` and `"🎣 Protect Rod Craft"`.
  - The `sellDuplicates()` engine evaluates these separately, allowing players to hoard cooking ingredients for luck stacks while safely purging rod crafting fish for Yen (or vice versa).
  - Shifted all other toggles and rows in the grid container down by 18 pixels and updated the `automationTab` CanvasSize dynamically to `1078`.

### 2. "Auto All" Cooking Target
- **Problem:** The auto-cooker was locked to a single selected recipe target. If the player went AFK and ran out of ingredients for that specific target, the auto-cooker stopped completely, wasting valuable AFK time.
- **Solution:** 
  - Added a new target option `"Auto All"` (set as the default).
  - When `"Auto All"` is selected, the cooking loop automatically evaluates all available recipes in descending order of luck power (Platter -> Steam Fish -> Stew -> Porridge -> Crispy Fried Fish). 
  - If you have the required tokens and fish ingredients for the best possible dish, the loop fires the cook remote, letting you automatically cook whatever is available in your inventory while AFK!






