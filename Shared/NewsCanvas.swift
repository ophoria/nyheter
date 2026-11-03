import AppKit
import CoreImage

/// The news display, drawn with Core Animation. Hosted by both the screen
/// saver and the app's preview; the host calls `tick()` about ten times a second.
/// (WKWebView was tried first, but the screen saver host suspends its web process.)
final class NewsCanvas: NSView {
    private static let photoOpacity: Float = 0.25
    private static let washOpacity: Float = 0.16
    /// After a fetch where every feed failed (offline), try again this soon instead of waiting a full interval.
    private static let offlineRetry: TimeInterval = 120

    private(set) var settings: NyheterSettings
    /// Called with everything fetched, the resulting rotation and the fetch time.
    /// Set after init, so it is called straight away with saved news already shown.
    var onFetch: ((_ fetched: [Story], _ rotation: [Story], _ hits: [Filters.Hit], _ at: Date) -> Void)? {
        didSet { if let r = lastReport { onFetch?(r.fetched, r.rotation, r.hits, r.at) } }
    }
    private var lastReport: (fetched: [Story], rotation: [Story], hits: [Filters.Hit], at: Date)?
    /// Feeds that failed or returned nothing in the last fetch.
    private(set) var failedFeeds: Set<String> = []
    /// Remember shown stories so later runs show unseen ones first. Only the real screen saver does,
    /// so the app's preview doesn't use them up.
    var recordsSeen = false
    private var theme: Theme

    private let root = CALayer()
    private let backdrop = CALayer()
    private let glowA = CAGradientLayer()
    private let glowB = CAGradientLayer()
    private let rain = CALayer()
    private let bezel = CALayer()
    private let sourceTabs = CALayer()
    private let photo = CALayer()
    /// Faint full-bleed photo behind the text (photoWash themes); on the stage so it drifts with the text.
    private let wash = CALayer()
    private let scrim = CAGradientLayer()
    private let stage = CALayer()
    private let scanlines = CAReplicatorLayer()
    private var slideLayer = CALayer()
    private let aside = CALayer()
    private let footer = CALayer()
    private let barFill = CALayer()

    private var fetched: [Story] = []    // everything the feeds returned, before ordering
    private var stories: [Story] = []
    private var current: Int?             // index of the story on screen
    private var nextIndex = 0
    private var showingCounters = false
    private var sinceCounters = 0
    private var counterLayers: [(WorldCounter, CATextLayer)] = []
    private var slideStart = Date.distantPast
    private(set) var slideDuration: TimeInterval = 15
    private var lastFetch = Date.distantPast      // when the last fetch started; drives the refresh timer
    private var newsDate = Date.distantPast       // when the news now in `fetched` was fetched
    private var fetchGeneration = 0
    private var lastDrift = Date()
    private var laidOutSize = CGSize.zero
    private var laidOutScale: CGFloat = 0
    private var imageCache: [String: CGImage] = [:]
    private var currentImage: URL?
    private var photoChangedAt = Date.distantPast
    /// Title keys of the stories shown since this canvas started.
    private var shownThisRun: Set<String> = []

    private var vw: CGFloat { bounds.width / 100 }
    private var vh: CGFloat { bounds.height / 100 }
    /// Unit for type and spacing: 1 % of the width, but no wider than on a 16:9 screen of the same height,
    /// so headlines on an ultrawide screen don't grow so tall that the text below them has no room.
    private var vu: CGFloat { min(vw, vh * 16 / 9) }
    /// Keeps content below the large clock macOS draws on the lock screen.
    private var zone: ClosedRange<CGFloat> { 24 * vh...(theme.sourceTabs ? 80 : 86) * vh }
    private var scale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }
    private var selectedCounters: [WorldCounter] {
        settings.counterIDs.compactMap { id in WorldCounter.all.first { $0.id == id } }.filter { $0.isRelevant(to: settings) }
    }
    private var countersEnabled: Bool { settings.counters && !selectedCounters.isEmpty }

    init(frame: NSRect, settings: NyheterSettings) {
        self.settings = settings
        Sources.custom = settings.customFeeds
        L10n.override = settings.language
        self.theme = Theme.named(settings.randomTheme ? (settings.randomThemeIDs.randomElement() ?? settings.themeID) : settings.themeID)
        super.init(frame: frame)
        root.isGeometryFlipped = false
        layer = root
        wantsLayer = true

        for glow in [glowA, glowB] {
            glow.type = .radial
            glow.startPoint = CGPoint(x: 0.5, y: 0.5)
            glow.endPoint = CGPoint(x: 1, y: 1)
        }
        photo.contentsGravity = .resizeAspectFill
        photo.masksToBounds = true
        photo.opacity = 0
        wash.contentsGravity = .resizeAspectFill
        wash.masksToBounds = true
        wash.opacity = 0
        scrim.startPoint = CGPoint(x: 0, y: 0.5)
        scrim.endPoint = CGPoint(x: 1, y: 0.5)
        scrim.locations = [0, 0.45, 0.8]
        stage.isGeometryFlipped = true
        barFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        rain.isGeometryFlipped = true
        rain.opacity = 0.32
        bezel.isGeometryFlipped = true
        [backdrop, glowA, glowB, rain, photo, scrim, stage, scanlines, bezel].forEach(root.addSublayer)
        stage.addSublayer(wash)
        stage.addSublayer(sourceTabs)
        [aside, footer].forEach(stage.addSublayer)
        stage.addSublayer(slideLayer)

        // Saved news shows at once; it only counts as fresh if it was fetched for the same feeds.
        if let cache = NewsCache.loadNewest() {
            fetched = cache.stories
            newsDate = cache.fetchedAt
            if cache.signature == settings.sourceSignature { lastFetch = cache.fetchedAt }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Host API

    func apply(_ new: NyheterSettings) {
        let old = settings
        Sources.custom = new.customFeeds
        settings = new
        if new.language != old.language {
            L10n.override = new.language
            laidOutSize = .zero
            relayoutIfNeeded()
        }
        if new.sourceSignature != old.sourceSignature { fetch() }
        else if new.orderSignature != old.orderSignature { reorder() }
        // In random mode a theme is drawn once per start (each screen saver run makes a new canvas);
        // here only when random mode is switched on or the current theme is taken out of the pool.
        if new.randomTheme, !old.randomTheme || !new.randomThemeIDs.contains(theme.id) {
            pickRandomTheme()
            if showingCounters || current != nil { showSlide(animated: false) }
        } else if !new.randomTheme, theme.id != new.themeID {
            theme = Theme.named(new.themeID)
            laidOutSize = .zero
            relayoutIfNeeded()
        } else if new.showQRCode != old.showQRCode || new.headlineOnly != old.headlineOnly || new.showProgress != old.showProgress
                    || new.textWidth != old.textWidth || (showingCounters && (new.counterIDs != old.counterIDs || new.counters != old.counters)) {
            if showingCounters || current != nil { showSlide(animated: false) }
        }
    }

    func tick() {
        relayoutIfNeeded()
        let now = Date()
        if now.timeIntervalSince(lastFetch) > refreshInterval { fetch() }
        if (!stories.isEmpty || countersEnabled), now.timeIntervalSince(slideStart) >= slideDuration { advance() }
        if showingCounters { updateCounters(now) }
        // Burn-in protection: nudge the whole layout a little every minute.
        if now.timeIntervalSince(lastDrift) > 60 {
            lastDrift = now
            CATransaction.begin()
            CATransaction.setAnimationDuration(20)
            stage.setAffineTransform(CGAffineTransform(translationX: .random(in: -0.8...0.8) * vw, y: .random(in: -0.8...0.8) * vh))
            CATransaction.commit()
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        relayoutIfNeeded()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        relayoutIfNeeded()
    }

    // MARK: - Data

    /// Fetches all feeds now instead of waiting for the next refresh.
    func refresh() { fetch() }

    /// Fetches every feed. Stories show as each feed answers; until then a feed's stories from the
    /// previous fetch stay, and a feed that fails keeps them (so offline shows the saved news).
    private func fetch() {
        lastFetch = Date()
        fetchGeneration += 1
        let generation = fetchGeneration
        let requests = Sources.requests(for: settings)
        guard !requests.isEmpty else { failedFeeds = []; fetched = []; reorder(); return }

        let previous = fetched
        let startedAt = lastFetch
        let signature = settings.sourceSignature
        var collected: [Story] = []
        var answered: Set<String> = []
        var failed: Set<String> = []
        var pending = requests.count
        for request in requests {
            var urlRequest = URLRequest(url: request.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            urlRequest.setValue("Nyheter/1.0 (macOS screen saver)", forHTTPHeaderField: "User-Agent")
            URLSession.shared.dataTask(with: urlRequest) { data, _, _ in
                let parsed = data.map(request.parse) ?? []
                DispatchQueue.main.async { [weak self] in
                    guard let self, generation == self.fetchGeneration else { return }
                    pending -= 1
                    if parsed.isEmpty { failed.insert(request.feed) } else { collected += parsed; answered.insert(request.feed); self.newsDate = startedAt }
                    if pending > 0 {
                        guard !parsed.isEmpty else { return }
                        self.fetched = collected + previous.filter { !answered.contains($0.feed) }
                        self.reorder()
                        return
                    }
                    self.failedFeeds = failed
                    guard !collected.isEmpty else {
                        // Nothing came back: keep what is on screen and try again soon.
                        self.lastFetch = Date().addingTimeInterval(self.offlineRetryOffset)
                        self.reorder()
                        return
                    }
                    // Feeds that failed keep their stories from before; feeds no longer asked for drop theirs.
                    self.fetched = collected + previous.filter { failed.contains($0.feed) }
                    NewsCache(fetchedAt: startedAt, signature: signature, stories: self.fetched).save()
                    self.reorder()
                }
            }.resume()
        }
    }

    /// The refresh setting: news older than this is fetched again.
    private var refreshInterval: TimeInterval {
        TimeInterval(min(max(settings.refreshMinutes, NyheterSettings.refreshRange.lowerBound), NyheterSettings.refreshRange.upperBound) * 60)
    }

    /// Moves lastFetch back so the next try comes after offlineRetry rather than a full interval.
    private var offlineRetryOffset: TimeInterval { Self.offlineRetry - refreshInterval }

    /// Rebuilds the rotation from the last fetch, keeping the story on screen.
    private func reorder() {
        let filtered = Filters.apply(fetched, settings.filters, sections: settings.blockedSections)
        if !filtered.hits.isEmpty { BlockLog.record(filtered.hits, clearedAt: settings.logClearedAt) }
        let fresh = Sources.assemble(filtered.kept, settings: settings, seen: settings.unseenFirst ? SeenStories.keys() : [])
        lastReport = (fetched, fresh, filtered.hits, newsDate)
        onFetch?(fetched, fresh, filtered.hits, newsDate)
        let currentTitle = current.flatMap { stories.indices.contains($0) ? stories[$0].title : nil }
        let wasEmpty = stories.isEmpty
        stories = fresh
        current = fresh.firstIndex { $0.title == currentTitle }
        nextIndex = current.map { ($0 + 1) % max(1, fresh.count) } ?? 0
        // The rotation puts breaking and unseen stories first; go on with the first of those not shown yet.
        if settings.breakingFirst || settings.unseenFirst,
           let first = fresh.indices.first(where: { $0 != current && !shownThisRun.contains(Sources.titleKey(fresh[$0].title)) }),
           settings.breakingLabel(for: fresh[first]) != nil || settings.unseenFirst {
            nextIndex = first
        }
        if stories.isEmpty, !countersEnabled { showPlaceholder(L("No stories – choose sources in the Nyheter app."), icon: "newspaper") }
        else if wasEmpty, !showingCounters { advance() }
    }

    // MARK: - Slides

    private func advance() {
        if countersEnabled, stories.isEmpty || sinceCounters >= settings.counterEvery {
            sinceCounters = 0
            if showingCounters, stories.isEmpty { slideStart = Date(); return }   // nothing else to show
            showingCounters = true
            current = nil
        } else if !stories.isEmpty {
            let i = nextIndex % stories.count
            current = i
            nextIndex = (i + 1) % stories.count
            sinceCounters += 1
            showingCounters = false
        } else {
            return
        }
        showSlide(animated: true)
    }

    /// Switches to another theme from the user's selection, cross-fading the whole view.
    /// (The first theme is drawn in init, so every screen saver start gets a fresh one.)
    private func pickRandomTheme() {
        let pool = settings.randomThemeIDs.filter { id in Theme.all.contains { $0.id == id } }
        guard let next = (pool.count > 1 ? pool.filter { $0 != theme.id } : pool).randomElement(), next != theme.id else { return }
        theme = Theme.named(next)
        let fade = CATransition()
        fade.type = .fade
        fade.duration = 0.9
        root.add(fade, forKey: "theme")
        layoutThemeLayers()
    }

    private func showSlide(animated: Bool) {
        slideStart = Date()
        let source: String
        let content: CALayer
        if showingCounters {
            source = "world"
            slideDuration = settings.counterSeconds
            content = makeCounters(animated: animated)
            updatePhoto(nil)
        } else if let i = current, stories.indices.contains(i) {
            let story = stories[i]
            source = story.source
            shownThisRun.insert(Sources.titleKey(story.title))
            if recordsSeen { SeenStories.record(story) }
            let made = makeStory(story, animated: animated)
            content = made.layer
            slideDuration = settings.duration(words: made.visibleWords, headlineOnly: settings.headlineOnly)
            updatePhoto(theme.photo || theme.photoWash ? story.imageURL : nil)
        } else {
            return
        }
        applyColors(source, animated: animated)
        replaceSlide(with: content, animated: animated)
        rebuildAside(animated: animated)
        rebuildFooter(source)
        rebuildSourceTabs(source)
    }

    private func showPlaceholder(_ text: String, icon: String) {
        current = nil
        showingCounters = false
        let size = 2.4 * vu
        let label = textLayer(NSAttributedString(string: text, attributes: attrs(theme.headline.font(size), theme.muted)), width: 60 * vw)
        let symbol = iconLayer(icon, size: size, color: theme.muted)
        symbol.frame.origin = CGPoint(x: 0, y: (label.bounds.height - size) / 2)
        label.frame.origin = CGPoint(x: size * 1.5, y: 0)
        if icon == "download" {
            let bob = CABasicAnimation(keyPath: "transform.translation.y")
            bob.fromValue = -0.08 * size
            bob.toValue = 0.08 * size
            bob.duration = 0.9
            bob.autoreverses = true
            bob.repeatCount = .infinity
            bob.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            symbol.add(bob, forKey: "bob")
        }
        let placeholder = CALayer()
        placeholder.addSublayer(symbol)
        placeholder.addSublayer(label)
        placeholder.frame = CGRect(x: 5 * vw, y: 48 * vh, width: label.frame.maxX, height: label.bounds.height)
        replaceSlide(with: placeholder, animated: false)
        aside.sublayers?.forEach { $0.removeFromSuperlayer() }
        footer.sublayers?.forEach { $0.removeFromSuperlayer() }
        applyColors(settings.enabledProviders.first?.id ?? "svt", animated: false)
    }

    // MARK: - Layout

    private func relayoutIfNeeded() {
        guard bounds.width > 0, bounds.size != laidOutSize || scale != laidOutScale else { return }
        laidOutSize = bounds.size
        laidOutScale = scale
        layoutThemeLayers()
        if stories.isEmpty, !fetched.isEmpty { reorder() }   // saved news from the last run
        if showingCounters || current != nil { showSlide(animated: false) }
        else if stories.isEmpty { showPlaceholder(L("Fetching news…"), icon: "download") }
    }

    /// Sizes and styles the background layers for the current theme.
    private func layoutThemeLayers() {
        let w = bounds.width, h = bounds.height, size = max(w, h) * 1.2

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for l in [backdrop, stage, photo, scrim, scanlines, rain, bezel] { l.frame = bounds }
        // Bleeds past the edges so the burn-in drift never uncovers them.
        wash.frame = bounds.insetBy(dx: -vw, dy: -vh)
        glowA.frame = CGRect(x: -0.3 * size, y: -0.4 * size, width: size, height: size)
        glowB.frame = CGRect(x: w - 0.6 * size, y: h - 0.55 * size, width: size, height: size)
        glowA.isHidden = theme.glows == nil
        glowB.isHidden = theme.glows == nil
        scrim.isHidden = !theme.photo
        scrim.colors = [theme.background.cgColor, theme.background.withAlphaComponent(0.6).cgColor, theme.background.withAlphaComponent(0).cgColor]
        photo.isHidden = !theme.photo
        wash.isHidden = !theme.photoWash
        // Photo themes process images differently, so load the current one again.
        currentImage = nil
        photo.opacity = 0
        wash.opacity = 0

        // CRT scanlines for the terminal theme.
        scanlines.sublayers?.forEach { $0.removeFromSuperlayer() }
        scanlines.isHidden = !theme.scanlines
        if theme.scanlines {
            let line = CALayer()
            line.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
            line.frame = CGRect(x: 0, y: 0, width: w, height: 1)
            scanlines.addSublayer(line)
            scanlines.instanceCount = Int(h / 3) + 1
            scanlines.instanceTransform = CATransform3DMakeTranslation(0, 3, 0)
        }
        CATransaction.commit()

        drift(glowA, by: CGSize(width: 0.25 * w, height: 0.3 * h), duration: 70)
        drift(glowB, by: CGSize(width: -0.2 * w, height: -0.25 * h), duration: 90)
        buildRain()
        buildBezel()
        applyGlow(aside)
        applyGlow(footer)
        applyGlow(sourceTabs)
        sourceTabs.isHidden = !theme.sourceTabs

        stage.removeAnimation(forKey: "flicker")
        if theme.flicker {
            let flicker = CAKeyframeAnimation(keyPath: "opacity")
            flicker.values = [1, 1, 0.9, 1, 0.96, 1, 1, 0.93, 1]
            flicker.keyTimes = [0, 0.4, 0.41, 0.42, 0.7, 0.71, 0.88, 0.885, 0.89]
            flicker.duration = 5.3
            flicker.repeatCount = .infinity
            stage.add(flicker, forKey: "flicker")
        }
    }

    /// A CRT screen: dark rounded bezel, glowing inner edge, vignette and a soft glass glare.
    private func buildBezel() {
        bezel.sublayers?.forEach { $0.removeFromSuperlayer() }
        bezel.isHidden = !theme.bezel
        guard theme.bezel else { return }
        let inset = 1.6 * vu, radius = 3.2 * vu
        let screen = bounds.insetBy(dx: inset, dy: inset)
        let screenPath = CGPath(roundedRect: screen, cornerWidth: radius, cornerHeight: radius, transform: nil)

        let vignette = CAGradientLayer()
        vignette.type = .radial
        vignette.frame = bounds
        vignette.startPoint = CGPoint(x: 0.5, y: 0.5)
        vignette.endPoint = CGPoint(x: 1.15, y: 1.15)
        vignette.colors = [NSColor.clear.cgColor, NSColor.clear.cgColor, NSColor.black.withAlphaComponent(0.75).cgColor]
        vignette.locations = [0, 0.55, 1]

        let glare = CAGradientLayer()
        glare.frame = bounds
        glare.startPoint = CGPoint(x: 0, y: 0)
        glare.endPoint = CGPoint(x: 0.6, y: 0.6)
        glare.colors = [NSColor.white.withAlphaComponent(0.07).cgColor, NSColor.white.withAlphaComponent(0).cgColor]
        let glareMask = CAShapeLayer()
        glareMask.path = screenPath
        glare.mask = glareMask

        let frame = CAShapeLayer()
        let outside = CGMutablePath()
        outside.addRect(bounds)
        outside.addPath(screenPath)
        frame.path = outside
        frame.fillRule = .evenOdd
        frame.fillColor = hex(0x070908).cgColor

        let edge = CAShapeLayer()
        edge.path = screenPath
        edge.fillColor = nil
        edge.strokeColor = theme.text.withAlphaComponent(0.45).cgColor
        edge.lineWidth = max(1.5, 0.12 * vu)
        edge.shadowColor = theme.text.cgColor
        edge.shadowRadius = 0.8 * vu
        edge.shadowOpacity = 0.9
        edge.shadowOffset = .zero

        [vignette, glare, frame, edge].forEach(bezel.addSublayer)
    }

    /// Tabs naming the enabled sources, the current one lit up.
    private func rebuildSourceTabs(_ current: String) {
        sourceTabs.sublayers?.forEach { $0.removeFromSuperlayer() }
        guard theme.sourceTabs else { return }
        let size = 1 * vu, pad = CGSize(width: 1 * vu, height: 0.55 * vh)
        let kinds = settings.enabledProviders.map(\.id) + (countersEnabled ? ["world"] : [])
        var x: CGFloat = 0, height: CGFloat = 0
        var tabs: [CALayer] = []
        for kind in kinds {
            let active = kind == current
            let label = textLayer(upper(Sources.label(kind), theme.ui.font(size), active ? theme.background : theme.muted, kern: 0.18), width: 20 * vu)
            let tab = CALayer()
            tab.frame = CGRect(x: x, y: 0, width: label.bounds.width + 2 * pad.width, height: label.bounds.height + 2 * pad.height)
            label.frame.origin = CGPoint(x: pad.width, y: pad.height)
            tab.addSublayer(label)
            if active {
                tab.backgroundColor = theme.text.cgColor
            } else {
                tab.borderColor = theme.rule.cgColor
                tab.borderWidth = 1
            }
            tabs.append(tab)
            height = tab.bounds.height
            x += tab.bounds.width + 0.6 * vu
        }
        let line = CALayer()
        line.backgroundColor = theme.text.withAlphaComponent(0.5).cgColor
        line.frame = CGRect(x: 0, y: height, width: bounds.width - 10 * vw, height: 2)
        tabs.forEach(sourceTabs.addSublayer)
        sourceTabs.addSublayer(line)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sourceTabs.frame = CGRect(x: 5 * vw, y: bounds.height - 11 * vh - height, width: bounds.width - 10 * vw, height: height + 2)
        CATransaction.commit()
    }

    /// Matrix-style columns of glyphs falling at different speeds.
    private func buildRain() {
        rain.sublayers?.forEach { $0.removeFromSuperlayer() }
        rain.isHidden = !theme.rain
        guard theme.rain, bounds.width > 0 else { return }
        let glyph = 1.25 * vu
        let font = NSFont.monospacedSystemFont(ofSize: glyph, weight: .medium)
        let glyphs = Array("ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ0123456789Z:.=*+-<>")
        let head = NSColor(srgbRed: 0.85, green: 1, blue: 0.88, alpha: 1)
        var x: CGFloat = 0
        while x < bounds.width {
            defer { x += glyph * 1.2 }
            guard Double.random(in: 0...1) < 0.6 else { continue }
            let count = Int.random(in: 8...30)
            let text = NSMutableAttributedString()
            for i in 0..<count {
                let isHead = i == count - 1
                text.append(NSAttributedString(string: String(glyphs.randomElement()!) + (isHead ? "" : "\n"),
                                               attributes: attrs(font, isHead ? head : theme.text, lineHeight: glyph * 1.2)))
            }
            let column = textLayer(text, width: glyph * 1.5)
            let fade = CAGradientLayer()
            fade.frame = column.bounds.insetBy(dx: -glyph, dy: -glyph)
            fade.colors = [NSColor.clear.cgColor, NSColor.black.cgColor]
            fade.startPoint = CGPoint(x: 0.5, y: 0)
            fade.endPoint = CGPoint(x: 0.5, y: 0.85)
            column.mask = fade
            column.opacity = Float.random(in: 0.35...1)
            let height = column.bounds.height
            column.frame.origin = CGPoint(x: x, y: CGFloat.random(in: -height...bounds.height))
            let fall = CABasicAnimation(keyPath: "position.y")
            fall.fromValue = -height / 2
            fall.toValue = bounds.height + height / 2
            fall.duration = .random(in: 7...18)
            fall.timeOffset = .random(in: 0...fall.duration)
            fall.repeatCount = .infinity
            column.add(fall, forKey: "fall")
            rain.addSublayer(column)
        }
    }

    /// Soft glow around text for themes that want it; cleared otherwise.
    private func applyGlow(_ layer: CALayer) {
        layer.shadowColor = theme.text.cgColor
        layer.shadowOffset = .zero
        layer.shadowRadius = 0.45 * vu
        layer.shadowOpacity = theme.textGlow ? 0.8 : 0
    }

    private func drift(_ layer: CALayer, by offset: CGSize, duration: CFTimeInterval) {
        let anim = CABasicAnimation(keyPath: "transform.translation")
        anim.fromValue = NSValue(size: .zero)
        anim.toValue = NSValue(size: offset)
        anim.duration = duration
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(anim, forKey: "drift")
    }

    private func applyColors(_ source: String, animated: Bool) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 1.5 : 0)
        CATransaction.setDisableActions(!animated)
        backdrop.backgroundColor = theme.backdrop(source).cgColor
        if let glows = theme.glows, let second = theme.secondGlows {
            glowA.colors = glowColors(glows[Sources.paletteKey(source)] ?? theme.accent(source), theme.glowAlpha)
            glowB.colors = glowColors(second[Sources.paletteKey(source)] ?? theme.accent(source), theme.glowAlpha)
        } else if let glows = theme.glows {
            glowA.colors = glowColors(theme.accent(source), theme.glowAlpha)
            glowB.colors = glowColors(glows[Sources.paletteKey(source)] ?? theme.accent(source), theme.glowAlpha * 0.6)
        }
        CATransaction.commit()
    }

    // MARK: - Story slide

    /// Width of the main column: narrower when the QR code column is shown.
    /// Wash themes keep the column's space open so the photo shows there even when the column is off.
    private var narrow: Bool { settings.showQRCode || theme.photoWash }
    /// The user's text width (a share of the screen's width) never reaches into the QR code column.
    private var mainWidth: CGFloat {
        let widest = CGFloat(narrow ? NyheterSettings.textWidthBesideColumn : NyheterSettings.textWidthFull)
        return (settings.textWidth > 0 ? min(CGFloat(settings.textWidth), widest) : widest) * vw
    }
    private var ledeWidth: CGFloat { mainWidth * (narrow ? 48 / 58 : 64 / 86) }

    /// Builds a story slide and counts the words actually on screen (truncated text excluded).
    private func makeStory(_ story: Story, animated: Bool) -> (layer: CALayer, visibleWords: Int) {
        let container = CALayer()
        var visible: [NSAttributedString] = []
        let width = mainWidth
        var y: CGFloat = 0
        var parts: [CALayer] = []

        if theme.kickerRule {
            let rules = kickerRules(width: width)
            container.addSublayer(rules)
            y += rules.bounds.height + 2.5 * vh
        }

        let meta = metaRow(chip: Sources.label(story.source), mark: story.source, category: L(story.category), age: ago(story.date),
                           breaking: settings.breakingLabel(for: story))
        meta.frame.origin.y = y
        container.addSublayer(meta)
        parts.append(meta)
        y += meta.bounds.height + 3 * vh

        // Headline, one layer per line so lines can stagger in.
        // Headline-only slides get a larger headline to fill the space.
        let headSize = (story.title.count > 70 ? 4.1 : 5.2) * vu * theme.headlineScale * (settings.headlineOnly ? 1.25 : 1)
        let lineHeight = headSize * theme.headlineLineHeight
        let title = theme.uppercaseHeadline ? story.title.uppercased(with: Locale(identifier: "sv_SE")) : story.title
        let headline = NSAttributedString(string: title,
            attributes: attrs(theme.headline.font(headSize), theme.text, lineHeight: lineHeight, kern: theme.headlineKern))
        var lines: [CALayer] = []
        for line in splitLines(headline, width: width).prefix(settings.headlineOnly ? 5 : 4) {
            visible.append(line)
            let l = textLayer(line, width: width + 4)
            l.frame.origin = CGPoint(x: 0, y: y)
            container.addSublayer(l)
            lines.append(l)
            y += lineHeight
        }
        if theme.cursor, let last = lines.last {
            let cursor = CALayer()
            cursor.backgroundColor = theme.text.cgColor
            cursor.frame = CGRect(x: last.frame.maxX + 0.25 * headSize, y: last.frame.minY + lineHeight * 0.12,
                                  width: 0.55 * headSize, height: lineHeight * 0.8)
            let blink = CAKeyframeAnimation(keyPath: "opacity")
            blink.values = [1, 1, 0, 0]
            blink.keyTimes = [0, 0.5, 0.5, 1]
            blink.duration = 1.1
            blink.repeatCount = .infinity
            cursor.add(blink, forKey: "blink")
            container.addSublayer(cursor)
        }

        // Lede: bullet points (SR) or intro paragraph.
        let lede = CALayer()
        if !settings.headlineOnly {
            y += 4 * vh
            let ledeSize = 1.6 * vu * theme.ledeScale, ledeLine = ledeSize * 1.45
            let ledeAttrs = attrs(theme.lede.font(ledeSize), theme.text.withAlphaComponent(theme.ledeAlpha), lineHeight: ledeLine)
            var ly: CGFloat = 0
            // Room left before the content zone ends, so long ledes never run into the footer.
            let room = zone.upperBound - zone.lowerBound - y
            if story.bullets {
                for bullet in story.body {
                    let dash = CALayer()
                    dash.backgroundColor = theme.mark(story.source).cgColor
                    dash.frame = CGRect(x: 0, y: ly + ledeLine * 0.55, width: 0.5 * vu, height: 2)
                    let text = NSAttributedString(string: bullet, attributes: ledeAttrs)
                    let t = textLayer(text, width: ledeWidth - 2 * vu, maxHeight: ledeLine * 2)
                    guard ly + t.bounds.height <= room else { break }
                    t.frame.origin = CGPoint(x: 1.4 * vu, y: ly)
                    visible += splitLines(text, width: ledeWidth - 2 * vu).prefix(2)
                    lede.addSublayer(dash)
                    lede.addSublayer(t)
                    ly += t.bounds.height + 1.2 * vh
                }
            } else if let text = story.body.first, !text.isEmpty {
                let paragraph = NSAttributedString(string: text, attributes: ledeAttrs)
                let lines = max(0, min(4, Int(room / ledeLine)))
                visible += splitLines(paragraph, width: ledeWidth).prefix(lines)
                let t = textLayer(paragraph, width: ledeWidth, maxHeight: ledeLine * CGFloat(lines))
                lede.addSublayer(t)
                ly = t.bounds.height
            }
            lede.frame = CGRect(x: 0, y: y, width: ledeWidth, height: ly)
            container.addSublayer(lede)
            y += ly
        }

        let top = max(zone.lowerBound, (zone.lowerBound + zone.upperBound - y) / 2)
        container.frame = CGRect(x: 5 * vw, y: top, width: width, height: y)

        if animated {
            fadeIn(meta, delay: 0.6, dy: 1.5 * vh)
            for (k, line) in lines.enumerated() { fadeIn(line, delay: 0.75 + 0.14 * Double(k), dy: 0.35 * headSize) }
            fadeIn(lede, delay: 1.0 + 0.14 * Double(lines.count), dy: 1.5 * vh)
        }
        let words = visible.reduce(0) { $0 + $1.string.split(whereSeparator: \.isWhitespace).count }
        return (container, words)
    }

    // MARK: - Counter slide

    private func makeCounters(animated: Bool) -> CALayer {
        let container = CALayer()
        let width = mainWidth
        let columns = narrow ? 2 : 3
        var y: CGFloat = 0
        if theme.kickerRule {
            let rules = kickerRules(width: width)
            container.addSublayer(rules)
            y += rules.bounds.height + 2.5 * vh
        }
        let meta = metaRow(chip: Sources.label("world"), mark: "world", category: L("Right now"), age: L("Live"))
        meta.frame.origin.y = y
        container.addSublayer(meta)
        y += meta.bounds.height + 3 * vh

        let headSize = 3.6 * vu * theme.headlineScale
        let heading = textLayer(NSAttributedString(string: theme.uppercaseHeadline ? L("The world right now").uppercased(with: L10n.locale) : L("The world right now"),
            attributes: attrs(theme.headline.font(headSize), theme.text, kern: theme.headlineKern)), width: width)
        heading.frame.origin.y = y
        container.addSublayer(heading)
        y += heading.bounds.height + 4 * vh

        counterLayers = []
        let counters = Array(selectedCounters.prefix(8))
        let columnWidth = 28 * vu
        let numberSize = (counters.count > 4 ? 2.8 : 3.2) * vu
        let numberFont = theme.number.numberFont(numberSize)
        var rowHeight: CGFloat = 0
        var cells: [CALayer] = []
        for (k, counter) in counters.enumerated() {
            let cell = CALayer()
            let label = textLayer(upper(L(counter.label), theme.ui.font(0.85 * vu), theme.muted, kern: 0.12), width: columnWidth - 2 * vu)
            let number = CATextLayer()
            number.contentsScale = scale
            number.frame = CGRect(x: 0, y: label.bounds.height + 0.8 * vh, width: columnWidth, height: numberSize * 1.25)
            counterLayers.append((counter, number))
            cell.addSublayer(label)
            cell.addSublayer(number)
            let h = number.frame.maxY
            rowHeight = max(rowHeight, h)
            cell.frame = CGRect(x: CGFloat(k % columns) * (columnWidth + 2 * vu), y: 0, width: columnWidth, height: h)
            cells.append(cell)
        }
        for (k, cell) in cells.enumerated() {
            cell.frame.origin.y = y + CGFloat(k / columns) * (rowHeight + 3.5 * vh)
            container.addSublayer(cell)
            if animated { fadeIn(cell, delay: 0.7 + 0.1 * Double(k), dy: 1.5 * vh) }
        }
        y += CGFloat((cells.count + columns - 1) / columns) * (rowHeight + 3.5 * vh)
        counterFont = numberFont
        updateCounters(Date())

        let note = textLayer(NSAttributedString(string: L("Real-time estimates, calculated from published yearly figures:") + " "
            + Set(counters.map { L($0.source) }).sorted().joined(separator: ", ") + ".",
            attributes: attrs(theme.ui.font(0.75 * vu), theme.muted)), width: width)
        note.frame.origin.y = y
        container.addSublayer(note)
        y += note.bounds.height

        let top = max(zone.lowerBound, (zone.lowerBound + zone.upperBound - y) / 2)
        container.frame = CGRect(x: 5 * vw, y: top, width: width, height: y)
        if animated {
            fadeIn(meta, delay: 0.6, dy: 1.5 * vh)
            fadeIn(heading, delay: 0.7, dy: 2 * vh)
        }
        return container
    }

    private var counterFont = NSFont.systemFont(ofSize: 12)

    private func updateCounters(_ now: Date) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (counter, layer) in counterLayers {
            let text = WorldCounter.formatter.string(from: NSNumber(value: counter.value(at: now).rounded(.down))) ?? ""
            layer.string = NSAttributedString(string: text, attributes: [.font: counterFont, .foregroundColor: theme.text])
        }
        CATransaction.commit()
    }

    // MARK: - Shared slide parts

    private func metaRow(chip label: String, mark source: String, category: String, age: String, breaking: String? = nil) -> CALayer {
        let size = 1 * vu
        let chip = CALayer()
        let pad = CGSize(width: 0.7 * vu, height: 0.45 * vh)
        switch theme.chip {
        case .filled, .inverted:
            let filled = theme.chip == .filled
            let chipText = textLayer(upper(label, theme.ui.font(size), filled ? theme.backdrop(source) : theme.accent(source), kern: 0.16), width: 20 * vu)
            chip.backgroundColor = (filled ? theme.accent(source) : theme.text).cgColor
            chip.frame = CGRect(x: 0, y: 0, width: chipText.bounds.width + 2 * pad.width, height: chipText.bounds.height + 2 * pad.height)
            chip.cornerRadius = chip.bounds.height * theme.chipRadius
            chipText.frame.origin = CGPoint(x: pad.width, y: pad.height)
            chip.addSublayer(chipText)
        case .highlight:
            let chipText = textLayer(upper(label, theme.ui.font(size), theme.onHighlight, kern: 0.16), width: 20 * vu)
            chip.backgroundColor = theme.mark(source).cgColor
            chip.frame = CGRect(x: 0, y: 0, width: chipText.bounds.width + 2 * pad.width, height: chipText.bounds.height + 2 * pad.height)
            chip.cornerRadius = chip.bounds.height * theme.chipRadius
            chipText.frame.origin = CGPoint(x: pad.width, y: pad.height)
            chip.addSublayer(chipText)
        case .underline:
            let chipText = textLayer(upper(label, theme.ui.font(size), theme.accent(source), kern: 0.16), width: 20 * vu)
            let line = CALayer()
            line.backgroundColor = theme.accent(source).cgColor
            line.frame = CGRect(x: 0, y: chipText.bounds.height + pad.height, width: chipText.bounds.width, height: 2)
            chip.frame = CGRect(x: 0, y: 0, width: chipText.bounds.width, height: line.frame.maxY)
            chip.addSublayer(chipText)
            chip.addSublayer(line)
        }
        let categoryLayer = textLayer(upper(category, theme.ui.font(size), theme.text, kern: 0.16), width: 20 * vu)
        let ageLayer = textLayer(upper(age, FontSpec(family: theme.ui.family, weight: .regular).font(size), theme.muted, kern: 0.16), width: 20 * vu)
        let meta = CALayer()
        var x: CGFloat = 0
        let parts = [chip] + (breaking.map { [breakingTag($0, source: source, size: size)] } ?? []) + [categoryLayer, ageLayer]
        for part in parts {
            part.frame.origin = CGPoint(x: x, y: (chip.bounds.height - part.bounds.height) / 2)
            meta.addSublayer(part)
            x += part.bounds.width + 1.2 * vu
        }
        meta.frame = CGRect(x: 0, y: 0, width: x, height: chip.bounds.height)
        return meta
    }

    /// A pulsing dot and the reason a story counts as breaking ("New" or the watchword it mentions).
    private func breakingTag(_ text: String, source: String, size: CGFloat) -> CALayer {
        let color = theme.mark(source)
        let label = textLayer(upper(text, theme.ui.font(size), color, kern: 0.16), width: 20 * vu)
        let d = 0.55 * size
        let dot = CALayer()
        dot.backgroundColor = color.cgColor
        dot.cornerRadius = d / 2
        dot.frame = CGRect(x: 0, y: (label.bounds.height - d) / 2, width: d, height: d)
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = 0.25
        pulse.duration = 0.9
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dot.add(pulse, forKey: "pulse")
        label.frame.origin = CGPoint(x: d + 0.5 * size, y: 0)
        let tag = CALayer()
        tag.addSublayer(dot)
        tag.addSublayer(label)
        tag.frame = CGRect(x: 0, y: 0, width: label.frame.maxX, height: label.bounds.height)
        return tag
    }

    /// Newspaper-style thick-and-thin rule above the kicker, or a solid block in the highlight colour.
    private func kickerRules(width: CGFloat) -> CALayer {
        let rules = CALayer()
        if let highlight = theme.highlight {
            rules.backgroundColor = highlight.cgColor
            rules.frame = CGRect(x: 0, y: 0, width: 7 * vu, height: 1 * vh)
            return rules
        }
        let thick = CALayer(), thin = CALayer()
        thick.backgroundColor = theme.text.cgColor
        thin.backgroundColor = theme.text.cgColor
        thick.frame = CGRect(x: 0, y: 0, width: width, height: 3)
        thin.frame = CGRect(x: 0, y: 6, width: width, height: 1)
        rules.addSublayer(thick)
        rules.addSublayer(thin)
        rules.frame = CGRect(x: 0, y: 0, width: width, height: 7)
        return rules
    }

    private func replaceSlide(with new: CALayer, animated: Bool) {
        applyGlow(new)
        let old = slideLayer
        slideLayer = new
        stage.addSublayer(new)
        guard animated else { old.removeFromSuperlayer(); return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.7)
        CATransaction.setCompletionBlock { old.removeFromSuperlayer() }
        old.opacity = 0
        old.setAffineTransform(CGAffineTransform(translationX: 0, y: -2 * vh))
        CATransaction.commit()
    }

    private func fadeIn(_ layer: CALayer, delay: CFTimeInterval, dy: CGFloat) {
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0
        opacity.toValue = 1
        let move = CABasicAnimation(keyPath: "transform.translation.y")
        move.fromValue = dy
        move.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [opacity, move]
        group.beginTime = CACurrentMediaTime() + delay
        group.duration = 0.9
        group.fillMode = .backwards
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.7, 0.2, 1)
        layer.add(group, forKey: "in")
    }

    // MARK: - QR code column and footer

    /// The right-hand column: a QR code to the story on the source's own site, to read on a phone.
    private func rebuildAside(animated: Bool) {
        aside.sublayers?.forEach { $0.removeFromSuperlayer() }
        let width = 26 * vu, pad = 2.2 * vu
        let story = showingCounters ? nil : current.flatMap { stories.indices.contains($0) ? stories[$0] : nil }
        let link = story?.link
        var y: CGFloat = 0

        let side = 13 * vu
        if let link, let story, let code = qrImage(link, source: story.source, pixels: side * scale) {
            let heading = textLayer(upper(L("Read the whole story"), theme.ui.font(0.8 * vu), theme.mark(story.source), kern: 0.14), width: width - pad)
            heading.frame.origin = CGPoint(x: pad, y: y)
            aside.addSublayer(heading)
            y += heading.bounds.height + 1.6 * vh

            // On a light page the quiet zone is the page itself (transparent), so the modules line up with
            // the text; on a dark page the code sits on a light card.
            let quiet = code.onPage ? side * 4 / CGFloat(code.width / code.modulePixels) : 0
            let plate = CALayer()
            plate.frame = CGRect(x: pad - quiet, y: y - quiet, width: side, height: side)
            plate.contents = code.image
            plate.magnificationFilter = .nearest
            plate.cornerRadius = 0.6 * vu
            plate.masksToBounds = true
            aside.addSublayer(plate)
            y += side - 2 * quiet + 1.6 * vh

            let site = textLayer(NSAttributedString(string: Self.siteName(link),
                attributes: attrs(FontSpec(family: theme.ui.family, weight: .semibold).font(1 * vu), theme.text)), width: width - pad)
            site.frame.origin = CGPoint(x: pad, y: y)
            aside.addSublayer(site)
            y += site.bounds.height + 0.6 * vh
            let hint = textLayer(NSAttributedString(string: L("Point your phone's camera at the code."),
                attributes: attrs(FontSpec(family: theme.ui.family, weight: .regular).font(0.85 * vu), theme.muted, lineHeight: 1.2 * vu)),
                width: side)
            hint.frame.origin = CGPoint(x: pad, y: y)
            aside.addSublayer(hint)
            y += hint.bounds.height
        }

        let border = CALayer()
        border.backgroundColor = theme.rule.cgColor
        border.frame = CGRect(x: 0, y: 0, width: 1, height: y)
        aside.addSublayer(border)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        aside.isHidden = y == 0 || !settings.showQRCode
        aside.frame = CGRect(x: bounds.width - 5 * vw - width, y: (zone.lowerBound + zone.upperBound - y) / 2, width: width, height: y)
        CATransaction.commit()
        if animated {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.8
            aside.add(fade, forKey: "fade")
        }
    }

    /// A QR code for the link, dark modules on a light ground (what phone cameras read best), in the
    /// theme's own text and background colours, with the standard four-module quiet zone. When the page
    /// itself is the light colour, the ground is left transparent (`onPage`).
    private func qrImage(_ link: URL, source: String, pixels: CGFloat) -> (image: CGImage, width: Int, modulePixels: Int, onPage: Bool)? {
        guard let generator = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        generator.setValue(Data(link.absoluteString.utf8), forKey: "inputMessage")
        generator.setValue("M", forKey: "inputCorrectionLevel")
        guard let code = generator.outputImage else { return nil }

        let a = theme.text, b = theme.backdrop(source)
        let (dark, light) = Self.luminance(a) < Self.luminance(b) ? (a, b) : (b, a)
        let onPage = light == b && !theme.photo
        guard let colored = CIFilter(name: "CIFalseColor") else { return nil }
        colored.setValue(code, forKey: kCIInputImageKey)
        colored.setValue(CIColor(color: dark) ?? CIColor.black, forKey: "inputColor0")
        colored.setValue(onPage ? CIColor.clear : CIColor(color: light) ?? CIColor.white, forKey: "inputColor1")
        guard let modules = colored.outputImage else { return nil }

        let quiet: CGFloat = 4
        let plate = CIImage(color: onPage ? CIColor.clear : CIColor(color: light) ?? CIColor.white)
            .cropped(to: modules.extent.insetBy(dx: -quiet, dy: -quiet))
        let composed = modules.composited(over: plate).transformed(by: CGAffineTransform(translationX: quiet, y: quiet))
        // Whole pixels per module, scaled without smoothing, so the edges stay sharp for the camera.
        let factor = max(1, (pixels / composed.extent.width).rounded(.up))
        let sharp = composed.samplingNearest().transformed(by: CGAffineTransform(scaleX: factor, y: factor))
        guard let image = CIContext().createCGImage(sharp, from: CGRect(origin: .zero, size: sharp.extent.size)) else { return nil }
        return (image, image.width, Int(factor), onPage)
    }

    private static func luminance(_ color: NSColor) -> CGFloat {
        guard let c = color.usingColorSpace(.sRGB) else { return 0 }
        return 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
    }

    /// "reuters.com", or the aggregator's name for links that go through one.
    private static func siteName(_ link: URL) -> String {
        let host = link.host ?? link.absoluteString
        if host == "news.google.com" { return "Google News" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Just the progress line and a position counter.
    private func rebuildFooter(_ source: String) {
        footer.sublayers?.forEach { $0.removeFromSuperlayer() }
        let width = bounds.width - 10 * vw
        let position = showingCounters ? "" : current.map { "\($0 + 1) / \(stories.count)" } ?? ""
        let count = textLayer(upper(position, theme.ui.font(0.8 * vu), theme.muted, kern: 0.12), width: 10 * vu)
        let height = max(count.bounds.height, 2)
        count.frame.origin = CGPoint(x: width - count.bounds.width, y: 0)
        footer.addSublayer(count)

        let track = CALayer()
        track.backgroundColor = theme.rule.cgColor
        let trackWidth = position.isEmpty ? width : count.frame.minX - 2 * vu
        track.frame = CGRect(x: 0, y: height / 2 - 1, width: max(0, trackWidth), height: 2)
        footer.addSublayer(track)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let footerY = bounds.height - 4.5 * vh - height
        footer.frame = CGRect(x: 5 * vw, y: footerY, width: width, height: height)
        footer.isHidden = !settings.showProgress
        barFill.backgroundColor = theme.mark(source).cgColor
        barFill.frame = track.bounds
        track.addSublayer(barFill)
        CATransaction.commit()

        barFill.removeAllAnimations()
        let progress = CABasicAnimation(keyPath: "transform.scale.x")
        progress.fromValue = 0
        progress.toValue = 1
        progress.duration = slideDuration
        progress.fillMode = .forwards
        progress.isRemovedOnCompletion = false
        barFill.add(progress, forKey: "progress")
    }

    // MARK: - Background photo

    private func updatePhoto(_ url: URL?) {
        guard url != currentImage || url == nil else { return }
        currentImage = url
        photoChangedAt = Date()
        CATransaction.begin()
        CATransaction.setAnimationDuration(1)
        photo.opacity = 0
        wash.opacity = 0
        CATransaction.commit()
        guard let url else { return }
        let color = theme.photoWash, key = "\(color)\(url.absoluteString)"
        if let image = imageCache[key] { showPhoto(image, for: url); return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = Self.process(data, color: color) else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                if self.imageCache.count > 8 { self.imageCache.removeAll() }
                self.imageCache[key] = image
                self.showPhoto(image, for: url)
            }
        }.resume()
    }

    private func showPhoto(_ image: CGImage, for url: URL) {
        let wait = max(0, 1 - Date().timeIntervalSince(photoChangedAt))
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self, self.currentImage == url, self.theme.photo || self.theme.photoWash else { return }
            let washed = self.theme.photoWash
            let target = washed ? self.wash : self.photo
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            target.contents = image
            CATransaction.commit()

            let zoom = CABasicAnimation(keyPath: "transform.scale")
            zoom.fromValue = washed ? 1 : 1.04
            zoom.toValue = washed ? 1.06 : 1.14
            zoom.duration = 30
            zoom.fillMode = .forwards
            zoom.isRemovedOnCompletion = false
            target.add(zoom, forKey: "kenburns")

            CATransaction.begin()
            CATransaction.setAnimationDuration(2.5)
            if washed { self.wash.opacity = Self.washOpacity } else { self.photo.opacity = Self.photoOpacity }
            CATransaction.commit()
        }
    }

    /// Downscaled; greyscale and darkened so the photo sits behind the text, or (wash)
    /// in slightly muted colour, like ink on newsprint.
    private static func process(_ data: Data, color: Bool) -> CGImage? {
        guard var image = CIImage(data: data) else { return nil }
        let scale = min(1, 1920 / image.extent.width)
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let filter = CIFilter(name: "CIColorControls") else { return nil }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(color ? 0.85 : 0, forKey: kCIInputSaturationKey)
        filter.setValue(color ? 0 : -0.12, forKey: kCIInputBrightnessKey)
        filter.setValue(color ? 1.04 : 1.1, forKey: kCIInputContrastKey)
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: image.extent)
    }

    // MARK: - Text helpers

    private func attrs(_ font: NSFont, _ color: NSColor, lineHeight: CGFloat? = nil, kern: CGFloat = 0) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        if let lineHeight {
            paragraph.minimumLineHeight = lineHeight
            paragraph.maximumLineHeight = lineHeight
        }
        return [.font: font, .foregroundColor: color, .paragraphStyle: paragraph, .kern: kern * font.pointSize]
    }

    private func upper(_ s: String, _ font: NSFont, _ color: NSColor, kern: CGFloat) -> NSAttributedString {
        NSAttributedString(string: s.uppercased(with: L10n.locale), attributes: attrs(font, color, kern: L10n.allowsTracking ? kern : 0))
    }

    private func splitLines(_ s: NSAttributedString, width: CGFloat) -> [NSAttributedString] {
        let storage = NSTextStorage(attributedString: s)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        var lines: [NSAttributedString] = []
        manager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: manager.numberOfGlyphs)) { _, _, _, glyphs, _ in
            let range = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            let line = NSMutableAttributedString(attributedString: s.attributedSubstring(from: range))
            while line.string.last?.isWhitespace == true { line.deleteCharacters(in: NSRange(location: line.length - 1, length: 1)) }
            lines.append(line)
        }
        return lines
    }

    /// Rasterises text at the screen's backing scale into a layer sized to fit.
    /// The bitmap bleeds past the layer's bounds so glyphs that rise above a tight
    /// line height (Å, Ä, Ö in the Schweiz theme) aren't clipped; layout still uses the bounds.
    private func textLayer(_ s: NSAttributedString, width: CGFloat, maxHeight: CGFloat = .greatestFiniteMagnitude) -> CALayer {
        let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        let measured = s.boundingRect(with: CGSize(width: width, height: maxHeight), options: options)
        let size = CGSize(width: ceil(min(measured.width, width)), height: ceil(min(measured.height, maxHeight)))
        let layer = CALayer()
        layer.frame = CGRect(origin: .zero, size: size)
        guard size.width > 0, size.height > 0 else { return layer }

        let fontSize = (s.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize ?? 12
        let bleed = ceil(fontSize * 0.4)
        let full = CGSize(width: size.width + 2 * bleed, height: size.height + 2 * bleed)
        let scale = self.scale
        guard let ctx = CGContext(data: nil, width: Int(full.width * scale), height: Int(full.height * scale),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return layer }
        ctx.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        s.draw(with: CGRect(origin: CGPoint(x: bleed, y: bleed), size: size), options: options)
        NSGraphicsContext.restoreGraphicsState()

        let image = CALayer()
        image.frame = CGRect(x: -bleed, y: -bleed, width: full.width, height: full.height)
        image.contentsScale = scale
        image.contents = ctx.makeImage()
        layer.addSublayer(image)
        return layer
    }

    /// A Lucide icon rasterised at the backing scale.
    private func iconLayer(_ name: String, size: CGFloat, color: NSColor) -> CALayer {
        let layer = CALayer()
        layer.frame = CGRect(x: 0, y: 0, width: size, height: size)
        layer.contentsScale = scale
        guard let image = Lucide.image(name, color: color) else { return layer }
        var rect = CGRect(x: 0, y: 0, width: size * scale, height: size * scale)
        layer.contents = image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        return layer
    }

    private func glowColors(_ color: NSColor, _ alpha: CGFloat) -> [CGColor] {
        [color.withAlphaComponent(alpha).cgColor, color.withAlphaComponent(0).cgColor]
    }

    private func clock(_ date: Date) -> String {
        date.formatted(.dateTime.locale(L10n.locale).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    private func ago(_ date: Date) -> String {
        if date == .distantPast { return "" }
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        if minutes < 2 { return L("Just now") }
        if minutes < 60 { return L("%d min ago", minutes) }
        let hours = Int((Double(minutes) / 60).rounded())
        if hours < 24 { return L("%d h ago", hours) }
        return date.formatted(.dateTime.locale(L10n.locale).day().month(.abbreviated))
    }
}
