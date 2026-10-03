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

Capture adds an item without typing: it is named after the app that was in front, or, when that app is Claude, after the title of the Claude Code session on screen.

🧻 opens the next paper from the reading list at `~/agent_brain/04-research/papers/_inbox.md`: the highest-scoring row still `queued`, oldest first among ties. The paper opens in the browser and joins the stack, and clicking that item reopens it. The inbox file is only read, never written — a paper keeps coming up until you retire its row in chat.

💡 opens a random idea from [r/SomebodyMakeThis](https://www.reddit.com/r/SomebodyMakeThis/), where people post things they want built but have no time to build. The idea only opens in the browser; unlike a paper, it does not join the stack, since it is something to look at now rather than something to come back to. Ideas already shown since the app started are passed over, so a second click gives a second thing to look at, until the pool runs out and repeats start. Reddit's JSON API needs an account, so this reads the public Atom feed instead: one of the "top" feeds at random, up to 25 ideas at a time, cached for six hours. Clicks inside that window cost nothing; afterwards the next click fetches again, and falls back to the expired pool when it is throttled or you are offline. The button only beeps when there is nothing cached to fall back to.

Each item can be linked to one app. A new item is linked automatically to whatever app was in front before you opened the panel; click the link icon on a row to unlink, and click it again to re-link the current front app. Clicking a linked item's text brings that app forward. When the app in front is Claude, the link also remembers the Claude Code session on screen and reopens it.

## Claude Code sessions join on their own
Click **Track Claude** once (it shows until the hooks are in place). It adds user-level hooks to `~/.claude/settings.json`, keeping everything else there and a copy of the original beside it as `settings.json.attention-stack-backup`. From then on every Claude Code session on this Mac, in the terminal or in the desktop app's Code tab, joins the stack at its first prompt without any typing. Cloud sessions on claude.ai do not run your local hooks, so they are not tracked.

A session row is named after its folder and first prompt, or after the desktop app's title for that session once there is one, and its badge follows the session:

- blue dotted circle: working
- orange !: waiting on a permission or a question
- green check: finished, not looked at yet
- grey circle: finished and looked at

The menu bar icon gains a ! while any session is orange or green. Clicking a row brings back the app the session runs in (reopening the session itself for the desktop app) and counts as looking at it, as does sending the session a new prompt. A session leaves the stack once it has closed and you have looked at it; ✕ removes it sooner, and it only comes back with a new prompt. When a closed terminal session is clicked, `cd <folder> && claude --resume <id>` is left on the clipboard.

The hooks run `AttentionStackHook` from inside the app bundle, in the background, so a session never waits on it. It drops each event into `~/Library/Application Support/AttentionStack/events/`, keeping only the session id, event name, folder, notification type, the first 200 characters of a prompt, and the app the session runs in. The app reads and deletes them, including any that piled up while it was closed. Moving the app breaks the hook path; **Track Claude** reappears and fixes it.

## Install
Drag `build/Attention Stack.app` into `/Applications`.

## Data
Items are stored as JSON at `~/Library/Application Support/AttentionStack/items.json`, and the cached pool of ideas sits beside it in `ideas.json`.
