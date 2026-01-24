# nvim-eject
Temporarily rip regions out of one buffer and edit them in another.

## Features
- Edit pieces of a buffer in another
- Automatically use treesitter injections
- Customize opening of the window for the new buffer (floats, splits etc.)

## Installation
Use any plugin manager and call `require("eject").setup{}`.
Lazy loading is *not* necessary, the majority of the plugin is only loaded once a
keybinding is executed.

### Keymaps
Eject does *not* create any default keymaps or plugin maps.
Simply map the lua functions `require("eject").eject_operator` and/or `.eject_ts_injection`.
Some possible mappings are: `cp` - **C**hange in **P**opup, and `cP` for the treesitter
version.

## Usage
(This assumes that you have the functions mapped as `cp` and `cP` respectively)

Type `cp<textobject>` to open a region of the buffer in a split.
Do your edits normally, while this buffer is open, the buffer that it is ejecting content
from is readonly to protect you from conflicts.
Once you're happy with any changes, write them like you normally would (`:w` for example).
Once you close that buffer, the original buffer is modifiable again.

In order to edit a treesitter injection, simply place your cursor anywhere on it and press
`cP`.
