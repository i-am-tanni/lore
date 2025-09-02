# Lore

This is an experimental re-write of a Multi User Dungeon (MUD) engine in Gleam
from Elixir. It is still in early stages.

The architecture takes inspiration from [Kalevala](https://github.com/oestrich/kalevala)
written in Elixir by Eric Oestrich. Big thanks to Eric!

A good place to start with the codebase is the endpoint for the telnet
connection at `src/lore/server/telnet/protocol.gleam`.

## Features

- ✅ Network I/O is fully async
- ✅ Rooms, zones, and characters fully async
- ✅ Look command
- ✅ Movement
- ✅ Doors
- ✅ Room communication (says, whispers, and emotes)
- ✅ Chat channels
- ✅ ASCII Map
- ✅ Color (16 and 256 colors)
- ✅ Who command
- ✅ Items
- ⬜ Socials
- ⬜ Spawn mobiles
- ⬜ Postgres
