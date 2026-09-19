import SwiftUI
import WebKit

/// The standard 604-page Madani Mushaf. Each page uses its own QCF font and
/// fixed 15-line layout, so words and ayah markers stay in their printed places.
struct QuranPagesView: View {
    @Environment(AppModel.self) private var model
    @Environment(QuranLibrary.self) private var library
    @State private var page: Int
    @State private var choosingPage = false
    /// The ayahs marked on the printed page, as positions in `pageVerses`.
    @State private var selection: ClosedRange<Int>?

    init(initialPage: Int) { _page = State(initialValue: min(604, max(1, initialPage))) }

    private var current: QuranPage? { library.pages.first { $0.id == page } }
    /// Every ayah printed on this page, in printed order, including one continued
    /// from the previous page. Matches the page's verified ayah runs.
    private var pageVerses: [PageVerse] { current?.selectableVerses ?? [] }
    private var selectedKeys: [String] {
        selection.map { range in range.compactMap { pageVerses.indices.contains($0) ? pageVerses[$0].key : nil } } ?? []
    }
    private var surahIDs: [Int] {
        current?.verses.map(\.surah).reduce(into: []) {
            if $0.last != $1 { $0.append($1) }
        } ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.state.activeSession != nil {
                FocusBanner().padding(.horizontal, 20).padding(.bottom, 12)
            }
            MushafPager(page: $page, selectedKeys: selectedKeys, onSelect: select)
                // UIPageViewController takes its paging direction from this; MushafPager maps it to Mushaf order.
                .environment(\.layoutDirection, .leftToRight)
            if let selection {
                PageSelectionBar(verses: pageVerses, selection: selection,
                                 change: { self.selection = $0 }, clear: { self.selection = nil })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Text("Tap an ayah on the page to copy it or listen to it.")
                    .font(.caption).foregroundStyle(QT.muted).frame(maxWidth: .infinity, minHeight: 34)
                    .accessibilityHint("Tap any word to select the ayah it belongs to")
            }
            HStack {
                Button { changePage(-1) } label: { Label("Previous", systemImage: "chevron.backward") }
                    .disabled(page == 1)
                Spacer()
                Button { choosingPage = true } label: {
                    Text(I18n.format("Page %lld of 604", page))
                        .font(.subheadline.weight(.semibold))
                        .contentTransition(.numericText(value: Double(page))).animation(.snappy, value: page)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(QT.sage, in: Capsule())
                }.buttonStyle(.pressable)
                Spacer()
                Button { changePage(1) } label: { Label("Next", systemImage: "chevron.forward") }
                    .disabled(page == 604)
            }
            // Mirrors the Mushaf pager in every language: the next page is on the left.
            .environment(\.layoutDirection, .rightToLeft)
            .font(.subheadline).padding(18).background(QT.surface)
            .sensoryFeedback(.selection, trigger: page)
        }
        .background(QT.paper)
        .sensoryFeedback(.selection, trigger: selection)
        .navigationTitle("Quran pages")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.setReadingQuran(true); saveProgress() }
        .onDisappear { model.setReadingQuran(false) }
        .onChange(of: page) { _, _ in saveProgress(); selection = nil }
        .animation(QT.spring, value: selection)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Go to page") { choosingPage = true }
                    ForEach(surahIDs, id: \.self) { surahID in
                        if let surah = library.surahs.first(where: { $0.id == surahID }) {
                            FavoriteSurahButton(surahID: surahID, title: surah.displayName)
                        }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $choosingPage) { PageChooser(page: $page).appPresentation() }
    }

    /// A tap on the page: select the ayah that word belongs to, or clear the marking.
    private func select(_ key: String?) {
        guard let key, let index = pageVerses.firstIndex(where: { $0.key == key }) else { selection = nil; return }
        selection = selection == index...index ? nil : index...index
    }

    private func changePage(_ offset: Int) { page = min(604, max(1, page + offset)) }
    private func saveProgress() {
        model.update { state in
            state.lastPage = page
            if let first = current?.verses.first {
                state.lastSurah = first.surah
                state.lastVerse = first.ayah
            }
        }
    }
}

/// Swipeable pages in Mushaf order: later pages sit to the left, so swiping toward the
/// right turns to the next page, whatever the app's language. The pager is always laid
/// out left to right, and its "before" (left) neighbor is the next page.
private struct MushafPager: UIViewControllerRepresentable {
    @Binding var page: Int
    /// Ayah keys marked on the current page, e.g. ["2:5"].
    var selectedKeys: [String]
    /// The ayah a tap landed on, or nil when the tap missed the text.
    var onSelect: (String?) -> Void

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pager = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal,
                                         options: [.interPageSpacing: 16])
        pager.dataSource = context.coordinator
        pager.delegate = context.coordinator
        pager.setViewControllers([context.coordinator.controller(for: page)], direction: .forward, animated: false)
        context.coordinator.prepareNeighbors(of: page, in: pager)
        context.coordinator.mark(page: page)
        return pager
    }

    func updateUIViewController(_ pager: UIPageViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.mark(page: page)
        guard let current = (pager.viewControllers?.first as? MushafPageController)?.page, current != page else { return }
        let target = coordinator.controller(for: page)
        let animated = abs(page - current) == 1
        let direction: UIPageViewController.NavigationDirection = page > current ? .reverse : .forward
        pager.setViewControllers([target], direction: direction, animated: animated) { [weak pager] finished in
            guard let pager else { return }
            // An animated change can leave UIPageViewController's neighbor cache stale; reset it.
            if animated, finished {
                DispatchQueue.main.async { pager.setViewControllers([target], direction: .forward, animated: false) }
            }
            coordinator.prepareNeighbors(of: target.page, in: pager)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: MushafPager
        private var controllers: [Int: MushafPageController] = [:]

        init(_ parent: MushafPager) { self.parent = parent }

        func controller(for page: Int) -> MushafPageController {
            if let controller = controllers[page] { return controller }
            let controller = MushafPageController(page: page)
            controller.onSelect = { [weak self] key in self?.parent.onSelect(key) }
            controllers[page] = controller
            return controller
        }

        /// Only the page on screen shows the marking; neighbours are cleared.
        func mark(page: Int) {
            for (number, controller) in controllers {
                controller.mark(number == page ? parent.selectedKeys : [])
            }
        }

        /// Renders the adjacent pages ahead of a swipe and releases distant ones.
        func prepareNeighbors(of page: Int, in pager: UIPageViewController) {
            controllers = controllers.filter { abs($0.key - page) <= 1 }
            for neighbor in [page - 1, page + 1] where (1...Mushaf.pageCount).contains(neighbor) {
                let controller = controller(for: neighbor)
                controller.view.frame = pager.view.bounds
                controller.view.layoutIfNeeded()
            }
        }

        func pageViewController(_ pager: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            neighbor(of: viewController, offset: 1)
        }

        func pageViewController(_ pager: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            neighbor(of: viewController, offset: -1)
        }

        private func neighbor(of viewController: UIViewController, offset: Int) -> UIViewController? {
            guard let page = (viewController as? MushafPageController)?.page,
                  (1...Mushaf.pageCount).contains(page + offset) else { return nil }
            return controller(for: page + offset)
        }

        func pageViewController(_ pager: UIPageViewController, didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            guard completed, let page = (pager.viewControllers?.first as? MushafPageController)?.page else { return }
            prepareNeighbors(of: page, in: pager)
            mark(page: page)
            if parent.page != page { parent.page = page }
        }
    }
}

/// Forwards the page's taps without letting WKWebView retain the controller.
private final class AyahTapRelay: NSObject, WKScriptMessageHandler {
    weak var controller: MushafPageController?
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        let key = message.body as? String
        self.controller?.onSelect?(key?.isEmpty == false ? key : nil)
    }
}

private final class MushafPageController: UIViewController, WKNavigationDelegate {
    let page: Int
    /// Called with the ayah key a tap landed on, or nil when it missed the text.
    var onSelect: ((String?) -> Void)?
    private weak var webView: WKWebView?
    private var pendingKeys: [String] = []
    private var loaded = false
    private let relay = AyahTapRelay()

    init(page: Int) {
        self.page = page
        super.init(nibName: nil, bundle: nil)
        relay.controller = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit { webView?.configuration.userContentController.removeScriptMessageHandler(forName: "ayah") }

    /// Marks these ayahs on the printed page, keeping the layout untouched.
    func mark(_ keys: [String]) {
        pendingKeys = keys
        guard loaded, let webView,
              let data = try? JSONSerialization.data(withJSONObject: keys),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("mark(\(json))")
    }

    override func loadView() {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(relay, name: "ayah")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        // Scrolling stays off, so the pager still owns horizontal swipes; taps reach the page.
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        // Fades in once rendered, instead of flashing an empty page.
        webView.alpha = 0
        webView.navigationDelegate = self
        self.webView = webView

        let container = UIView()
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            webView.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])
        webView.loadHTMLString(Self.html(for: page), baseURL: nil)
        view = container
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = true
        mark(pendingKeys)
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) { webView.alpha = 1 }
    }

    /// Wraps each printed line in per-ayah spans so a tapped word resolves to its ayah.
    /// The glyphs and their order are exactly the verified layout's.
    static func body(for mushafPage: Mushaf.Page) -> String {
        let segments = Mushaf.segments(mushafPage)
        return mushafPage.layout.lines.enumerated().map { index, line in
            let style = line.type == "surah-header" ? "surah" : line.type
            let content: String
            if line.type == "text", let parts = segments?[index] {
                content = parts.map { part in
                    guard let key = part.key else { return escaped(part.content) }
                    return "<span class=\"w\" data-k=\"\(escaped(key))\">\(escaped(part.content))</span>"
                }.joined()
            } else {
                content = escaped(line.content)
            }
            return "<div class=\"line \(style)\">\(content)</div>"
        }.joined()
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func html(for page: Int) -> String {
        guard let mushafPage = Mushaf.page(page) else { return errorHTML }

        let layout = mushafPage.layout
        let lineCount = layout.lines.count
        let pageClass = lineCount < 15 ? " special" : ""
        let lines = body(for: mushafPage)
        let basmalaFace = mushafPage.basmalaFont.map {
            "@font-face{font-family:qcf-basmala;src:url(data:font/woff2;base64,\($0.base64EncodedString())) format('woff2');font-display:block}"
        } ?? ""
        return """
        <!doctype html><html dir="rtl"><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no"><style>
        @font-face{font-family:qcf-\(page);src:url(data:font/woff2;base64,\(mushafPage.font.base64EncodedString())) format('woff2');font-display:block}
        \(basmalaFace)
        *{box-sizing:border-box}html,body{margin:0;width:100%;height:100%;overflow:hidden;background:transparent}
        body{padding:2.4% 3%;color:#17231d;font-family:qcf-\(page);display:flex;align-items:stretch;
             -webkit-user-select:none;user-select:none;-webkit-touch-callout:none;-webkit-tap-highlight-color:transparent}
        #page{width:100%;height:100%;display:grid;grid-template-rows:repeat(\(lineCount),1fr);align-items:center;border:1px solid rgba(90,110,82,.18);border-radius:12px;padding:2.2% 2.8%;background:#fffdf5;box-shadow:0 2px 14px rgba(30,45,35,.07)}
        #page.special{padding-top:19%;padding-bottom:19%}
        .line{min-height:0;text-align:center;white-space:nowrap;font-size:min(5.15vw,4.15vh);line-height:1;direction:rtl;font-variant-ligatures:normal}
        .surah{font-family:-apple-system,"Geeza Pro",sans-serif;font-size:min(4.3vw,3.4vh);font-weight:700;display:flex;align-items:center;justify-content:center;border-radius:999px;background:rgba(93,122,96,.12)}
        .basmala{font-family:qcf-basmala}
        /* Marking an ayah only tints it; the glyphs keep their printed places. */
        .w{border-radius:.18em;transition:background-color .18s ease}
        .w.sel{background:rgba(32,77,64,.16)}
        @media(prefers-color-scheme:dark){body{color:#f1ead8}#page{background:#17221d;border-color:rgba(220,210,180,.14);box-shadow:none}.w.sel{background:rgba(171,216,189,.24)}}
        </style></head><body><main id="page" class="\(pageClass)" aria-label="Quran page \(page)">\(lines)</main>
        <script>
        function fitMushafLines(){
          const page=document.getElementById('page');
          const lines=[...page.querySelectorAll('.text')];
          if(!lines.length)return;
          lines.forEach(line=>line.style.fontSize='');
          const available=page.clientWidth-20;
          const base=parseFloat(getComputedStyle(lines[0]).fontSize);
          let ratio=1;
          lines.forEach(line=>{if(line.scrollWidth>available)ratio=Math.min(ratio,available/line.scrollWidth)});
          const fitted=Math.max(base*ratio*.985,10);
          lines.forEach(line=>line.style.fontSize=fitted+'px');
          page.querySelectorAll('.basmala').forEach(line=>{
            line.style.fontSize=fitted+'px';
            if(line.scrollWidth>available)line.style.fontSize=(fitted*available/line.scrollWidth*.985)+'px';
          });
        }
        document.fonts.ready.then(fitMushafLines);
        new ResizeObserver(fitMushafLines).observe(document.getElementById('page'));
        function mark(keys){
          document.querySelectorAll('.w').forEach(w=>w.classList.toggle('sel',keys.indexOf(w.dataset.k)>=0));
        }
        // A tap picks the word under the finger, or the nearest word on that line,
        // so the gaps between words do not feel dead.
        function wordAt(event){
          const hit=event.target.closest?event.target.closest('.w'):null;
          if(hit)return hit;
          const line=event.target.closest?event.target.closest('.line.text'):null;
          if(!line)return null;
          let best=null,distance=1e9;
          line.querySelectorAll('.w').forEach(word=>{
            const box=word.getBoundingClientRect();
            const gap=Math.max(box.left-event.clientX,event.clientX-box.right,0);
            if(gap<distance){distance=gap;best=word}
          });
          return distance<44?best:null;
        }
        document.addEventListener('click',function(event){
          const word=wordAt(event);
          window.webkit.messageHandlers.ayah.postMessage(word?word.dataset.k:'');
        });
        </script></body></html>
        """
    }

    private static let errorHTML = "<html><body style='background:transparent;color:#777;text-align:center;padding-top:40%'>This Quran page could not be loaded.</body></html>"
}

/// Copy or listen to the ayahs marked on the printed page, and grow or shrink
/// the marking one ayah at a time.
private struct PageSelectionBar: View {
    @Environment(AppModel.self) private var model
    @Environment(QuranLibrary.self) private var library
    let verses: [PageVerse]
    let selection: ClosedRange<Int>
    let change: (ClosedRange<Int>) -> Void
    let clear: () -> Void
    @State private var copied = false

    private var selected: [PageVerse] { selection.compactMap { verses.indices.contains($0) ? verses[$0] : nil } }
    private var label: String {
        guard let first = selected.first, let last = selected.last else { return "" }
        let name = library.surahs.first { $0.id == first.surah }?.displayName ?? ""
        let reference = first.surah == last.surah && first.ayah == last.ayah
            ? "\(I18n.number(first.surah)):\(I18n.number(first.ayah))"
            : "\(I18n.number(first.surah)):\(I18n.number(first.ayah))–\(I18n.number(last.surah)):\(I18n.number(last.ayah))"
        return "\(name) · \(reference)"
    }
    /// The canonical Unicode text of the marked ayahs, never the page's glyph codes.
    private var text: String? {
        let lines = selected.compactMap { reference -> String? in
            library.surahs.first { $0.id == reference.surah }?.verses.first { $0.id == reference.ayah }?.text
        }
        guard lines.count == selected.count, let first = selected.first, let last = selected.last else { return nil }
        let reference = first.surah == last.surah && first.ayah == last.ayah
            ? "[\(first.surah):\(first.ayah)]" : "[\(first.surah):\(first.ayah)-\(last.surah):\(last.ayah)]"
        return lines.joined(separator: "\n") + "\n" + reference
    }
    /// Listening plays a range only within one surah; the reciter is the one in Settings.
    private var playable: (surah: Int, first: Int, last: Int)? {
        guard let first = selected.first, let last = selected.last, first.surah == last.surah else { return nil }
        return (first.surah, first.ayah, last.ayah)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(QT.green).lineLimit(1)
                Spacer(minLength: 0)
                Button(action: clear) { Image(systemName: "xmark.circle.fill") }
                    .foregroundStyle(QT.muted).accessibilityLabel("Clear selection").frame(minWidth: 44, minHeight: 44)
            }
            HStack(spacing: 10) {
                Button {
                    if let text { UIPasteboard.general.string = text; copied = true }
                } label: {
                    Label(LocalizedStringKey(copied ? "Copied" : "Copy"), systemImage: copied ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.disabled(text == nil).sensoryFeedback(.success, trigger: copied)
                    .task(id: copied) { if copied { try? await Task.sleep(for: .seconds(2)); copied = false } }
                Button {
                    if let playable { model.recitation.play(surah: playable.surah, from: playable.first, through: playable.last) }
                } label: {
                    Label("Listen", systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: 44)
                }.disabled(playable == nil)
                Button { change(selection.lowerBound...(selection.upperBound - 1)) } label: {
                    Image(systemName: "minus").frame(minWidth: 44, minHeight: 44)
                }.disabled(selection.count < 2).accessibilityLabel("Select one ayah fewer")
                Button { change(selection.lowerBound...(selection.upperBound + 1)) } label: {
                    Image(systemName: "plus").frame(minWidth: 44, minHeight: 44)
                }.disabled(selection.upperBound + 1 >= verses.count).accessibilityLabel("Select the next ayah too")
            }.font(.subheadline.weight(.medium)).buttonStyle(.bordered).tint(QT.green)
        }
        .padding(.horizontal, 18).padding(.vertical, 12).background(QT.surface)
        .accessibilityElement(children: .contain)
    }
}

private struct PageChooser: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(QuranLibrary.self) private var library
    @Binding var page: Int
    @State private var destination = 1
    @State private var selectedSurah = 1

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Choose a Quran page").font(QT.serif(28)).foregroundStyle(QT.ink)
                Picker("Surah", selection: $selectedSurah) {
                    ForEach(library.surahs) { surah in
                        Text("\(surah.id). \(surah.displayName)").tag(surah.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(QT.surface, in: RoundedRectangle(cornerRadius: 14))
                .onChange(of: selectedSurah) { _, surahID in
                    if let firstPage = library.pages.first(where: { $0.verses.contains { $0.surah == surahID } })?.id {
                        destination = firstPage
                    }
                }
                Picker("Page", selection: $destination) {
                    ForEach(1...604, id: \.self) { Text(I18n.number($0)).tag($0) }
                }.pickerStyle(.wheel)
                PrimaryButton(title: "Open page", symbol: "book") { page = destination; dismiss() }
            }
            .padding(28).frame(maxHeight: .infinity).background(QT.paper)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .onAppear {
            destination = page
            selectedSurah = library.pages.first(where: { $0.id == page })?.verses.first?.surah ?? 1
        }
        .presentationDetents([.medium, .large])
    }
}
