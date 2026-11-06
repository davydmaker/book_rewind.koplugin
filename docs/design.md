# Book Rewind: design and tools

A year of reading as a set of cards, in the style of a yearly recap, generated on the device from KOReader's statistics, with no internet. `book_rewind` is the plugin identifier. The research behind the idea is in `docs/research/year-recap.md`, in the `kindle` project.

## How it works

- In English, Portuguese and Spanish, following KOReader's language. In any other language, it uses English.
- It lives in the Tools menu, as **Book Rewind**. It opens on the most recent year with at least 10 minutes of reading, and the cover offers the neighbouring years that also reach that minimum. In the first 30 days of a year, it opens on the year that just ended, if that year reaches the minimum, and the new year stays on the button.
- A tap on the right or a swipe moves forward. A tap on the left third moves back. On devices with keys, the page keys navigate and the back key closes; changing the year and sharing need touch.
- It reads `koreader/settings/statistics.sqlite3` read-only. With a book open, it first writes the pages the statistics plugin still keeps in memory.
- **Share**, on the summary card, opens a screen with a QR code. See [Sharing](#sharing). Nothing is written to KOReader's screenshots folder, and images saved there by older versions stay untouched.
- If the screen cannot open, KOReader shows a short notice and the rotation is restored. If one card cannot be drawn, it shows a message in its place, and the other cards stay reachable. Both go to the KOReader log.
- If no year has 10 minutes of reading, it shows an invitation to read more, with the minutes still missing, instead of the cards. A missing or unreadable database counts as no reading.
- If the current year does not have 10 minutes yet, the cover of the most recent year says how many minutes are missing. That notice stays out of what is shared.
- Each card only appears when there is data for it, so a short history still makes a coherent sequence.

## Cards

Cover, time, pages, books, timeline of finished books, devoured book, top author, longest streak, biggest day, longest session, hours, weekday, best month, pace, wildcards, comparison with the previous year, profile, summary and about. The About card is the last one, right after the summary, and is not shared.

### Wildcards

Rare cards in `wildcards.lua`, with their content in `wildcard_cards.lua` and their drawings in `ui/wildcard_paint.lua`. Each year shows up to 3, the ones that stand out the most for that reader, scored like the profile traits: 1 at the minimum and 2 at what is exceptional. Cards about pauses do not appear together, and one book does not star in two cards. A year with nothing remarkable shows none. The minimums are proposals, to be calibrated with real histories.

| Card | Appears when | Score reaches 2 at |
|---|---|---|
| Comeback | The longest pause inside the year has 30 days or more | 120 days |
| Back after years | At least a year without reading before this year, with at least 10 minutes in the last year read | Always 2 |
| Waves | 3 or more pauses longer than two weeks | 8 returns |
| The book that waited | A finished book stopped for 30 days or more before reaching the end. The page where it stopped is in the book's own pagination | 180 days |
| Couldn't put it down | A whole book, with 30 pages or more, started and read to the end on the same day | 300 pages |
| Slow burn | A finished book that took 90 days or more to reach the end | 240 days |
| Reread | At least 90% of a book finished in an earlier year read again. The count of readings walks the earlier history in time order: each time it covers 90% of the book is one reading, and the next one starts from zero | Fixed at 1.7 |
| Series run | 3 or more finished books of the same series. The `series` metadata comes first, then a volume in the title (`Vol`, `Volume`, `Livro`, `Book` or `Tomo`, with an arabic or roman number), `[Name 2]` or a final roman numeral after at least two words, then the same author with titles sharing a final parenthesis or the same two opening words. Numbers, two very short words and generic openings such as `Curso de` do not count. The name is the longest opening those titles share | 6 books |
| Juggler | 3 or more books open at once. A pause over two weeks closes a book for this count, and so does reaching the end | 8 books |
| So close | A closed year with a book stopped between 70% and 90%, not read in later years | 90% |
| Shortest to longest | A finished book at least 3 times longer than another | 15 times |
| Most marked | A finished book with 10 highlights or more. The `highlights` and `notes` fields are totals for the book, not per year | 100 highlights |
| End to end | A closed year with 5 books or more, with the first and last at least 180 days apart | Fixed at 1.02 |
| Ritual | 20 reading days or more, with sessions starting in the same two hours on at least 65% of them | 100% |
| Past midnight | 5 or more sessions crossing midnight | 30 sessions |
| A day to remember | A biggest day of 3 hours or more. It takes the place of the biggest day card | 8 hours |
| Every book's pace | Two books, with 30 pages and 30 minutes each, more than 2 times apart in time per page | 6 times |

Language and categories are not used, because they depend on metadata that is often missing or unreliable.

## Visuals

The print language of halftone, hatching and speed lines, in three themes that share the same drawings. The review that approved them is in `docs/mockups/book_rewind_color/`, in the `kindle` project.

- **Themes** live in `ui/themes.lua`: `gray` for black and white screens, `eink` for color e-ink and `vibrant` for phones. The device picks `eink` when KOReader's color rendering is on, and `gray` otherwise. Each card belongs to a family of colors, and the same family has a version in each theme. `eink` keeps the hue of `vibrant` and uses lighter fills, because dark saturated fills turn gray on color e-ink. Gray is designed on its own, because a conversion by brightness merges colors of similar brightness. Text on its background keeps a contrast of at least 4.5, checked by `tests/themes_spec.lua`.
- **Backgrounds** live in `ui/scenes.lua`, as layers of circles, rectangles and polygons in 600x800 coordinates, reaching 260 units above and below, for the height of a story and of tall phones. What only matters outside the card, like the rays of the longest session and the halftone of the summary and the biggest day, is marked so a device does not draw it. Each layer also says how it moves in a browser. The hours card has a scene per period of the day.
- **Fixed art** lives in `assets/cards/600` and `assets/cards/1200`, with no text, so it works in every language. Each file holds three masks in its color channels: ink in red, the second tone in green and the inner fill in blue. What none of them covers is transparent. `Canvas:art` colors it with the theme and puts it over the background. It is generated by `python3 -I tools/make_card_art.py`, which needs Pillow.
- **Data charts** (shelf, year map, clock, standing books, mountain, gauge and piles) are drawn in `ui/card_view.lua`, in 600x800 coordinates fitted to the screen.
- **Color** goes through roles (`BLACK`, `WHITE`, `TEXT`, `BACKGROUND` and others), tables that the drawing code and the wildcards keep and that each card fills from its theme. `TextWidget` only draws in gray, so color text goes through a mask. A text box always goes through a mask, because it would paint its background over the drawing behind it.
- **Refresh:** entering or leaving a card with a dark background redraws the whole panel, to avoid ghosting.
- **Brand:** the icon is a ribbon bookmark with a rewind mark. `docs/brand/` has the icon and the README banner, and `docs/social-preview.png` is the image for the GitHub repository settings.

## Sharing

The device only draws each card without its background and sends the data of the background, and the browser puts them together. So the animation and the image of 1080x1920 cost the device nothing, and the same drawings serve both.

1. The screen in `ui/share_screen.lua` starts a server on port 8643, in `share/server.lua`, and shows the QR code.
2. The first device with the address waits for approval, on the screen.
3. The page, in `assets/share/`, asks for `deck/<theme>`, the JSON of the backgrounds from `share/deck.lua`, and `layer/<theme>/<card>/preview`, a PNG of 600x800 with transparency.
4. To save, it asks for `layer/<theme>/<card>/story`, of 1080x1440, and draws the background and the layer on a canvas of 1080x1920. Images are saved one at a time.

A layer is drawn when first asked for, while the interface waits, and kept in `cache/book_rewind_share/` until the screen closes. `CardView.paint_layer` draws in RGB32 with transparency, even for the gray theme.

The rules follow Book Drop, without anything that receives files. None of these layers makes the connection fully secure: there is no HTTPS, so someone capturing traffic on the same network could see the recap, or the code in the address. That is why the screen warns against public networks.

| Layer | What it does |
|---|---|
| Only on while in use | The server exists while the screen is open. It closes on Stop, on sleep and after 10 minutes without use. Only the approved device counts as use. |
| One network | It listens only on the Wi-Fi address, not on USB networking. |
| Firewall | The port opens in `iptables` during the session, and the rule goes away on closing. |
| Secret code | The address carries a random code from `/dev/urandom`, new at each opening. Without it, every answer is the same 404. |
| Approval on the device | The first device with the code must be approved on the screen. Until then, it only gets the waiting page and its style. |
| One device | Once approved, no other address is served. |
| Read only | Only `GET` exists, so nothing can be sent to the device. |
| No paths | Themes and sizes come from fixed lists and cards are numbers, so no file can be chosen. Only the cards of the year on the screen are reachable. |
| Private networks only | Refuses to start outside 10.x, 172.16-31.x and 192.168.x, and refuses clients from outside. |
| `Host` check | Blocks DNS rebinding, where a malicious page open on the phone would try to reach the device. |
| Limits | Headers up to 8 KB, and 30 seconds without progress end a connection. The device in use has 6 connections of its own; the other addresses share 6 more, at most 2 each. |
| Strikes per address | 20 invalid requests block that address only. The approved device is never blocked. |
| Pages | A restrictive `Content-Security-Policy`, `nosniff`, no frames and no inline script. Texts in the JSON are escaped. |
| Space | Refuses to draw when less than 50 MB would stay free, since the cache shares its partition with KOReader's settings. |
| Errors stay contained | An error in a request ends that connection only. The error goes to the KOReader log, without the request, which carries the code. |
| After a crash | A marker file records that sharing started. If KOReader crashes with the screen open, the next start closes the port, lets the device sleep again and removes the images. |

The page takes the whole screen of the phone: the card on top, with the progress over it, and one line below with the style and the save button. The background always moves, and the saved image has it still, without the progress.

## Metrics

- **Session:** ends after 5 minutes with no reading.
- **Pages:** the count uses the part of the book each page covers. The same passage counts once, even when read again at another font size.
- **Opened book:** at least 1 minute in the year, which keeps files opened by mistake out of the lists.
- **Read to the end:** counts in the year the history reaches 90% of the book, even if the last pages took less than 1 minute. In another year, it only counts again if 90% of the book is read again in that year; if it is only reopened, it appears on the shelf as "finished before". It does not use the book status in `.sdr` files, so a book marked as finished without being read does not count.
- **When a book was finished:** the moment it reaches 90%. Opening it again later, to look something up, does not change that day, so the timeline, the devoured book, the slow burn, the book that waited, a book in one day and the series run all use it. The time a book took counts until the end of the day it was finished.
- **Biggest day:** its pages follow the same rule as the pages of the year. For a book with no page count, the pages of that day's rows are the reference.
- **Titles:** the cards drop what the file carries besides the title: site marks such as `[e-Livros]`, tags such as `(Portuguese Edition)` and `(Oficial)`, `Microsoft Word - `, file extensions, websites at the edges of the title and the author repeated at its start. Underscores become spaces in titles that look like file names. Cover lookups still use the title as stored.
- **Authors:** co-authors count separately, including `;`, `&`, `and`, `with` and commas between full names. `Last, First` and names like `Cruz e Sousa` stay whole. Dates after the name are dropped, and a shorter name of at least two words inside a single longer one counts as the same person. Generic labels (`N/A`, `Unknown`, `Windows User`, `Vários Autores`), program names (`Digital Source`, `PDFCreator`), websites and names with up to 2 letters are ignored. PDFs often carry the account that made the file in this field, and that cannot be told apart from a real name. Spellings such as `J.R.R. Tolkien` and `Tolkien, J. R. R.` count as the same person.
- **Previous year:** a year in progress is compared with the same period of the previous year. A closed year is compared with the whole previous year.
- **Profile:** the strongest trait wins, and the next one appears as secondary ("With traits of...", in a small label right below the card). Each trait has a minimum, worth 1 point, and an exceptional value, worth 2 and the cap, so one huge number cannot outweigh a whole year. With no trait, the profile is Curious Reader. On a tie, the first one in the table wins.

  | Profile | Measure | Minimum | Exceptional |
  |---|---|---|---|
  | Night Owl | Reading from 10 PM to 5 AM, above chance (7 of 24 hours) | 30% (about 50% of the reading) | 80% (about 86%) |
  | Early Bird | Reading from 5 AM to 9 AM, above chance (4 of 24 hours) | 30% (about 42% of the reading) | 80% (about 83%) |
  | Steady Reader | Days read in the year so far, with at least 14 days, or the longest streak | 40% of the days, or 30 days in a row | 90% of the days, or 180 days in a row |
  | Marathoner | Average of the 5 longest sessions | 1h30 | 4h |
  | Loyal Reader | Concentration of time on one author, who needs 50% of the time and 2 books with 30 minutes each | 0.4 | 1 |
  | Weekend Reader | Reading on Saturday and Sunday, above chance (2 of 7 days) | 30% (50% of the reading) | 80% (about 86%) |
  | Explorer | Effective number of authors | 5 | 15 |

  The three time-based habits need at least 7 days of reading, because a few days do not show a habit. The effective number of authors considers those with at least 30 minutes in the year and weighs them by time: 3 equal authors give 3, and one dominant author gives close to 1. The concentration used by Loyal Reader is the inverse of that number.
- **Devoured book:** the one with the fewest days between the first reading and the day it was finished, started and finished in the year, with at least 30 pages.
- **Covers:** they come from the Cover browser cache (`bookinfo_cache.sqlite3`), looked up by title and author. The title alone is enough only when a single book in the cache has it, so a common title such as "Poemas" does not bring the cover of another book. The cache has no index on titles, so they are read once per year and each cover is then read by its row. A cover whose size does not match its pixels is refused. A book with no cached cover gets one generated by `ui/generated_cover.lua`, with the title on top and the first author the cards accept at the bottom, so labels such as "Windows User" never get printed. The style comes from the title, so it is always the same for each book, and a long title shrinks or gets clipped to stay above the drawing. Each cover is built once per opened year and released when changing the year or closing.

## Limits

- It only sees what went through KOReader. Reading in Amazon's system is not included.
- No online data: Open Library was tested and removed, because it has too little data for comparison.
- No comparison with friends, which depends on the reading club mapped in `docs/research/reading-club.md`, in the `kindle` project.

## Structure

```
book_rewind.koplugin/
  _meta.lua, main.lua     registration in KOReader, and recovery after a crash while sharing
  book_rewind/
    stats.lua             metrics and profile, with no KOReader dependency
    cards.lua             content of the cards
    wildcards.lua         which rare cards a year qualifies for
    wildcard_cards.lua    content of the rare cards
    i18n.lua              texts in the three languages
    store.lua             database access
    share/access.lua      who gets what when sharing, independent from KOReader and the network
    share/server.lua      HTTP server that does not block the interface
    share/deck.lua        backgrounds as JSON, for the browser
    share/strings.lua     texts of the share screen and page, in the three languages
    ui/screen.lua         navigation
    ui/share_screen.lua   QR code, approval, firewall, sleep and the shared images
    ui/card_view.lua      drawing of the cards
    ui/wildcard_paint.lua drawing of the rare cards
    ui/themes.lua         colors of each theme, and which card uses what
    ui/scenes.lua         backgrounds of the cards
    ui/generated_cover.lua cover for books with none in the cache
  assets/cards/           fixed art, in two sizes
  assets/share/           script and style of the page in the browser
  tests/, tools/, docs/   development
```

## Tools

- `luajit tests/stats_spec.lua`: tests for metrics and cards.
- `luajit tests/themes_spec.lua`: every card has colors and a background in every theme, and text stays readable.
- `luajit tests/share_spec.lua`: the sharing rules, including attack attempts, and the server with fake connections.
- `tools/package.sh`: builds the zip and the checksum, only with what the plugin uses.
- `OUTPUT_DIR=docs/screenshots tools/koreader/run_headless.sh tools/koreader/render_readme_screens.lua`: updates the README images, from the fake history, in English and Portuguese. `share_page.png` is a capture of the page in a browser, taken by hand.
- `KOREADER_DIR=<desktop KOReader> python3 -I tools/make_brand_art.py`: draws the icon, the banner and the social preview from those images. It needs Pillow.
- With `KOREADER_DIR` pointing to a desktop KOReader:
  - `tools/koreader/run_emulator.sh` opens a window with a fake history, generated by `tools/koreader/fake_history.lua`, in `.ko-home/`. It has eight years with reading, one per reader profile, with a gap year so the comeback after years shows up, and scenes that make each of the 17 wildcards appear in some year. The reading is invented, over real titles.
  - `tools/koreader/check_all_sizes.sh` checks every card at four screen sizes, plus little reading, a single session, a missing or empty database, a book read across two years, a year in progress, a corrupted cover, keys, the 8 profiles and the 17 wildcards of the fake history, the transparent layers and rotation.
  - `RUN_SECONDS=600 READY_FILE=<file> tools/koreader/run_headless.sh tools/koreader/demo_share.lua` serves the share page with the fake history, approving the first device, and writes the address to that file.

In the `kindle` project, `tools/book_rewind/swap_stats.sh install|restore|status <ip>` swaps the device's statistics for the fake history, keeping the real database, and undoes the swap. It refuses to run with KOReader open. While the swap lasts, reading done on the device goes to the fake database and is lost on restore.

## License

Code under GPL-3.0, version 3 only. Art and texts under CC BY-NC-SA 4.0, to prevent the sale of copies of the plugin. The GPL allows selling the code, but not the art and texts. The details are in `NOTICE`.

## How to publish a version

1. Update `version` in `_meta.lua` and create the version's section in `CHANGELOG.md`, in the `## [1.2.3]` format.
2. Run the tests and `tools/koreader/check_all_sizes.sh`, and test on a device, including **Share**.
3. Publish the `v1.2.3` release on GitHub, creating the tag with it, after the push. The `release.yml` workflow checks that the tag matches `_meta.lua`, runs the tests and attaches the zip and the checksum to the release.
