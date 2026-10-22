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

Add it only once the plugin is installed: a bar naming a module that no installed plugin declares makes every config reload fail.

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

A card id in a pane's text (`c2462`, or the whole `c2462-tests-leave-…`),
as openpath.ranma treats a path, on the board of that pane's repository:
  ctrl+click         the card whole on a screen (enter types the reference,
                     y copies it, w opens the browser), or the browser
                     itself when kumiko.click says so.
  ctrl+right-click   a list: view it, the browser, type the reference into
                     the pane, copy the reference, the id or the address.
  hover              a tooltip: the title, the column, labels, checklist
                     (kumiko.hover; needs the mouse on, the `mouse`
                     setting not "off"). It shows at once: "fetching"
                     until the card lands, then the card, "not on
                     <board>", or why the fetch failed. It fetches a card
                     once per kumiko.refresh and never asks which board.
A link, or a word that is a file in the pane's directory, is left to
openpath and linkhover. Alt+click works the same as Ctrl+click.

Which board: a `.kumiko` file at the repository's top saying
`board = <slug>` (in a worktree, its own or its main checkout's); else
kumiko.boards, mapping a repository's directory name to a board slug
(`kumiko=work-hours *.ranma=ranma`); else the board whose slug is the
repository's name, and with none the picker asks which board. A worktree
counts as its main checkout; a `.git` that is not a repository (a stub
directory with no HEAD) does not count, and the search goes on above it. Pins are kept in ranma.store("kumiko").
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
| `ctrl+click` a card id | a pane's text | The card on a screen of its own (or the browser, with `kumiko.click`). |
| `ctrl+right-click` a card id | a pane's text | View, browser, type the reference, copy the reference, id or address. |
| hover a card id | a pane's text | A tooltip with its title, column, labels and checklist. |

## Which board: `.kumiko`

A repository names its board in a `.kumiko` file at its top, which beats both `kumiko.boards` and the guess from the directory's name:

```ini
# the Kanban board this repository's cards are on
board = work-hours
```

Commit it when the board is the repository's for everyone; add it to `.git/info/exclude` when it is yours alone. A worktree reads its own, or its main checkout's when it has none (an untracked one is not copied into a worktree). The file is read each time, so an edit counts at once.

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
| `kumiko.click` | `view` | What ctrl+click on a card id does: `view` the card in ranma, or open it in the `browser`. |
| `kumiko.hover` | `true` | A tooltip with a card's title, column, labels and checklist when the pointer rests on its id. |
| `kumiko.width` | `32` | The most characters of a card's title the bar shows. |

## How it talks to the API

Every request is `curl` started with `ranma.spawn`, so nothing waits on the network inside a bind or the bar. It only sends `GET /boards`, `GET /cards?board=<slug>&role=...&fields=...`, and, for a card id clicked or hovered, `GET /cards?board=<slug>&q=<id>&fields=...` (the API reads one card by its whole id only, so a short `c2462` is found by search, which covers every column). The token is written by the shell's own `printf` into curl's `--config -` on stdin, so it is never in an argument list that `ps` shows.

## License

MIT or Apache-2.0, as ranma.
