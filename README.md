# Lore

This is a multi-user dungeon (MUD - aka a text based MMO) server written in
Gleam. It's still early stages and a work in process.

The architecture takes inspiration from [Kalevala](https://github.com/oestrich/kalevala) written in Elixir by Eric Oestrich. Thanks Eric!

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
- ✅ Postgres
- ✅ Socials
- ⬜ Spawn mobiles
