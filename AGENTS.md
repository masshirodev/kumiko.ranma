# AGENTS.md

lattice.ranma is a ranma plugin in Lua: `plugin/lattice.lua` is all of it, and
its header comment is the reference that `README.md` repeats. ranma's API is
https://github.com/masshirodev/ranma/blob/main/doc/CONFIG.md (`ranma --dump-types` prints it as LuaLS annotations).

- Push to `main`.
- A change to what it does changes the header comment and `README.md` in the
  same commit, and an option goes in the README's table.
- Check it loads: `ranma --check-config` lists every plugin and why one failed;
  `ranma lua` runs code in the live server.
  CI (`.github/workflows/ci.yml`) loads it into the latest ranma release on
  every push and fails if it does not.
- It is read-only against the board, and stays so: only `GET`s. Test anything
  new against a fake server (`lattice.url` pointed at it), never by changing
  cards on the real board.
- Read a JSON field through `str()` or `list_of()`: ranma's `json.decode`
  turns `null` into a userdata that is truthy, so `x or ""` does not catch it.
- `AGENTS.local.md` (gitignored) carries what is true of one checkout on one
  machine. Never commit it.
