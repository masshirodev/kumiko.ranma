# kumiko.ranma

A plugin for [ranma](https://github.com/masshirodev/ranma), the terminal tiling window manager: the Kanban board of the repository you are in, from [Kumiko](https://kumiko.ink), as a picker, a screen and a bar module.

## Install

With [hako](https://github.com/masshirodev/hako.ranma), in `~/.config/ranma/lua/plugins/kumiko.lua`:

```lua
return { "masshirodev/kumiko.ranma" }
```

Or by hand, as ranma loads any package under `pack/*/start/`:

```sh
git clone https://github.com/masshirodev/kumiko.ranma ~/.config/ranma/pack/plugins/start/kumiko.ranma
```

Needs: ranma 0.2.2 or newer (the first with `ranma.refresh_module`, and with `json.decode` giving `nil` for `null`), `curl` and `sh`, an API token for the Kanban API in the environment ranma's server starts with (`LATTICE_MCP_TOKEN` by default), and `xdg-open` for `w`.

The bar module is not placed for you. Add it where you want it:

```lua
ranma.bar { right = { "kumiko", "datetime" } }
```

## What it does

```text
kumiko: the Kanban board of the focused pane's repository, from the terminal.

leader K   (shift+k) a picker over the board's cards still to start or under way
           (Kumiko's active columns first, then intake); choosing one types
           `<id> ("<title>")` into the pane, without Enter, the way a card
           is named in a commit or in a message to an agent.
In the palette (leader :): `card [board]` is the same picker, on another
board when one is named; `board [board]` opens a screen of those cards by
column, with each one's labels, description and checklist under it. On it:
  enter  type the reference into the pane     y  copy it
  v      the card whole: description, checklist (esc comes back; enter, y)
  p      pin it to the bar (again: unpin)      w  open it in the browser
  r      fetch again
The bar: a module named `kumiko` shows the repository's In Progress card
(the pinned one, else the first), cut to kumiko.width, and `+N` for the
others; a click opens the screen. It fetches when focus or a pane's
directory moves to a repository it has not fetched, and every
kumiko.refresh seconds, only while the bar shows it, never per frame;
what it fetched shows at once.

Another key: ranma.bind(KEY, function() ranma.emit("kumiko_card") end), or
"kumiko_board" for the screen; a board's slug as emit's data names one.

Which board: kumiko.boards maps a repository's directory name to a board
slug (`kumiko=work-hours *.ranma=ranma`); any other repository uses the
board whose slug is its name, and with none the picker asks which board. A
worktree counts as its main checkout. Pins are kept in ranma.store("kumiko").
Read-only: it never creates, moves or edits a card. The API token is read
from the environment variable kumiko.token_env and reaches curl on its
stdin, never in a process's arguments.

Needs ranma 0.2.2 or newer, the first with ranma.refresh_module and with
json.decode giving nil for null.
```

| Key or command | Where | Does |
| --- | --- | --- |
| `leader K` (`shift+k`) | WM mode | The picker over this repository's board. |
| `card [board]` | palette (`leader :`) | The same picker, on another board when named. |
| `board [board]` | palette | The screen of the board's cards. |
| `enter` `v` `y` `p` `w` `r` | the screen | Type the reference, view the card, copy, pin, browser, fetch again. |

To put the picker on another key, drop the default and emit the plugin's event (`kumiko_board` opens the screen; a board's slug as the data names one):

```lua
ranma.unbind("shift+k")
ranma.bind("ctrl+k", function() ranma.emit("kumiko_card") end, { desc = "kumiko card", exit = true })
```

## Options

In ranma's settings panel under `kumiko`, or with hako's `opts` (`{ "masshirodev/kumiko.ranma", opts = { ... } }`), or `ranma.set { kumiko = { ... } }`.

| Option | Default | |
| --- | --- | --- |
| `kumiko.url` | `https://kumiko.ink/api/kanban` | The Kanban API's base URL: `/boards` and `/cards` are under it. |
| `kumiko.token_env` | `LATTICE_MCP_TOKEN` | The environment variable holding the API token, in the environment ranma's server started with. It keeps the app's old name on purpose: that is the variable Kumiko's own tooling sets. |
| `kumiko.boards` | `kumiko=work-hours wayfarer=main kuji=rents-due hansei=heimdall kizuna=ai-session *.ranma=ranma` | `repository=board` pairs, space-separated; `*.suffix` matches the end of a name. Any other repository uses the board named like it. |
| `kumiko.refresh` | `300` | Seconds between the bar's fetches of a board. |
| `kumiko.width` | `32` | The most characters of a card's title the bar shows. |

## How it talks to the API

Every request is `curl` started with `ranma.spawn`, so nothing waits on the network inside a bind or the bar. It only sends `GET /boards` and `GET /cards?board=<slug>&role=...&fields=...`. The token is written by the shell's own `printf` into curl's `--config -` on stdin, so it is never in an argument list that `ps` shows.

## License

MIT or Apache-2.0, as ranma.
