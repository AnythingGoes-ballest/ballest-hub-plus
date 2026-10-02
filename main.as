// Hub Plus: the game's track hub, plus search.
//
// A row of its own inside the hub, under the hub's header and page row:
//
//   [search maps, or authors by name ................................................................ x]
//   [top rated .............v] [any author ...............v] [any progress ...........v]
//   Showing 19 of the 25 maps on this page (not finished)
//
// Everything shows in the hub's own list: a search is made the way the game makes its own (the game's query builder
// and its list view, through Hub::Search), so the hub's pages, entries, info panel, medals and play button all work
// as always, and the tags picked in the hub's own filter panel still apply.
//
//   * search: Steam's search of map titles, descriptions and tags, as you type (once typing pauses); the box's x
//     empties it and keeps the hub on its page; on the downloads page the text narrows that page instead;
//   * authors by name: every map is loaded once a session in the background (Workshop::Find, 50 a query) to learn
//     who made what; their names (Workshop::Name) are kept between sessions. Searching lists the authors whose names
//     match in the author list; picking one shows their maps;
//   * more by this author: a button after the author's name in the hub's info panel (Hub::SetAuthorButton);
//   * players: every thumbnail on screen shows how many players have the map (Hub::SetEntryBadge, Steam's unique
//     subscribers);
//   * sorts: the game's own (best match, top rated, trending over a day, week, month or year, newest, oldest, name,
//     recently updated) and Steam's (most played, most subscribed, most liked). One author's maps sort by newest,
//     oldest, name, recently updated or top rated only;
//   * your progress: maps on each page that don't match are hidden (Hub::HideEntry). Finished maps and medals come
//     from the game's save (Workshop::MyMedal); played ones from Steam's list of the maps you've played, the save, and
//     the workshop maps this plugin has seen you on.

const float WINDOW_R = 0.0052f, WINDOW_G = 0.0060f, WINDOW_B = 0.0086f;     // #101217
const float BUTTON_R = 0.0232f, BUTTON_G = 0.0273f, BUTTON_B = 0.0382f;     // #2a2e37
const float PRIMARY_R = 0.0782f, PRIMARY_G = 0.2051f, PRIMARY_B = 0.0048f;  // #4f7d0f
const float MUTED_R = 0.2582f, MUTED_G = 0.2747f, MUTED_B = 0.3185f;        // #8b8f99

const int PAGE_SIZE = 50;               // Steam's results per query
const int MAX_PAGES = 400;

// --- the maps --------------------------------------------------------------------------------------------------------

class Map
{
    string id, title, author, tags, description, lowerText;
    int64 created, updated, plays, subscribers;
    int up, down;
    float score;
}

array<Map@> maps;                       // every map, newest first as loaded
array<string> mapIds;                   // sorted, for finding a map by id
array<int> mapAt;                       // mapIds[i] is maps[mapAt[i]]

int FindSorted(const array<string>@ list, const string &in id)
{
    int lo = 0, hi = int(list.length());
    while (lo < hi)
    {
        int mid = (lo + hi) / 2;
        if (list[mid] < id)
            lo = mid + 1;
        else
            hi = mid;
    }
    return lo;
}

bool Contains(const array<string>@ list, const string &in id)
{
    int at = FindSorted(list, id);
    return at < int(list.length()) && list[at] == id;
}

void InsertSorted(array<string>@ list, const string &in id)
{
    int at = FindSorted(list, id);
    if (at < int(list.length()) && list[at] == id)
        return;
    list.insertAt(at, id);
}

Map@ MapById(const string &in id)
{
    int at = FindSorted(mapIds, id);
    if (at >= int(mapIds.length()) || mapIds[at] != id)
        return null;
    return maps[mapAt[at]];
}

// A map as Steam last described it (any query that returned it).
Map@ Described(const string &in id)
{
    Map m;
    m.id = id;
    m.title = Workshop::Title(id);
    m.author = Workshop::Author(id);
    m.tags = Workshop::Tags(id);
    m.description = Workshop::Description(id);
    m.created = Workshop::Created(id);
    m.updated = Workshop::Updated(id);
    m.plays = Workshop::Plays(id);
    m.subscribers = Workshop::Subscribers(id);
    m.up = Workshop::VotesUp(id);
    m.down = Workshop::VotesDown(id);
    m.score = Workshop::Score(id);
    m.lowerText = Lower(m.title + " " + m.tags);
    return m;
}

void AddMap(const string &in id)
{
    int at = FindSorted(mapIds, id);
    if (at < int(mapIds.length()) && mapIds[at] == id)
        return;
    Map@ m = Described(id);
    mapIds.insertAt(at, id);
    mapAt.insertAt(at, int(maps.length()));
    maps.insertLast(m);
    CountAuthor(m.author);
}

// --- authors -----------------------------------------------------------------------------------------------------------

class Author
{
    string id, name, lowerName;
    int maps;
}

array<Author@> authors;                 // sorted by id
array<string> authorIds;
bool namesChanged = false;

Author@ AuthorById(const string &in id)
{
    int at = FindSorted(authorIds, id);
    if (at >= int(authorIds.length()) || authorIds[at] != id)
        return null;
    return authors[at];
}

Author@ AuthorFor(const string &in id)
{
    int at = FindSorted(authorIds, id);
    if (at < int(authorIds.length()) && authorIds[at] == id)
        return authors[at];
    Author a;
    a.id = id;
    authorIds.insertAt(at, id);
    authors.insertAt(at, a);
    return a;
}

void CountAuthor(const string &in id)
{
    if (id == "")
        return;
    AuthorFor(id).maps++;
}

string AuthorName(const string &in id)
{
    Author@ a = AuthorById(id);
    return a !is null && a.name != "" ? a.name : "";
}

// Names Steam hasn't given yet are asked for a few at a time (the host spaces the requests out).
double nextNameCheck = 0;
uint nameCursor = 0;
void LearnNames()
{
    if (Host::Time() < nextNameCheck)
        return;
    nextNameCheck = Host::Time() + 1;
    // Round the list from where the last check stopped, so every author gets asked about in turn.
    int asked = 0;
    for (uint n = 0; n < authors.length() && asked < 40; n++)
    {
        nameCursor = (nameCursor + 1) % authors.length();
        Author@ a = authors[nameCursor];
        if (a.maps == 0)
            continue;               // only known from an earlier session's names
        string name = Workshop::Name(a.id);
        if (name == "")
        {
            asked++;
            continue;
        }
        if (name != a.name)
        {
            a.name = name;
            a.lowerName = Lower(name);
            namesChanged = true;
            resultsDirty = true;
        }
    }
}

// Names are kept between sessions, so searching by author works before Steam has answered again.
string FIELD, RECORD;                   // unit and record separators (bytes 31 and 30), set in Main
void LoadNames()
{
    array<string>@ records = Storage::Get("names", "").split(RECORD);
    for (uint i = 0; i < records.length(); i++)
    {
        array<string>@ f = records[i].split(FIELD);
        if (f.length() != 2 || f[0] == "")
            continue;
        Author@ a = AuthorFor(f[0]);
        a.name = f[1];
        a.lowerName = Lower(f[1]);
    }
}

double nextNameSave = 0;
void SaveNames()
{
    if (!namesChanged || Host::Time() < nextNameSave)
        return;
    nextNameSave = Host::Time() + 30;
    namesChanged = false;
    array<string> records;
    for (uint i = 0; i < authors.length(); i++)
        if (authors[i].name != "")
            records.insertLast(authors[i].id + FIELD + Replace(Replace(authors[i].name, FIELD, " "), RECORD, " "));
    Storage::Set("names", join(records, RECORD));
}

// --- loading from Steam ------------------------------------------------------------------------------------------------

// A paged load: Steam pages fetched one after another until a short page (or `lastPage`).
class Loader
{
    string kind;                        // "all", "trending" or a list name ("played", "favorited", ...)
    int days = 7;
    int page = 0, lastPage = MAX_PAGES, query = -1, total = 0, failures = 0;
    bool done = false;
    string error;
    double nextAt = 0;
    array<string> ids;

    void Step()
    {
        if (done || Host::Time() < nextAt)
            return;
        if (query < 0)
        {
            page++;
            if (kind == "all")
                query = Workshop::Find("", "new", page);
            else if (kind == "trending")
                query = Workshop::Find("", "trending", page, days);
            else
                query = Workshop::FindList(kind, "", "new", page);
            if (query < 0)
            {
                done = true;
                error = "Steam isn't available";
            }
            return;
        }
        string state = Workshop::State(query);
        if (state == "searching")
            return;
        if (state != "done")
        {
            Workshop::Forget(query);
            query = -1;
            page--;
            nextAt = Host::Time() + 5;
            if (++failures >= 3)
            {
                done = true;
                error = state;
            }
            return;
        }
        int count = Workshop::Count(query);
        total = Workshop::Total(query);
        for (int i = 0; i < count; i++)
            ids.insertLast(Workshop::Id(query, i));
        Workshop::Forget(query);
        query = -1;
        resultsDirty = true;
        if (count < PAGE_SIZE || page * PAGE_SIZE >= total || page >= lastPage)
            done = true;
        nextAt = Host::Time() + 0.3;
    }
}

Loader@ catalogue;                      // every map
Loader@ playedList;                     // Steam's list of the maps you've played
int catalogueSeen = 0;

void StartLoading()
{
    if (catalogue !is null)
        return;
    @catalogue = Loader();
    catalogue.kind = "all";
    @playedList = Loader();
    playedList.kind = "played";
}

void StepLoaders()
{
    if (catalogue is null)
        return;
    catalogue.Step();
    while (catalogueSeen < int(catalogue.ids.length()))
        AddMap(catalogue.ids[catalogueSeen++]);
    if (catalogue.done)
        playedList.Step();
}

// --- your progress -----------------------------------------------------------------------------------------------------

array<string> playedIds;                // sorted: maps this plugin has seen you on (kept between sessions)

void LoadPlayed()
{
    array<string>@ ids = Storage::Get("played", "").split(",");
    for (uint i = 0; i < ids.length(); i++)
        if (ids[i] != "")
            InsertSorted(playedIds, ids[i]);
}

// On a workshop map: Race::TrackKey is "custom:<workshop id>:<file>".
string lastTrackKey;
void NotePlayed()
{
    string key = Race::TrackKey();
    if (key == lastTrackKey)
        return;
    lastTrackKey = key;
    if (key.findFirst("custom:") != 0)
        return;
    int end = key.findFirst(":", 7);
    string id = end > 7 ? key.substr(7, end - 7) : "";
    if (id == "" || !AllDigits(id) || Contains(playedIds, id))
        return;
    InsertSorted(playedIds, id);
    Storage::Set("played", join(playedIds, ","));
}

array<string> playedOnSteam;            // sorted copy of playedList.ids
uint playedOnSteamFrom = 0;

bool Played(const string &in id)
{
    if (playedList !is null && playedOnSteamFrom < playedList.ids.length())
    {
        for (uint i = playedOnSteamFrom; i < playedList.ids.length(); i++)
            InsertSorted(playedOnSteam, playedList.ids[i]);
        playedOnSteamFrom = playedList.ids.length();
    }
    return Contains(playedIds, id) || Contains(playedOnSteam, id) || Workshop::MyMedal(id) >= 0;
}

// --- the row in the hub ------------------------------------------------------------------------------------------------

// Sorts by Hub::Search's names: the game's own and Steam's. One author's maps (a Steam list of theirs) sort only by
// newest, oldest, name, recently updated and top rated (measured: the game's builder refuses the rest for an author).
// Trending is Steam's trend over a window of days; each window is its own entry ("trending:7").
const array<string> SORTS = {"top rated", "trending today", "trending this week", "trending this month",
                             "trending this year", "newest", "oldest", "name", "recently updated", "most played",
                             "most subscribed", "most liked", "best match"};
const array<string> SORT_KEYS = {"top", "trending:1", "trending:7", "trending:30", "trending:365", "new", "oldest",
                                 "title", "updated", "played", "subscribed", "liked", "relevance"};
const array<string> AUTHOR_SORTS = {"newest", "oldest", "name", "recently updated", "top rated"};
const array<string> AUTHOR_SORT_KEYS = {"new", "oldest", "title", "updated", "top"};
const array<string> PROGRESS = {"any progress", "not played", "played, not finished", "not finished", "finished",
                                "no gold yet", "no author medal yet"};
const array<string> PROGRESS_SHOWN = {"", "not played", "played but not finished", "not finished", "finished",
                                      "without gold", "without the author medal"};

UI::Window@ row;
UI::TextInput@ search;
UI::Dropdown@ sortList;
UI::Dropdown@ authorList;
UI::Dropdown@ progressList;
UI::Text@ status;
array<string> authorChoices;            // Steam ids behind authorList's options ("" for any author)
array<string> sortKeys;                 // Hub::Search's sort behind each of sortList's options
bool resultsDirty = false;

//   [search maps, or authors by name ...........................] [search] [more by this author] [clear]
//   [top rated .............v] [any author ...............v] [any progress ...........v]
//   Showing 19 of the 25 maps on this page (not finished)        (only while there's something to say)
//
// The hub's column is about 790 pixels wide (measured), so the second row is three dropdowns and nothing else.
void BuildRow()
{
    @row = UI::CreateWindow();
    row.DockInHub();
    row.SetBackground(WINDOW_R, WINDOW_G, WINDOW_B, 0.92f);
    row.SetCornerRadius(10);
    row.visible = false;
    @search = row.AddTextInput(0, "search maps, or authors by name", 17);
    search.clearOnSubmit = false;
    search.clearButton = true;          // the x at its right end empties it
    row.NewRow();
    @sortList = row.AddDropdown(240);
    SetSorts(false, "top");
    @authorList = row.AddDropdown(270);
    SetAuthorChoices(array<string>());
    @progressList = row.AddDropdown(240);
    for (uint i = 0; i < PROGRESS.length(); i++)
        progressList.AddOption(PROGRESS[i]);
    progressList.selected = 0;
    row.NewRow();
    @status = Muted(row.AddText("", 15));
    status.visible = false;
}

void Secondary(UI::Button@ b) { b.SetBackground(BUTTON_R, BUTTON_G, BUTTON_B, 1); }
void Primary(UI::Button@ b) { b.SetBackground(PRIMARY_R, PRIMARY_G, PRIMARY_B, 1); }
UI::Text@ Muted(UI::Text@ t)
{
    t.SetColor(MUTED_R, MUTED_G, MUTED_B, 1);
    return t;
}

// The sort list: every sort, or the ones one author's maps take. The sort chosen stays when the other list has it.
bool authorSorts = false;
void SetSorts(bool forAuthor, const string &in keep)
{
    authorSorts = forAuthor;
    const array<string>@ labels = forAuthor ? AUTHOR_SORTS : SORTS;
    const array<string>@ keys = forAuthor ? AUTHOR_SORT_KEYS : SORT_KEYS;
    sortList.ClearOptions();
    sortKeys.resize(0);
    for (uint i = 0; i < labels.length(); i++)
    {
        sortList.AddOption(labels[i]);
        sortKeys.insertLast(keys[i]);
    }
    int at = sortKeys.find(keep);
    if (at < 0)
        at = sortKeys.find(forAuthor ? "new" : "top");
    sortList.selected = at;
}

string SortKey()
{
    int at = sortList.selected;
    if (at < 0 || at >= int(sortKeys.length()))
        return "top";
    return sortKeys[at];
}

// The author list: "any author", then these authors with how many maps each has. (Changing a dropdown's options
// builds the row again, so it's only done on a search or a pick, never while typing.)
void SetAuthorChoices(const array<string> &in ids, const string &in selected = "")
{
    authorList.ClearOptions();
    authorChoices.resize(0);
    authorList.AddOption("any author");
    authorChoices.insertLast("");
    for (uint i = 0; i < ids.length(); i++)
    {
        Author@ a = AuthorById(ids[i]);
        string name = AuthorName(ids[i]);
        string label = name == "" ? "an author" : name;
        if (a !is null && a.maps > 0)
            label += " (" + a.maps + (a.maps == 1 ? " map)" : " maps)");
        authorList.AddOption(label);
        authorChoices.insertLast(ids[i]);
    }
    int at = authorChoices.find(selected);
    authorList.selected = at < 0 ? 0 : at;
}

// The authors whose names hold the text, most maps first.
array<string> AuthorsMatching(const string &in text)
{
    array<Author@> found;
    string typed = Lower(Trim(text));
    if (typed.length() >= 2)
        for (uint i = 0; i < authors.length(); i++)
            if (authors[i].lowerName != "" && authors[i].maps > 0 && authors[i].lowerName.findFirst(typed) >= 0)
                found.insertLast(authors[i]);
    if (found.length() > 1)          // sort() throws "index out of bounds" on an empty array (measured)
        found.sort(function(a, b) { return a.maps > b.maps; });
    array<string> ids;
    for (uint i = 0; i < found.length() && i < 20; i++)
        ids.insertLast(found[i].id);
    return ids;
}

string PickedAuthor()
{
    int at = authorList.selected;
    if (at <= 0 || at >= int(authorChoices.length()))
        return "";
    return authorChoices[at];
}

// Searches the hub's own list: the text last searched for, or one author's maps (Steam can't search a player's maps by
// text). The tags picked in the game's own filter panel still apply.
string message, query;                  // query: the text last searched for (as typed, or Enter)
// show: switch the hub to its list for the results (false: it stays on the page it's on)
void Search(bool show = true)
{
    string author = PickedAuthor();
    if ((author != "") != authorSorts)
        SetSorts(author != "", SortKey());
    string sort = SortKey();
    int days = 7;
    if (sort.findFirst("trending:") == 0)
    {
        days = parseInt(sort.substr(9));
        sort = "trending";
    }
    if (sort == "relevance" && query == "")
        sort = "top";
    if (!Hub::Search(author != "" ? "" : query, sort, days, author, null, false, true, show))
        message = "the hub couldn't make that search";
}

void Submit(const string &in text, bool show = true)
{
    query = Trim(text);
    message = "";
    array<string> matches = AuthorsMatching(query);
    SetAuthorChoices(matches);          // a new search is of every author's maps
    if (authorSorts)
        SetSorts(false, SortKey());
    // Text reads best by how well maps match it; back to top rated when the box is emptied.
    if (query != "" && SortKey() == "top")
        sortList.selected = sortKeys.find("relevance");
    else if (query == "" && SortKey() == "relevance")
        sortList.selected = sortKeys.find("top");
    Search(show);
    if (matches.length() == 1)
        message = "1 author's name matches \"" + query + "\": pick them in the author list to see their maps";
    else if (matches.length() > 1)
        message = matches.length() + " authors' names match \"" + query + "\": pick one in the author list to see their maps";
    else if (query != "" && catalogue !is null && !catalogue.done)
        message = "Still learning who made what (" + Grouped(maps.length()) + " of " + Grouped(catalogue.total) + " maps): authors show up once it's done";
}

// --- your progress on the list ---------------------------------------------------------------------------------------

bool ProgressMatches(const string &in id)
{
    int p = progressList.selected;
    if (p == 0)
        return true;
    int medal = Workshop::MyMedal(id);
    bool finished = medal >= 0;
    if (p == 1)
        return !Played(id);
    if (p == 2)
        return Played(id) && !finished;
    if (p == 3)
        return !finished;
    if (p == 4)
        return finished;
    if (p == 5)
        return medal < 3;
    return medal < 4;
}

// On Downloads (the Subscribed page) the search box narrows the page itself: a map stays when its name or its author's
// name holds the text. Maps whose name isn't known yet stay shown.
string localFilter;                     // lower-case text, "" for none
bool TextMatches(const string &in id)
{
    if (localFilter == "" || Hub::View() != "subscribed")
        return true;
    string title = Lower(Workshop::Title(id));
    if (title == "")
        return true;
    return title.findFirst(localFilter) >= 0 || Lower(AuthorName(Workshop::Author(id))).findFirst(localFilter) >= 0;
}

// The list's maps that don't match the progress filter are hidden, page by page, as the game fills it. Checked
// again every time, not only when the page's maps change: going Home and back to the list shows the same maps with
// the game's own visibility again, so they have to be hidden again.
int shownOnPage = 0, onPage = 0;
double nextFilter = 0;
void FilterEntries()
{
    if (Host::Time() < nextFilter)
        return;
    nextFilter = Host::Time() + 0.3;
    array<string>@ ids = Hub::Entries();     // the list on screen: the main list or Subscribed's (none on Home)
    onPage = int(ids.length());
    shownOnPage = 0;
    for (uint i = 0; i < ids.length(); i++)
    {
        bool keep = ProgressMatches(ids[i]) && TextMatches(ids[i]);
        Hub::HideEntry(ids[i], !keep);
        if (keep)
            shownOnPage++;
    }
}

// How many people have each map (Steam's unique subscribers, from the background catalogue) on every thumbnail on
// screen: Home's tiles, the list and Subscribed.
double nextBadges = 0;
void UpdateBadges()
{
    if (Host::Time() < nextBadges)
        return;
    nextBadges = Host::Time() + 0.3;
    array<string>@ ids = Hub::Thumbnails();
    for (uint i = 0; i < ids.length(); i++)
    {
        int64 people = Workshop::Subscribers(ids[i]);
        Hub::SetEntryBadge(ids[i], people > 0 ? Short(people) : "");
    }
}

// 950, 1.2k, 12k, 1.4m
string Short(int64 n)
{
    if (n < 1000)
        return "" + n;
    if (n < 10000)
        return "" + (n / 1000) + "." + ((n % 1000) / 100) + "k";
    if (n < 1000000)
        return "" + (n / 1000) + "k";
    return "" + (n / 1000000) + "." + ((n % 1000000) / 100000) + "m";
}

string Status()
{
    if (message != "")
        return message;
    if (progressList.selected > 0 && !Hub::ListShown())
        return "Your progress filter works on the list and Subscribed pages";
    bool texting = localFilter != "" && Hub::View() == "subscribed";
    if ((progressList.selected > 0 || texting) && onPage > 0)
    {
        string why = progressList.selected > 0 ? PROGRESS_SHOWN[progressList.selected] : "";
        if (texting)
            why += (why == "" ? "" : ", ") + "matching \"" + Trim(search.typed == "" ? lastTyped : search.typed) + "\"";
        return "Showing " + shownOnPage + " of the " + onPage + " maps on this page (" + why + ")";
    }
    return "";
}

// Searching as you type: once the box has been still for a moment, so every key doesn't make a Steam search.
const double TYPING_PAUSE = 0.5;
string lastTyped;
double typedAt = 0;

// Emptying the search (the box's x, or deleting the text): back to every map, on the page the hub is on.
void ClearSearch()
{
    bool searched = query != "" || PickedAuthor() != "";
    search.value = "";
    lastTyped = "";
    localFilter = "";
    query = "";
    message = "";
    SetAuthorChoices(array<string>());
    if (SortKey() == "relevance")
        sortList.selected = sortKeys.find("top");
    if (searched)
        Search(Hub::View() == "list");
}

void UpdateRow()
{
    if (search.Cleared())
        ClearSearch();
    string typed = search.typed;
    if (typed != lastTyped)
    {
        lastTyped = typed;
        typedAt = Host::Time();
    }
    if (search.Submitted())
    {
        typedAt = -100;                 // Enter: now
        lastTyped = search.text;
    }
    // Downloads: the text narrows the page at once, no search. Elsewhere: a search once typing pauses.
    bool downloads = Hub::View() == "subscribed";
    localFilter = downloads ? Lower(Trim(lastTyped)) : "";
    if (!downloads && Trim(lastTyped) != query && Host::Time() - typedAt >= TYPING_PAUSE)
    {
        // Still typing (or on the list already): the list shows the results. Clicked away to Home or Subscribed in the
        // pause: the results wait in the list and the hub stays where it was clicked to.
        bool typing = search.focused;
        if (Trim(lastTyped) == "")
            ClearSearch();
        else
            Submit(lastTyped, typing || Hub::View() == "list");
        if (typing)
            search.Focus();             // the hub's list takes the keyboard when it shows results: keep typing
    }
    if (sortList.Changed())
    {
        message = "";
        Search();
    }
    if (authorList.Changed())
    {
        message = "";
        Search();
    }
    if (progressList.Changed())
        message = "";
    if (Hub::AuthorButtonClicked())     // "more by this author", next to the name in the hub's info panel
    {
        string author = Hub::FocusedAuthor();
        if (author != "")
        {
            array<string> one = {author};
            SetAuthorChoices(one, author);
            message = "";
            Search();
        }
    }
    UpdateBadges();
    FilterEntries();
    string text = Status();
    status.text = text;
    status.visible = text != "";
}

// --- the plugin ------------------------------------------------------------------------------------------------------------

void Main()
{
    FIELD.resize(1);
    FIELD[0] = 31;
    RECORD.resize(1);
    RECORD[0] = 30;
    LoadNames();
    LoadPlayed();
    BuildRow();
    Hub::SetAuthorButton("more by this author");
    Log::Info("hub plus ready");
}

void Update(float dt)
{
    NotePlayed();
    bool hub = !Race::OnTrack() && Hub::Shown();
    row.visible = hub;
    if (!hub)
        return;
    StartLoading();
    StepLoaders();
    LearnNames();
    SaveNames();
    UpdateRow();
}

// --- text helpers --------------------------------------------------------------------------------------------------------

string Lower(const string &in s)
{
    string picked = s;
    for (uint i = 0; i < picked.length(); i++)
        if (picked[i] >= 65 && picked[i] <= 90)
            picked[i] = picked[i] + 32;
    return picked;
}

string Trim(const string &in s)
{
    int first = 0, last = int(s.length()) - 1;
    while (first <= last && s[first] <= 32)
        first++;
    while (last >= first && s[last] <= 32)
        last--;
    return s.substr(first, last - first + 1);
}

string Replace(const string &in s, const string &in from, const string &in to)
{
    return join(s.split(from), to);
}

int Min(int a, int b) { return a < b ? a : b; }
int Max(int a, int b) { return a > b ? a : b; }

bool AllDigits(const string &in s)
{
    for (uint i = 0; i < s.length(); i++)
        if (s[i] < 48 || s[i] > 57)
            return false;
    return s.length() > 0;
}

string Short(const string &in text, uint most)
{
    return text.length() <= most ? text : text.substr(0, most - 3) + "...";
}

// 12345 -> "12,345"
string Grouped(int64 n)
{
    string digits = "" + n;
    string grouped;
    for (int i = 0; i < int(digits.length()); i++)
    {
        if (i > 0 && (int(digits.length()) - i) % 3 == 0)
            grouped += ",";
        grouped += digits.substr(i, 1);
    }
    return grouped;
}

// Seconds -> "1:02.345"
string Clock(double seconds)
{
    int64 ms = int64(seconds * 1000 + 0.5);
    int64 minutes = ms / 60000;
    int64 rest = ms % 60000;
    string s = "" + (rest / 1000);
    if (s.length() < 2)
        s = "0" + s;
    string frac = "" + (rest % 1000);
    while (frac.length() < 3)
        frac = "0" + frac;
    return minutes + ":" + s + "." + frac;
}

const array<string> MONTHS = {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"};

// Unix seconds -> "3 Jan 2026" (days to a civil date: Howard Hinnant's algorithm).
string Date(int64 unix)
{
    if (unix <= 0)
        return "?";
    int64 z = unix / 86400 + 719468;
    int64 era = z / 146097;
    int64 doe = z - era * 146097;
    int64 yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    int64 y = yoe + era * 400;
    int64 doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    int64 mp = (5 * doy + 2) / 153;
    int64 d = doy - (153 * mp + 2) / 5 + 1;
    int64 m = mp < 10 ? mp + 3 : mp - 9;
    if (m <= 2)
        y++;
    return d + " " + MONTHS[m - 1] + " " + y;
}
