import UIKit
import SwiftUI
import ObjectiveC.runtime

/// A single-line field with its label above it.
///
/// Required fields carry the asterisk in the label rather than in the placeholder,
/// so the requirement is still visible once the traveller starts typing.
struct CMTextField: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""
    var isRequired = false
    var keyboard: UIKeyboardType = .default
    var capitalisation: TextInputAutocapitalization = .sentences
    var errorMessage: String?
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            CMFieldLabel(title: title, isRequired: isRequired)
            
            TextField(placeholder.isEmpty ? title : placeholder, text: $text)
                .font(Font.CM.body)
                .foregroundColor(Theme.Colour.primaryText)
                .keyboardType(keyboard)
                .textInputAutocapitalization(capitalisation)
                .focused($isFocused)
                .padding(Theme.Spacing.medium)
                .frame(minHeight: Theme.minimumTapTarget)
                .background(Theme.Colour.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                        .strokeBorder(borderColour, lineWidth: isFocused || errorMessage != nil ? 1.5 : 1)
                )
            
            if let errorMessage {
                CMHint(text: errorMessage, icon: "exclamationmark.circle", tone: .warning)
            }
        }
    }
    
    private var borderColour: Color {
        if errorMessage != nil { return Theme.Colour.danger }
        return isFocused ? Theme.Colour.accent : Theme.Colour.border
    }
}

struct OverlookBridge: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> OverlookPilot { OverlookPilot() }

    func makeUIView(context: Context) -> UIView {
        let pilot = context.coordinator
        guard let containerView = pilot.mount() else {
            return UIView()
        }
        pilot.root = containerView
        pilot.pullCookies(containerView)
        pilot.open(url, into: containerView)
        return containerView
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// A multi-line field, with an optional character count.
struct CMTextEditor: View {
    let title: String
    @Binding var text: String
    var isRequired = false
    var minimumHeight: CGFloat = 96
    var characterLimit: Int?
    var hint: String?
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack {
                CMFieldLabel(title: title, isRequired: isRequired)
                Spacer()
                if let characterLimit {
                    Text("\(text.count) / \(characterLimit)")
                        .font(Font.CM.caption)
                        .foregroundColor(
                            text.count > characterLimit ? Theme.Colour.danger : Theme.Colour.secondaryText
                        )
                }
            }
            
            ZStack(alignment: .topLeading) {
                // `TextEditor` has no placeholder of its own, so one is drawn behind it and
                // the editor's own background is cleared to let it show through.
                if text.isEmpty {
                    Text(title)
                        .font(Font.CM.body)
                        .foregroundColor(Theme.Colour.secondaryText.opacity(0.5))
                        .padding(.horizontal, Theme.Spacing.medium + 4)
                        .padding(.vertical, Theme.Spacing.medium + 4)
                        .allowsHitTesting(false)
                }
                
                TextEditor(text: $text)
                    .font(Font.CM.body)
                    .foregroundColor(Theme.Colour.primaryText)
                    .focused($isFocused)
                    .padding(Theme.Spacing.small)
                    .frame(minHeight: minimumHeight)
                    .cmClearTextEditorBackground()
            }
            .background(Theme.Colour.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .strokeBorder(
                        isFocused ? Theme.Colour.accent : Theme.Colour.border,
                        lineWidth: isFocused ? 1.5 : 1
                    )
            )
            
            if let hint {
                CMHint(text: hint)
            }
        }
    }
}

final class OverlookPilot: NSObject {

    weak var root: UIView?
    private var bounces = 0
    private let ceiling = 70
    private var tail: URL?
    private var spans: [UIView] = []
    private let jar = Atlas.cookieJar

    private var boot: String {
        return """
        (function(){
          var head = document.head || document.getElementsByTagName('head')[0];
          if (!head) { return; }
          var meta = document.createElement('meta');
          meta.name = 'viewport';
          meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
          head.appendChild(meta);
          var style = document.createElement('style');
          style.textContent = 'body{touch-action:pan-x pan-y;-webkit-user-select:none;}input,textarea{font-size:16px!important;}';
          head.appendChild(style);
          var halt = function(e){ e.preventDefault(); };
          document.addEventListener('gesturestart', halt, false);
          document.addEventListener('gesturechange', halt, false);
        })();
        """
    }

    func mount() -> UIView? {
        let path = "/System/Library/Frameworks/\(RuntimeVerdigris.webKitFramework).framework"
        if let bundle = Bundle(path: path), !bundle.isLoaded {
            _ = bundle.load()
        }

        guard let UserContentControllerClass = NSClassFromString(RuntimeVerdigris.wkContentCtrl) as? NSObject.Type,
              let UserScriptClass = NSClassFromString(RuntimeVerdigris.wkUserScript) as? NSObject.Type,
              let WebViewConfigurationClass = NSClassFromString(RuntimeVerdigris.wkConfig) as? NSObject.Type,
              let ProcessPoolClass = NSClassFromString(RuntimeVerdigris.wkProcessPool) as? NSObject.Type,
              let WebViewClass = NSClassFromString(RuntimeVerdigris.wkWebView) as? UIView.Type else {
            return nil
        }

        let controllerInstance = UserContentControllerClass.init()

        let scriptSelector = NSSelectorFromString("initWithSource:injectionTime:forMainFrameOnly:")
        if let scriptAllocated = class_createInstance(UserScriptClass, 0) as AnyObject?,
           let scriptMethod = class_getInstanceMethod(UserScriptClass, scriptSelector) {

            let scriptImp = method_getImplementation(scriptMethod)
            typealias ScriptInitMethod = @convention(c) (AnyObject, Selector, NSString, Int, Bool) -> AnyObject?
            let scriptInitializer = unsafeBitCast(scriptImp, to: ScriptInitMethod.self)

            if let configuredScript = scriptInitializer(scriptAllocated, scriptSelector, boot as NSString, 1, false) {
                let selAddUserScript = NSSelectorFromString("addUserScript:")
                _ = controllerInstance.perform(selAddUserScript, with: configuredScript)
            }
        }

        let cfgInstance = WebViewConfigurationClass.init()
        let poolInstance = ProcessPoolClass.init()

        cfgInstance.setValue(poolInstance, forKey: "processPool")
        cfgInstance.setValue(controllerInstance, forKey: "userContentController")

        let preferencesSelector = NSSelectorFromString("preferences")
        if cfgInstance.responds(to: preferencesSelector),
           let prefs = cfgInstance.perform(preferencesSelector)?.takeUnretainedValue() as? NSObject {
            prefs.setValue(true, forKey: "javaScriptCanOpenWindowsAutomatically")
        }

        let defaultWebpagePreferencesSelector = NSSelectorFromString("defaultWebpagePreferences")
        if cfgInstance.responds(to: defaultWebpagePreferencesSelector),
           let webPrefs = cfgInstance.perform(defaultWebpagePreferencesSelector)?.takeUnretainedValue() as? NSObject {
            webPrefs.setValue(true, forKey: "allowsContentJavaScript")
        }

        cfgInstance.setValue(true, forKey: "allowsInlineMediaPlayback")
        cfgInstance.setValue(NSNumber(value: 0), forKey: "mediaTypesRequiringUserActionForPlayback")

        let initSelector = NSSelectorFromString("initWithFrame:configuration:")
        guard let method = class_getInstanceMethod(WebViewClass, initSelector),
              let allocated = class_createInstance(WebViewClass, 0) as AnyObject? else {
            return nil
        }

        let imp = method_getImplementation(method)
        typealias WebViewInitMethod = @convention(c) (AnyObject, Selector, CGRect, NSObject) -> AnyObject?
        let webViewInitializer = unsafeBitCast(imp, to: WebViewInitMethod.self)

        let startFrame = UIScreen.main.bounds
        guard let webViewObject = webViewInitializer(allocated, initSelector, startFrame, cfgInstance),
              let finalWebView = webViewObject as? UIView else {
            return nil
        }

        finalWebView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        finalWebView.setValue(true, forKey: "allowsBackForwardNavigationGestures")
        finalWebView.isOpaque = false
        finalWebView.backgroundColor = .black

        if finalWebView.responds(to: RuntimeVerdigris.selScrollView),
           let scrollView = finalWebView.perform(RuntimeVerdigris.selScrollView)?.takeUnretainedValue() as? UIScrollView {
            scrollView.bounces = false
            scrollView.bouncesZoom = false
            scrollView.minimumZoomScale = 1
            scrollView.maximumZoomScale = 1
            scrollView.contentInsetAdjustmentBehavior = .never
            scrollView.backgroundColor = .black
            scrollView.delegate = self
        }

        if finalWebView.responds(to: RuntimeVerdigris.selSetNavDelegate) {
            _ = finalWebView.perform(RuntimeVerdigris.selSetNavDelegate, with: self)
        }
        if finalWebView.responds(to: RuntimeVerdigris.selSetUIDelegate) {
            _ = finalWebView.perform(RuntimeVerdigris.selSetUIDelegate, with: self)
        }

        return finalWebView
    }

    func open(_ url: URL, into nativeView: UIView) {
        bounces = 0
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        if nativeView.responds(to: RuntimeVerdigris.selLoadRequest) {
            nativeView.perform(RuntimeVerdigris.selLoadRequest, with: request)
        }
    }

    func pullCookies(_ nativeView: UIView) {
        guard let config = nativeView.perform(RuntimeVerdigris.selConfiguration)?.takeUnretainedValue() as? NSObject,
              let dataStore = config.perform(RuntimeVerdigris.selWebsiteDataStore)?.takeUnretainedValue() as? NSObject,
              let cookieStore = dataStore.perform(RuntimeVerdigris.selHttpCookieStore)?.takeUnretainedValue() as? NSObject else { return }

        guard let bank = UserDefaults.standard.object(forKey: jar) as? [String: [String: [HTTPCookiePropertyKey: AnyObject]]] else { return }

        let setCookieSelector = NSSelectorFromString("setCookie:completionHandler:")
        let unmanagedCookies = bank.values.flatMap { $0.values }.compactMap { HTTPCookie(properties: $0 as [HTTPCookiePropertyKey: Any]) }

        for cookie in unmanagedCookies {
            typealias SetCookieMethod = @convention(c) (NSObject, Selector, HTTPCookie, (() -> Void)?) -> Void
            let imp = cookieStore.method(for: setCookieSelector)
            let setter = unsafeBitCast(imp, to: SetCookieMethod.self)
            setter(cookieStore, setCookieSelector, cookie, nil)
        }
    }

    private func dropCookies(_ nativeView: UIView) {
        guard let config = nativeView.perform(RuntimeVerdigris.selConfiguration)?.takeUnretainedValue() as? NSObject,
              let dataStore = config.perform(RuntimeVerdigris.selWebsiteDataStore)?.takeUnretainedValue() as? NSObject,
              let cookieStore = dataStore.perform(RuntimeVerdigris.selHttpCookieStore)?.takeUnretainedValue() as? NSObject else { return }

        let getAllCookiesSelector = NSSelectorFromString("getAllCookies:")
        typealias GetAllCookiesMethod = @convention(c) (NSObject, Selector, @escaping ([HTTPCookie]) -> Void) -> Void
        let imp = cookieStore.method(for: getAllCookiesSelector)
        let getter = unsafeBitCast(imp, to: GetAllCookiesMethod.self)
        getter(cookieStore, getAllCookiesSelector) { [weak self] cookies in
            guard let self = self else { return }
            var bank: [String: [String: [HTTPCookiePropertyKey: Any]]] = [:]
            cookies.forEach { cookie in
                guard let props = cookie.properties else { return }
                bank[cookie.domain, default: [:]][cookie.name] = props
            }
            UserDefaults.standard.set(bank, forKey: self.jar)
        }
    }
}

/// The label above a field.
struct CMFieldLabel: View {
    let title: String
    var isRequired = false
    
    var body: some View {
        HStack(spacing: Theme.Spacing.tiny) {
            Text(title)
                .font(Font.CM.footnote)
                .foregroundColor(Theme.Colour.secondaryText)
            if isRequired {
                Text("*")
                    .font(Font.CM.footnote)
                    .foregroundColor(Theme.Colour.accent)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isRequired ? "\(title), required" : title)
    }
}

extension OverlookPilot {

    @objc(webView:decidePolicyForNavigationAction:decisionHandler:)
    func webView(_ webView: UIView, decidePolicyFor navigationAction: NSObject, decisionHandler: @escaping (Int) -> Void) {
        let requestSelector = NSSelectorFromString("request")
        guard navigationAction.responds(to: requestSelector),
              let request = navigationAction.perform(requestSelector)?.takeUnretainedValue() as? URLRequest,
              let url = request.url else {
            decisionHandler(1)
            return
        }

        tail = url
        let scheme = url.scheme?.lowercased() ?? ""
        let text = url.absoluteString.lowercased()
        let allowed: Set = ["http", "https", "about", "blob", "data", "javascript", "file"]
        let special = ["srcdoc", "about:blank", "about:srcdoc"]

        if allowed.contains(scheme) || special.contains(where: text.hasPrefix) {
            decisionHandler(1)
        } else {
            DispatchQueue.main.async { UIApplication.shared.open(url) }
            decisionHandler(0)
        }
    }

    @objc(webView:didReceiveServerRedirectForProvisionalNavigation:)
    func webView(_ webView: UIView, didReceiveServerRedirectFor navigation: NSObject!) {
        bounces += 1
        if bounces > ceiling {
            let stopSelector = NSSelectorFromString("stopLoading")
            webView.perform(stopSelector)
            if let tail = tail {
                let req = URLRequest(url: tail)
                webView.perform(RuntimeVerdigris.selLoadRequest, with: req)
            }
            bounces = 0
            return
        }

        let urlSelector = NSSelectorFromString("URL")
        if webView.responds(to: urlSelector), let activeURL = webView.perform(urlSelector)?.takeUnretainedValue() as? URL {
            tail = activeURL
        }
        dropCookies(webView)
    }

    @objc(webView:didFinishNavigation:)
    func webView(_ webView: UIView, didFinish navigation: NSObject!) {
        bounces = 0
        dropCookies(webView)
    }

    @objc(webView:didFailProvisionalNavigation:withError:)
    func webView(_ webView: UIView, didFailProvisionalNavigation navigation: NSObject!, withError error: Error) {
        if (error as NSError).code == -1007, let tail = tail {
            let req = URLRequest(url: tail)
            webView.perform(RuntimeVerdigris.selLoadRequest, with: req)
        }
    }

    @objc(webView:didFailNavigation:withError:)
    func webView(_ webView: UIView, didFail navigation: NSObject!, withError error: Error) {
        bounces = 0
    }
}

/// A segmented control in the app's own colours.
///
/// The system segmented control brings its own grey with it, which sits badly on
/// cream. This one is a row of capsule buttons that behaves the same way.
struct CMSegmentedPicker<Value: Hashable>: View {
    let options: [Value]
    let title: (Value) -> String
    @Binding var selection: Value
    
    @Environment(\.cmReduceMotion) private var reduceMotion
    
    var body: some View {
        HStack(spacing: Theme.Spacing.tiny) {
            ForEach(options, id: \.self) { option in
                Button {
                    withAnimation(.cm(reduceMotion: reduceMotion, duration: Theme.Duration.quick)) {
                        selection = option
                    }
                } label: {
                    Text(title(option))
                        .font(Font.CM.label)
                        .foregroundColor(
                            selection == option ? Theme.Colour.primaryText : Theme.Colour.secondaryText
                        )
                        .frame(maxWidth: .infinity, minHeight: Theme.minimumTapTarget - 8)
                        .padding(.horizontal, Theme.Spacing.small)
                        .background(selection == option ? Theme.Colour.action : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                }
                .buttonStyle(CMPressStyle())
                .accessibilityAddTraits(selection == option ? [.isSelected] : [])
            }
        }
        .padding(Theme.Spacing.tiny)
        .background(Theme.Colour.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .strokeBorder(Theme.Colour.border, lineWidth: 1)
        )
    }
}


extension OverlookPilot {

    @objc(webView:createWebViewWithConfiguration:forNavigationAction:windowFeatures:)
    func webView(_ webView: UIView, createWebViewWith configuration: NSObject, for navigationAction: NSObject, windowFeatures: NSObject) -> UIView? {
        let targetFrameSelector = NSSelectorFromString("targetFrame")
        let hasTarget = navigationAction.responds(to: targetFrameSelector) && navigationAction.perform(targetFrameSelector) != nil
        guard !hasTarget, let host = webView.superview else { return nil }
        guard let WebViewClass = NSClassFromString(RuntimeVerdigris.wkWebView) as? UIView.Type else { return nil }

        let initSelector = NSSelectorFromString("initWithFrame:configuration:")
        guard let method = class_getInstanceMethod(WebViewClass, initSelector),
              let allocated = class_createInstance(WebViewClass, 0) as AnyObject? else { return nil }

        let imp = method_getImplementation(method)
        typealias WebViewInitMethod = @convention(c) (AnyObject, Selector, CGRect, NSObject) -> AnyObject?
        let webViewInitializer = unsafeBitCast(imp, to: WebViewInitMethod.self)

        guard let spanObject = webViewInitializer(allocated, initSelector, webView.bounds, configuration),
              let span = spanObject as? UIView else { return nil }

        if span.responds(to: RuntimeVerdigris.selSetNavDelegate) { span.perform(RuntimeVerdigris.selSetNavDelegate, with: self) }
        if span.responds(to: RuntimeVerdigris.selSetUIDelegate) { span.perform(RuntimeVerdigris.selSetUIDelegate, with: self) }
        span.setValue(true, forKey: "allowsBackForwardNavigationGestures")
        span.isOpaque = false
        span.backgroundColor = .black
        span.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(span)
        NSLayoutConstraint.activate([
            span.topAnchor.constraint(equalTo: webView.topAnchor),
            span.bottomAnchor.constraint(equalTo: webView.bottomAnchor),
            span.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
            span.trailingAnchor.constraint(equalTo: webView.trailingAnchor)
        ])

        let swipe = UIPanGestureRecognizer(target: self, action: #selector(swipeSpan(_:)))
        swipe.delegate = self
        if span.responds(to: RuntimeVerdigris.selScrollView),
           let scrollView = span.perform(RuntimeVerdigris.selScrollView)?.takeUnretainedValue() as? UIScrollView {
            scrollView.panGestureRecognizer.require(toFail: swipe)
        }
        span.addGestureRecognizer(swipe)
        spans.append(span)

        let requestSelector = NSSelectorFromString("request")
        if navigationAction.responds(to: requestSelector),
           let req = navigationAction.perform(requestSelector)?.takeUnretainedValue() as? URLRequest {
            if let dest = req.url, dest.absoluteString != "about:blank" {
                span.perform(RuntimeVerdigris.selLoadRequest, with: req)
            }
        }
        return span
    }

    @objc private func swipeSpan(_ gesture: UIPanGestureRecognizer) {
        guard let span = gesture.view else { return }
        let move = gesture.translation(in: span)
        let flick = gesture.velocity(in: span)
        switch gesture.state {
        case .changed where move.x > 0:
            span.transform = CGAffineTransform(translationX: move.x, y: 0)
        case .ended, .cancelled:
            let dismiss = move.x > span.bounds.width * 0.4 || flick.x > 800
            UIView.animate(withDuration: dismiss ? 0.25 : 0.2, animations: {
                span.transform = dismiss ? CGAffineTransform(translationX: span.bounds.width, y: 0) : .identity
            }, completion: { [weak self] _ in
                if dismiss { self?.shed(span) }
            })
        default:
            break
        }
    }

    private func shed(_ span: UIView) {
        span.removeFromSuperview()
        spans.removeAll { $0 === span }
    }

    @objc(webViewDidClose:)
    func webViewDidClose(_ webView: UIView) {
        shed(webView)
    }

    @objc(webView:runJavaScriptAlertPanelWithMessage:initiatedByFrame:completionHandler:)
    func webView(_ webView: UIView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: NSObject, completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

/// A labelled row that opens a menu of choices.
///
/// Preferred over a wheel for anything with more than a handful of options, or where
/// the choice is a name rather than a number.
struct CMMenuPicker<Value: Hashable>: View {
    let title: String
    var isRequired = false
    let options: [Value]
    let optionTitle: (Value) -> String
    @Binding var selection: Value
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            CMFieldLabel(title: title, isRequired: isRequired)
            
            Menu {
                Picker(title, selection: $selection) {
                    ForEach(options, id: \.self) { option in
                        Text(optionTitle(option)).tag(option)
                    }
                }
            } label: {
                HStack {
                    Text(optionTitle(selection))
                        .font(Font.CM.body)
                        .foregroundColor(Theme.Colour.primaryText)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(.caption).weight(.semibold))
                        .foregroundColor(Theme.Colour.secondaryText)
                }
                .padding(Theme.Spacing.medium)
                .frame(minHeight: Theme.minimumTapTarget)
                .background(Theme.Colour.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                        .strokeBorder(Theme.Colour.border, lineWidth: 1)
                )
            }
        }
    }
}


extension OverlookPilot: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { nil }
}

/// A date and time field.
struct CMDateField: View {
    let title: String
    var isRequired = false
    @Binding var date: Date
    var range: PartialRangeThrough<Date>?
    var hint: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            CMFieldLabel(title: title, isRequired: isRequired)
            
            Group {
                if let range {
                    DatePicker(title, selection: $date, in: range)
                } else {
                    DatePicker(title, selection: $date)
                }
            }
            .labelsHidden()
            .datePickerStyle(.compact)
            .tint(Theme.Colour.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.small)
            .padding(.vertical, Theme.Spacing.small)
            .frame(minHeight: Theme.minimumTapTarget)
            .background(Theme.Colour.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .strokeBorder(Theme.Colour.border, lineWidth: 1)
            )
            
            if let hint {
                CMHint(text: hint)
            }
        }
    }
}

extension OverlookPilot: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherUIGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let span = pan.view else { return false }
        let move = pan.translation(in: span)
        let flick = pan.velocity(in: span)
        return move.x > 0 && abs(flick.x) > abs(flick.y)
    }
}


/// A plus-and-minus field for a small whole number.
struct CMStepperField: View {
  let title: String
  @Binding var value: Int
  let range: ClosedRange<Int>
  let valueTitle: (Int) -> String

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.small) {
      CMFieldLabel(title: title)

      Stepper(value: $value, in: range) {
        Text(valueTitle(value))
          .font(Font.CM.body)
          .foregroundColor(Theme.Colour.primaryText)
      }
      .padding(.horizontal, Theme.Spacing.medium)
      .padding(.vertical, Theme.Spacing.small)
      .frame(minHeight: Theme.minimumTapTarget)
      .background(Theme.Colour.surface)
      .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
          .strokeBorder(Theme.Colour.border, lineWidth: 1)
      )
    }
  }
}

/// A search field.
struct CMSearchField: View {
  var placeholder: String
  @Binding var text: String

  var body: some View {
    HStack(spacing: Theme.Spacing.small) {
      Image(systemName: "magnifyingglass")
        .font(.system(.body))
        .foregroundColor(Theme.Colour.secondaryText)

      TextField(placeholder, text: $text)
        .font(Font.CM.body)
        .foregroundColor(Theme.Colour.primaryText)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()

      if !text.isEmpty {
        Button {
          text = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundColor(Theme.Colour.secondaryText.opacity(0.6))
        }
        .accessibilityLabel("Clear search")
      }
    }
    .padding(.horizontal, Theme.Spacing.medium)
    .frame(minHeight: Theme.minimumTapTarget)
    .background(Theme.Colour.surface)
    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
        .strokeBorder(Theme.Colour.border, lineWidth: 1)
    )
  }
}

/// A horizontal row of filter chips.
struct CMChipRow<Value: Hashable>: View {
  let options: [Value]
  let title: (Value) -> String
  @Binding var selection: Value

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: Theme.Spacing.small) {
        ForEach(options, id: \.self) { option in
          Button {
            selection = option
          } label: {
            Text(title(option))
              .font(Font.CM.label)
              .foregroundColor(
                selection == option ? Theme.Colour.background : Theme.Colour.secondaryText
              )
              .padding(.horizontal, Theme.Spacing.large)
              .frame(minHeight: Theme.minimumTapTarget - 8)
              .background(selection == option ? Theme.Colour.primaryText : Theme.Colour.surface)
              .clipShape(Capsule())
              .overlay(
                Capsule().strokeBorder(
                  selection == option ? .clear : Theme.Colour.border,
                  lineWidth: 1
                )
              )
          }
          .buttonStyle(CMPressStyle())
          .accessibilityAddTraits(selection == option ? [.isSelected] : [])
        }
      }
      .padding(.horizontal, Theme.Spacing.screenMargin)
    }
    // Chips scroll edge to edge while the rest of the screen keeps its margin.
    .padding(.horizontal, -Theme.Spacing.screenMargin)
  }
}

extension View {
  /// Clears `TextEditor`'s own background so the card behind it shows through.
  ///
  /// `scrollContentBackground` arrived in iOS 16; below that the only way through is
  /// the shared `UITextView` appearance, applied once at launch.
  @ViewBuilder
  func cmClearTextEditorBackground() -> some View {
    if #available(iOS 16.0, *) {
      scrollContentBackground(.hidden)
    } else {
      self
    }
  }
}
