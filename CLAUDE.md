# ClaudeUsage — macOS app za praćenje Claude Code limita

Native macOS aplikacija (SwiftUI) koja prikazuje koliko je potrošeno od limita Claude
pretplate: trenutna sesija (5h), nedeljni limit za sve modele i nedeljni limit po modelu
(npr. Fable). Podaci se prikazuju u glavnom prozoru, u meni baru i u desktop widgetu.

- Repo: https://github.com/Stankoo003/CLAUDEUSAGE (privatni, lični nalog `Stankoo003`)
- Testni nalog: Dev-ov Claude Max 5x (`subscriptionType: max`, `rateLimitTier: default_claude_max_5x`), individualni, nije Team/Enterprise
- Dizajn: claude.ai artifact „Claude Usage — macOS app“ (Menu bar light/dark, Widgets light/dark, Sign in, Menu bar item states)

---

## 1. Kako smo radili (metod)

1. **Research pre koda.** Prvo smo istražili koji izvori podataka postoje (zvanična dokumentacija
   Claude Code-a, community alati, lokalni fajlovi na mašini), pa tek onda pravili plan.
2. **Provera na pravom nalogu.** Pre pisanja aplikacije napravljena je read-only skripta koja
   čita token iz Keychain-a i poziva usage endpoint. Pravi odgovor sa Dev-ovog naloga je
   odredio model podataka (tako smo otkrili niz `limits[]` i Fable limit).
3. **Dizajn kao izvor istine.** UI je rađen po artifact dizajnu (monohromno, Inter/SF,
   kartica 320 pt, barovi 6 pt, prsten u meni baru, četiri stanja ikonice).
4. **Faze sa proverom posle svake.** Posle svake izmene: `xcodebuild` mora da prođe bez
   grešaka i upozorenja. Parser je testiran na pravom JSON odgovoru, a ikonica u meni baru
   renderovana u PNG i vizuelno proverena. Pokretanje aplikacije i UI proveru radi Dev u Xcode-u.
5. **Git radi Dev.** Claude ne pokreće git komande koje menjaju repo (commit, push, add,
   reset…), već daje predlog poruke i komande. Commit poruke: conventional commits, engleski,
   jedna linija, max 15 reči (skill `commit-message`).

### Build provera (bez diranja Xcode DerivedData)

```
xcodebuild -project ClaudeUsage.xcodeproj -scheme ClaudeUsage -configuration Debug \
  -derivedDataPath <scratchpad>/DerivedData CODE_SIGNING_ALLOWED=NO build
```

`CODE_SIGNING_ALLOWED=NO` je potreban dok tim nije izabran; za pravo pokretanje widgeta
build mora biti potpisan timom (vidi „Otvorene stavke“).

---

## 2. Rezultati istraživanja: odakle dolaze podaci

Ne postoji zvanični javni API za limite pretplate pojedinačnog naloga. Postoje tri izvora:

| # | Izvor | Šta daje | Status |
|---|---|---|---|
| **A** | Statusline JSON (`rate_limits.five_hour` / `seven_day`, polja `used_percentage`, `resets_at`) | Samo 5h i 7d, bez limita po modelu; stiže samo dok radi Claude Code sesija | Zvanično dokumentovano za Pro/Max/Ultra |
| **B** | `GET https://api.anthropic.com/api/oauth/usage` | Svi limiti uključujući **po modelu (Fable)**, breakdown po proizvodu | **Nedokumentovano**; isti endpoint koristi `/usage` u Claude Code-u |
| **C** | Lokalni logovi `~/.claude/projects/**/*.jsonl` | Tokeni po poruci, modelu, projektu, vremenu (input/output/cache/thinking) | Postoje lokalno; ne daju procente limita |

Ostalo što je razmotreno i odbačeno: OpenTelemetry (nema metrike za limite pretplate),
Enterprise Analytics API / Claude Code Analytics API (samo Team/Enterprise/Console sa admin
ključem, dnevni agregati).

**Odluka:** B je glavni izvor (jedini ima Fable), C je planiran za statistiku (faza 4),
A ostaje kao moguća rezerva (nije implementiran).

### Autentikacija

Claude Code čuva OAuth token u login Keychain-u:
- service: `Claude Code-credentials`
- sadržaj: JSON `{"claudeAiOauth": {"accessToken", "refreshToken", "expiresAt" (ms), "subscriptionType", "rateLimitTier", "scopes"}}`

Email naloga je u `~/.claude.json` → `oauthAccount.emailAddress`.

Zahtev: `Authorization: Bearer <accessToken>` + `anthropic-beta: oauth-2025-04-20`.

### Verifikovan odgovor endpointa (2026-10-31)

Koristi se **samo niz `limits[]`**:

```json
{ "kind": "session",       "group": "session", "percent": 1,  "severity": "normal", "resets_at": "2026-10-31T23:40:00.435501+00:00", "scope": null, "is_active": false }
{ "kind": "weekly_all",    "group": "weekly",  "percent": 39, "severity": "normal", "resets_at": "2026-11-03T02:00:00.435522+00:00", "scope": null, "is_active": false }
{ "kind": "weekly_scoped", "group": "weekly",  "percent": 66, "severity": "normal", "resets_at": "…",
  "scope": { "model": { "id": null, "display_name": "Fable" }, "surface": null }, "is_active": true }
```

- `resets_at` ima mikrosekunde, koje `ISO8601DateFormatter` ne prima → parser ih odseca.
- Ravna polja `seven_day_opus` / `seven_day_sonnet` su `null` (stari format) — ignorišu se.
- Mnogo internih kodnih imena (`iguana_necktie`, `amber_cistern`, …) — ignorišu se.
- Korisno za kasnije: `seven_day_breakdown.rows` (Claude Code 99%, Chats 1%, Cowork 0%) i
  `weekly_scoped_shares` (Fable 33% od nedeljnog, pravo na 50% → 66%).

---

## 3. Arhitektura

```
Claude Code ── Keychain token ──► ClaudeUsage.app (bez sandbox-a)
                                   ├─ UsageAPI: GET /api/oauth/usage na 5 min
                                   ├─ UsageStore (@Observable) ──► glavni prozor + meni bar
                                   └─ upisuje usage.json u App Group ──┐
                                                                       ▼
                                       ClaudeUsageWidget (sandbox) čita usage.json
                                       (nikad ne poziva Keychain ni mrežu)
```

### Struktura fajlova

```
ClaudeUsage/                     app target
  ClaudeUsageApp.swift           Window("main") + MenuBarExtra; polling kreće pri pokretanju
  ContentView.swift              kartica iz dizajna, layout .window (razvlači se, skroluje) i .menuBar (320 pt)
  MenuBarLabel.swift             prsten + % sesije kao template NSImage (ImageRenderer), 4 stanja
  UsageStore.swift               stanje, polling, greške, upis keša za widget, OSLog
  Services/ClaudeCredentials.swift  Keychain token (samo čitanje) + email iz ~/.claude.json
  Services/UsageAPI.swift        HTTP poziv, mapiranje 401/403/429
ClaudeUsageWidget/               widget extension target
  UsageWidget.swift              WidgetBundle, TimelineProvider, Small/Medium/Large prikaz
Shared/                          u OBA targeta (synchronized group)
  UsageSnapshot.swift            PlanLimit model, lenient dekodiranje, tekstovi za reset
  UsageCache.swift               CachedUsage + čitanje/upis usage.json u App Group
  UsageViews.swift               UsageBar i UsageRing
Config/                          nije član nijednog targeta
  ClaudeUsage.entitlements       App Group
  ClaudeUsageWidget.entitlements App Sandbox + App Group
  ClaudeUsageWidget-Info.plist   NSExtensionPointIdentifier = com.apple.widgetkit-extension
```

Projekat koristi Xcode 16+ **synchronized folders** (`PBXFileSystemSynchronizedRootGroup`):
novi `.swift` fajl u folderu automatski ulazi u target, bez ručnog dodavanja u projekat.
`project.pbxproj` je inicijalno ručno napisan (xcodegen nije instaliran).

### Build podešavanja

- macOS 15.0+, Swift 5 mode, Xcode 26
- App: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, approachable concurrency; modeli i servisi su `nonisolated`
- Widget: bez default MainActor izolacije (zbog `TimelineProvider`)
- Bundle ID: `com.ingsoftware.ClaudeUsage`, widget `com.ingsoftware.ClaudeUsage.Widget`
- App Group: `$(TeamIdentifierPrefix)com.ingsoftware.ClaudeUsage` — kod ga u runtime-u čita iz
  potpisa (`SecTaskCopyValueForEntitlement`), pa Team ID nije upisan u kod

---

## 4. Ključne odluke i zašto

| Odluka | Razlog |
|---|---|
| **App Sandbox isključen za glavnu app** | Sandboxed app ne može da čita Keychain stavku Claude Code-a ni `~/.claude.json`. Posledica: nema Mac App Store / TestFlight distribucije. |
| **Token se samo čita, nikad ne osvežava** | Osvežavanje rotira refresh token i izlogovalo bi Claude Code. Ako je token istekao, app čeka da ga Claude Code osveži. |
| **Polling na 5 min, 429 → `Retry-After` ili 15 min** | Endpoint je rate-limitovan (i sam `/usage` dobija 429). Pri grešci ostaju poslednji poznati podaci, greška ide u footer. |
| **Odbijen Keychain pristup → bez automatskog ponavljanja** | Da korisnik ne bi dobijao prompt svakog minuta; čeka se „Try again“. |
| **Lenient dekodiranje** | Endpoint je nedokumentovan: pokvaren unos se preskače, nepoznat `kind` se prikazuje sa generičkim naslovom. |
| **Widget ne zove mrežu ni Keychain** | Widget mora biti sandboxed; app upisuje keš u App Group. |
| **Widget reload samo kad se promeni sadržaj (+ najmanje jednom na sat)** | macOS budžetira reload-ove widgeta. Timeline ima 16 unosa na 15 min, pa odbrojavanje ide bez reload-a. |
| **Widget prikazuje 0% kad je `resets_at` prošao** | Prozor se resetovao od poslednjeg preuzimanja. |
| **Meni bar prikazuje % sesije** | Po dizajnu; podešavanje (sesija / nedeljni / najbliži limitu) planirano u fazi 3. |

---

## 5. Faze i status

### ✅ Faza 0 — Blank projekat
Prazna SwiftUI macOS app, ručno napisan `project.pbxproj`, build verifikovan.

### ✅ Research i provera izvora
Istražena dokumentacija (statusline, `/usage`, OpenTelemetry), community alati i lokalni
fajlovi. Read-only skripta potvrdila endpoint na Dev-ovom nalogu (HTTP 200, Fable limit).

### ✅ Faza 1 — Glavni prozor
Kartica iz dizajna sa pravim podacima: header (email · plan, refresh), redovi limita sa
barom i vremenom do reseta, footer („Updated … ago“, quit). Prozor se razvlači
(min 300×260, default 360×420). Sandbox isključen (Dev ručno).

### ✅ Faza 2a — Meni bar
`MenuBarExtra` sa prstenom i % sesije; stanja normal / near limit / limit reached
(obrnuta pilula) / signed out (isprekidan prsten). Klik otvara istu karticu (320 pt) sa
dugmetom za otvaranje glavnog prozora. Ikonica vizuelno proverena.

### 🟡 Faza 2b — Widget (napisan, nije proradio do kraja)
WidgetKit extension sa Small/Medium/Large po dizajnu, keš u App Group-u.
Widget se pojavljuje u galeriji, ali prikazuje „Not connected“ — **uzrok: tim nije izabran**,
pa je build lokalno potpisan (`TeamIdentifier=not set`), App Group nema Team ID prefiks i
macOS ne dozvoljava pristup Group Container-u. Dodato OSLog logovanje greške upisa keša
(`Widget cache not written …`).

### ✅ Git
Repo inicijalizovan i pushovan na `Stankoo003/CLAUDEUSAGE` (`main`).

### ⏭ Faza 3 — Svakodnevna upotreba (sledeća)
- Pokretanje pri prijavi (`SMAppService`) — bez toga widget/meni bar zastarevaju kad app ne radi
- Samo meni bar (`LSUIElement`, bez Dock ikonice)
- Settings ekran: metrika u meni baru, launch at login, prag notifikacija
- Notifikacije pri prelasku praga (npr. 80%) i pri resetu

### ⏭ Faza 4 — Statistika iz lokalnih logova (izvor C)
Tokeni po danu / modelu / projektu iz `~/.claude/projects/*.jsonl`, procena cene, grafici.

### ⏭ Faza 5 — Distribucija
Ikonica aplikacije, Release build, **Developer ID + notarizacija** + `.dmg`
(TestFlight/App Store ne dolazi u obzir bez sandbox-a), eventualno Sparkle za ažuriranja.
Potreban plaćen Apple Developer Program na ličnom nalogu.

---

## 6. Otvorene stavke

1. **Izabrati lični tim** u Xcode-u za oba targeta (Signing & Capabilities → Team), pa
   Clean Build Folder i ponovo dodati widget. Na Mac-u trenutno nema code signing sertifikata;
   Xcode ga pravi pri izboru tima.
2. **Bundle ID** koristi `com.ingsoftware` (domen firme), a app se objavljuje na ličnom
   nalogu — razmotriti promenu prefiksa pre objave.
3. **Git identitet** nije podešen za ovaj repo (`git config user.name/user.email`), pa je
   commit aplikacije potpisan kao `Ing_ <ing_@Ing-s-MacBook-Pro-2.local>`.
4. `nesto.js` (prazan fajl iz početnog foldera) nije u repou.
5. Endpoint je nedokumentovan — ako se format promeni, prvo proveriti pravi odgovor
   (read-only skripta, bez ispisivanja tokena) pa prilagoditi `Shared/UsageSnapshot.swift`.

---

## 7. GitHub nalozi na ovoj mašini

Na Mac-u su u `gh` prijavljena dva naloga: lični `Stankoo003` (ovaj repo) i poslovni
`aleksastankovic-dev`. Remote URL sadrži korisničko ime (`https://Stankoo003@github.com/…`),
a git uzima prijavu iz `gh` (`gh auth setup-git`). GitHub ne prima lozinku naloga za git
preko HTTPS-a — samo token ili `gh` prijavu.

```
gh auth switch --user Stankoo003            # lični
gh auth switch --user aleksastankovic-dev   # poslovni
```

Ako push na ovaj repo vrati 403, prvo prebaciti aktivni nalog na `Stankoo003`.
