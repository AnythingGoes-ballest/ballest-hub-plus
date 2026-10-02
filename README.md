# Hub Plus

A plugin for the [Ballest plugin manager](https://github.com/AnythingGoes-ballest/ballest-plugin-manager): the game's
track hub, plus search. Hub Plus adds a row to the hub itself, under its header, and shows everything in the hub's own
list. Paging, the info panel, medals, the queue and the play button all work as they always do.

```
[search maps, or authors by name ......................................................... x]
[top rated ..........v] [any author ............v] [any progress ..........v]
Showing 19 of the 25 maps on this page (not finished)
```

## Search

- **Maps:** type: the hub's list shows the results once you pause (Enter searches at once). Steam searches map
  titles, descriptions and tags. The **x** at the box's end empties it and keeps the hub on the page it's on.
- **Authors by name:** searching also fills the author list with every author whose name matches, with how many maps
  each has. Pick one to see their maps.
- **More by this author:** a button after the author's name in the hub's info panel shows the rest of their maps.
- **Downloads:** on the hub's downloads page, typing narrows your downloaded maps right there, by map or author name.
- **The hub's own filter panel still applies:** tags picked there narrow every Hub Plus search too.

## Players

Every map's thumbnail (Home, the list and downloads) shows how many players have it: Steam's count of unique
subscribers, next to a little person.

## Sort

The game's own sorts (best match, top rated, trending today, this week, this month or this year, newest, oldest,
name, recently updated) and Steam's (most played, most subscribed, most liked). A text search starts on best match.
One author's maps sort by newest, oldest, name, recently updated or top rated (the others don't apply to one
player's maps on Steam).

## Your progress

Shows only the maps on each page that are: not played, played but not finished, not finished, finished, without a
gold medal yet, or without an author medal yet, on the list and on downloads. The others on the page are hidden, and
the row says how many are left. It works page by page: the hub's own page buttons move through the rest.

## Install

In the game: footer **plugins** > **browse** > Hub Plus > **install**. Needs the plugin manager host 0.23.0 or
newer.

## How it works

- **Searches:** `Hub::Search` makes them the way the game makes its own: its query builder, then its list. `Hub::HideEntry`
  hides maps on the list. The row is a plugin window docked into the hub (`Window.DockInHub`); the author button is
  `Hub::SetAuthorButton`, the player counts `Hub::SetEntryBadge` with `Workshop::Subscribers`.
- **Author names:** every map is loaded once a session in the background (`Workshop::Find`) to learn who made what.
  Their names come from Steam (`Workshop::Name`) and are kept between sessions, so author search works straight away.
- **Your progress:**
  - Finished maps and medals: the game's save (`Workshop::MyMedal`).
  - Played maps: Steam's list of the maps you've played, the save, and the workshop maps this plugin has seen you on.

## License

MIT
