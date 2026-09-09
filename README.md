# Attention Stack

A tiny macOS menu bar app: a quick stack of "things I opened and must return to".

## Build
```
./build.sh
```

## Run
```
open "build/Attention Stack.app"
```
The icon appears in the menu bar (no Dock icon). Type in the field and press Return to add; newest goes on top.

Each item can be linked to one app. A new item is linked automatically to whatever app was in front before you opened the panel; click the link icon on a row to unlink, and click it again to re-link the current front app. Clicking a linked item's text brings that app forward.

## Install
Drag `build/Attention Stack.app` into `/Applications`.

## Data
Items are stored as JSON at `~/Library/Application Support/AttentionStack/items.json`.
