// Sirat4mac — shows the next prayer time and the time left in the macOS menu bar.
// Prayer tables are read straight from the installed Sirat app, so they stay in
// sync when Sirat updates.

import Cocoa
import ServiceManagement

let siratApp = "/Applications/Sirat.app"
let siratDataDir = siratApp + "/Wrapper/Runner.app/Frameworks/App.framework/flutter_assets/assets/data"

// MARK: - Prayer definitions

struct PrayerDef {
    let key: String
    let name: String
}

let prayerDefs: [PrayerDef] = [
    .init(key: "imsak",   name: "Imsaku"),
    .init(key: "sunrise", name: "Lindja e diellit"),
    .init(key: "dhuhr",   name: "Dreka"),
    .init(key: "asr",     name: "Ikindia"),
    .init(key: "maghrib", name: "Akshami"),
    .init(key: "isha",    name: "Jacia"),
]

struct ProfileDef {
    let id: String
    let name: String
    let file: String
    let baseCity: String
    let prettyNames: [String: String]
    let hiddenCities: Set<String>
}

let profileDefs: [ProfileDef] = [
    .init(id: "bik", name: "Kosovë (BIK)", file: "bik_cyclic_366_cet.json",
          baseCity: "Prishtinë", prettyNames: [:], hiddenCities: []),
    .init(id: "kmsh", name: "Shqipëri (KMSH)", file: "kmsh_albania_cyclic_366_cet.json",
          baseCity: "Tiranë",
          prettyNames: ["tirane": "Tiranë", "durres": "Durrës", "shkoder": "Shkodër", "vlore": "Vlorë",
                        "lushnje": "Lushnjë", "berat": "Berat", "elbasan": "Elbasan", "kukes": "Kukës",
                        "peshkopi": "Peshkopi", "librazhd": "Librazhd", "korce": "Korçë"],
          hiddenCities: ["tirana"]),
    .init(id: "bfi", name: "Maqedoni e Veriut", file: "bfi_north_macedonia_cyclic_366_cet.json",
          baseCity: "Shkup", prettyNames: [:], hiddenCities: []),
    .init(id: "mne", name: "Mali i Zi", file: "montenegro_podgorica_cyclic_366_cet.json",
          baseCity: "Podgoricë", prettyNames: [:], hiddenCities: []),
]

struct City {
    let name: String
    let offset: Int
}

// MARK: - Takvim (one prayer table)

final class Takvim {
    let def: ProfileDef
    let rows: [String: [String: String]]
    let baseZone: TimeZone      // the table's clock: standard time, no DST
    let timeZone: TimeZone      // the country's real time zone (adds DST)
    let cities: [City]

    init?(def: ProfileDef) {
        guard let data = FileManager.default.contents(atPath: siratDataDir + "/" + def.file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = json["rows"] as? [String: [String: String]]
        else { return nil }

        self.def = def
        self.rows = rows
        let baseMinutes = json["baseStandardUtcOffsetMinutes"] as? Int ?? 60
        baseZone = TimeZone(secondsFromGMT: baseMinutes * 60)!
        timeZone = TimeZone(identifier: json["timeZoneId"] as? String ?? "Europe/Belgrade") ?? .current

        var cities: [City] = []
        if let offsets = json["cityOffsetsMinutes"] as? [String: Int] {
            for (key, offset) in offsets where !def.hiddenCities.contains(key) {
                let name = def.prettyNames[key] ?? key.prefix(1).uppercased() + key.dropFirst()
                if name != def.baseCity { cities.append(City(name: name, offset: offset)) }
            }
        }
        self.cities = [City(name: def.baseCity, offset: 0)]
            + cities.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }

    /// All prayer times for the civil day containing `day`, already shifted by `shiftMinutes`.
    func times(for day: Date, shiftMinutes: Int) -> [(PrayerDef, Date)] {
        let d = calendar.dateComponents([.year, .month, .day], from: day)
        guard let month = d.month, let dayOfMonth = d.day,
              let row = rows[String(format: "%02d-%02d", month, dayOfMonth)] else { return [] }

        var baseCal = Calendar(identifier: .gregorian)
        baseCal.timeZone = baseZone
        return prayerDefs.compactMap { prayer in
            let parts = (row[prayer.key] ?? "").split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2 else { return nil }
            let comps = DateComponents(year: d.year, month: month, day: dayOfMonth,
                                       hour: parts[0], minute: parts[1])
            guard let date = baseCal.date(from: comps) else { return nil }
            return (prayer, date.addingTimeInterval(TimeInterval(shiftMinutes * 60)))
        }
    }
}

// MARK: - App

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()
    var takvimCache: [String: Takvim] = [:]
    var timer: Timer?
    let defaults = UserDefaults.standard

    var profileId: String {
        get { defaults.string(forKey: "profile") ?? "bik" }
        set { defaults.set(newValue, forKey: "profile") }
    }
    var cityName: String? {
        get { defaults.string(forKey: "city") }
        set { defaults.set(newValue, forKey: "city") }
    }
    var adjustMinutes: Int {
        get { defaults.integer(forKey: "adjust") }
        set { defaults.set(newValue, forKey: "adjust") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        // Start automatically at login the first time the app runs.
        if !defaults.bool(forKey: "didSetupLogin") {
            try? SMAppService.mainApp.register()
            defaults.set(true, forKey: "didSetupLogin")
        }

        refresh()
        let t = Timer(timeInterval: 5, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(tick), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(tick), name: .NSSystemTimeZoneDidChange, object: nil)
    }

    @objc func tick() { refresh() }

    // MARK: Data

    func takvim() -> Takvim? {
        let def = profileDefs.first { $0.id == profileId } ?? profileDefs[0]
        if let cached = takvimCache[def.id] { return cached }
        let t = Takvim(def: def)
        takvimCache[def.id] = t
        return t
    }

    func currentCity(in t: Takvim) -> City {
        t.cities.first { $0.name == cityName } ?? t.cities[0]
    }

    func shift(for t: Takvim) -> Int { currentCity(in: t).offset + adjustMinutes }

    /// The next prayer (today, or tomorrow's Imsak) after `now`.
    func nextPrayer(_ t: Takvim, now: Date) -> (PrayerDef, Date)? {
        let shift = shift(for: t)
        if let next = t.times(for: now, shiftMinutes: shift).first(where: { $0.1 > now }) {
            return next
        }
        guard let tomorrow = t.calendar.date(byAdding: .day, value: 1, to: now) else { return nil }
        return t.times(for: tomorrow, shiftMinutes: shift).first { $0.1 > now }
    }

    // MARK: Formatting

    func remainingText(_ seconds: TimeInterval) -> String {
        let mins = max(1, Int((seconds / 60).rounded(.up)))
        if mins < 60 { return "\(mins) min" }
        let h = mins / 60, m = mins % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)min"
    }

    func clock(_ date: Date, _ t: Takvim) -> String {
        let f = DateFormatter()
        f.timeZone = t.timeZone
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    // MARK: Menu bar title

    func refresh() {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize,
                                                    weight: .regular)
        let title: String
        if let t = takvim(), let (prayer, date) = nextPrayer(t, now: Date()) {
            title = "\(prayer.name) \(remainingText(date.timeIntervalSinceNow))"
        } else {
            title = "Sirat4mac ⚠︎"
        }
        if statusItem.button?.title != title {
            statusItem.button?.attributedTitle = NSAttributedString(string: title, attributes: [.font: font])
        }
    }

    // MARK: Dropdown menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        refresh()
        menu.removeAllItems()
        let now = Date()

        guard let t = takvim() else {
            menu.addItem(info("Nuk u gjetën kohët e namazit."))
            menu.addItem(info("Kontrollo që Sirat është në /Applications."))
            addFooter(to: menu)
            return
        }

        let shift = shift(for: t)
        let today = t.times(for: now, shiftMinutes: shift)
        let next = nextPrayer(t, now: now)

        // Date header
        let df = DateFormatter()
        df.locale = Locale(identifier: "sq_AL")
        df.timeZone = t.timeZone
        df.dateFormat = "EEEE, d MMMM yyyy"
        let dateText = df.string(from: now)
        menu.addItem(info(dateText.prefix(1).uppercased() + dateText.dropFirst()))

        if let (prayer, date) = next {
            let item = NSMenuItem()
            item.attributedTitle = NSAttributedString(
                string: "\(prayer.name): edhe \(remainingText(date.timeIntervalSince(now))) (\(clock(date, t)))",
                attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)])
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())

        // Today's times, aligned in two columns
        let para = NSMutableParagraphStyle()
        para.tabStops = [NSTextTab(textAlignment: .right, location: 190)]
        for (prayer, date) in today {
            let isNext = next.map { $0.0.key == prayer.key && $0.1 == date } ?? false
            let isPast = date <= now
            let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize,
                                                        weight: isNext ? .bold : .regular)
            let color: NSColor = isPast ? .secondaryLabelColor : .labelColor
            let item = NSMenuItem()
            item.attributedTitle = NSAttributedString(
                string: "\(prayer.name)\t\(clock(date, t))",
                attributes: [.font: font, .foregroundColor: color, .paragraphStyle: para])
            item.state = isNext ? .on : .off
            item.isEnabled = true   // no action: just keeps normal (not greyed) text
            menu.addItem(item)
        }
        menu.addItem(.separator())

        // Location
        let city = currentCity(in: t)
        var place = "\(t.def.name) · \(city.name)"
        if adjustMinutes != 0 { place += " (\(adjustMinutes > 0 ? "+" : "")\(adjustMinutes) min)" }
        menu.addItem(info(place))
        menu.addItem(profileMenu())
        menu.addItem(adjustMenu())
        menu.addItem(.separator())
        addFooter(to: menu)
    }

    func info(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    func profileMenu() -> NSMenuItem {
        let root = NSMenuItem(title: "Takvimi", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for def in profileDefs {
            guard let t = takvimCache[def.id] ?? Takvim(def: def) else { continue }
            takvimCache[def.id] = t
            if t.cities.count > 1 {
                let item = NSMenuItem(title: def.name, action: nil, keyEquivalent: "")
                item.state = def.id == profileId ? .on : .off
                let citiesMenu = NSMenu()
                for city in t.cities {
                    let c = NSMenuItem(title: city.name, action: #selector(pickPlace(_:)), keyEquivalent: "")
                    c.target = self
                    c.representedObject = [def.id, city.name]
                    c.state = (def.id == profileId && city.name == currentCity(in: t).name) ? .on : .off
                    citiesMenu.addItem(c)
                }
                item.submenu = citiesMenu
                sub.addItem(item)
            } else {
                let item = NSMenuItem(title: "\(def.name) – \(def.baseCity)",
                                      action: #selector(pickPlace(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = [def.id, def.baseCity]
                item.state = def.id == profileId ? .on : .off
                sub.addItem(item)
            }
        }
        root.submenu = sub
        return root
    }

    func adjustMenu() -> NSMenuItem {
        let root = NSMenuItem(title: "Korrigjo minutat (për qytetin tënd)", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for m in -10...10 {
            let label = m == 0 ? "0 (pa korrigjim)" : "\(m > 0 ? "+" : "−")\(abs(m)) min"
            let item = NSMenuItem(title: label, action: #selector(pickAdjust(_:)), keyEquivalent: "")
            item.target = self
            item.tag = m
            item.state = m == adjustMinutes ? .on : .off
            sub.addItem(item)
        }
        root.submenu = sub
        return root
    }

    func addFooter(to menu: NSMenu) {
        let open = NSMenuItem(title: "Hap Sirat", action: #selector(openSirat), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let login = NSMenuItem(title: "Hape vetë kur ndizet Mac-u", action: #selector(toggleLogin),
                               keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        if let version = Bundle(path: siratApp + "/Wrapper/Runner.app")?
            .infoDictionary?["CFBundleShortVersionString"] as? String {
            menu.addItem(info("Burimi: Sirat \(version)"))
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Mbyll Sirat4mac", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: Actions

    @objc func pickPlace(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2 else { return }
        profileId = pair[0]
        cityName = pair[1]
        refresh()
    }

    @objc func pickAdjust(_ sender: NSMenuItem) {
        adjustMinutes = sender.tag
        refresh()
    }

    @objc func openSirat() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: siratApp),
                                           configuration: NSWorkspace.OpenConfiguration())
    }

    @objc func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
                if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            }
        } catch {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    @objc func quit() { NSApp.terminate(nil) }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
