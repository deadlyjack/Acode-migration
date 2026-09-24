import XCTest
import WebKit
@testable import runner

@MainActor
final class SystemUITests: BridgeTestCase {
    func testInputModesPreserveFieldsAndRestorePromptDefaults() async throws {
        let webView = try await editorWebView()
        let result = try await webView.callAsyncJavaScript("""
            const call=(service,action,args)=>new Promise((resolve,reject)=>Bridge.exec(resolve,reject,service,action,args));
            const field=document.createElement('input');field.type='email';field.autocomplete='email';field.setAttribute('autocorrect','on');
            document.body.append(field);
            try {
                await call('System','set-input-type',['NO_SUGGESTIONS_AGGRESSIVE']);
                if(field.getAttribute('autocorrect')!=='off'||field.getAttribute('writingsuggestions')!=='false') throw Error('Suggestions not disabled');
                if(field.type!=='email'||field.autocomplete!=='email') throw Error('Input semantics changed');
                await call('System','set-input-type',['NORMAL']);
                if(field.getAttribute('autocorrect')!=='on'||field.hasAttribute('writingsuggestions')) throw Error('Prompt defaults not restored');
                await call('Native','setKeyboardSuggestionsEnabled',[false]);
                if(field.getAttribute('autocorrect')!=='off') throw Error('Native compatibility API ignored');
                for(const [type,options,capitalize] of [['filename',{},'off'],['text',{},'on'],['filename',{capitalize:true},'on']]) {
                    const result=acode.require('prompt')('Input fixture','ios-file.txt',type,options);
                    const dialog=document.querySelector('.prompt:not(.hide)'), input=dialog.querySelector('input');
                    try {
                        await call('System','set-input-type',['NORMAL']);
                        if(input.getAttribute('autocapitalize')!==capitalize)throw Error('Prompt capitalization changed: '+type);
                        if(type==='filename'&&(input.getAttribute('autocorrect')!=='off'||input.getAttribute('spellcheck')!=='false'||input.getAttribute('writingsuggestions')!=='false'))throw Error('Filename correction remained enabled');
                        if(type==='text'&&(input.hasAttribute('autocorrect')||input.hasAttribute('writingsuggestions')))throw Error('Text prompt defaults changed');
                    } finally {dialog.querySelector('button[type="button"]').click();await result;}
                }
                return true;
            } finally {field.remove();await call('System','set-input-type',[acode.require('settings').value.keyboardMode]);}
            """, arguments: [:], in: nil, contentWorld: .page) as? Bool
        XCTAssertEqual(result, true)
    }

    func testNativeMenuPolicyPreservesDOMSelectionAndStatusBarCanBeHidden() async throws {
        let app = try await appWebView()
        let webView = try XCTUnwrap(app as? AppWebView)
        let scene = try XCTUnwrap(webView.window?.windowScene)
        let result = try await webView.callAsyncJavaScript("""
            const field=document.createElement('div');field.contentEditable='true';field.textContent='selected code';document.body.append(field);
            const range=document.createRange();range.selectNodeContents(field);
            const selection=getSelection();selection.removeAllRanges();selection.addRange(range);
            await new Promise((resolve,reject)=>system.setNativeContextMenuDisabled(true,resolve,reject));
            const retained=selection.toString()==='selected code'&&field.isContentEditable;
            field.remove();selection.removeAllRanges();return retained;
            """, arguments: [:], in: nil, contentWorld: .page) as? Bool
        XCTAssertEqual(result, true)
        XCTAssertTrue(webView.nativeContextMenuDisabled)
        defer { webView.nativeContextMenuDisabled = false }
        try await call(webView, service: "SystemBarPlugin", action: "setStatusBarVisible", args: [false])
        try await Task.sleep(for: .milliseconds(300))
        let hidden = scene.statusBarManager?.isStatusBarHidden
        try await call(webView, service: "SystemBarPlugin", action: "setStatusBarVisible", args: [true])
        XCTAssertEqual(hidden, true)
        try await call(webView, action: "set-native-context-menu-disabled", args: ["false"])
        XCTAssertFalse(webView.nativeContextMenuDisabled)
        XCTAssertTrue(webView.configuration.preferences.isTextInteractionEnabled)
    }

    func testFullscreenOrientationRequiresSessionAndRestoresPolicyOnExit() async throws {
        let webView = try await editorWebView()
        let scene = try XCTUnwrap(webView.window?.windowScene)
        XCTAssertTrue(webView.configuration.preferences.isElementFullscreenEnabled)
        var responder: UIResponder? = webView
        while responder != nil, !(responder is WebViewController) { responder = responder?.next }
        let controller = try XCTUnwrap(responder as? WebViewController)
        let rejected = try await webView.callAsyncJavaScript("""
            const orientation=acode.require('orientation');
            try {await orientation.lock('landscape');return false;}catch{return true;}
            """, arguments: [:], in: nil, contentWorld: .page) as? Bool
        XCTAssertEqual(rejected, true)
        do {
            _ = try await webView.callAsyncJavaScript("""
                const target=document.createElement('div');target.id='ios-fullscreen-fixture';target.textContent='Fullscreen fixture';document.body.append(target);
                await target.requestFullscreen();return !!document.fullscreenElement;
                """, arguments: [:], in: nil, contentWorld: .page)
            for _ in 0..<100 {
                if webView.fullscreenState == .inFullscreen { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertEqual(webView.fullscreenState, .inFullscreen)
            XCTAssertGreaterThan(webView.bounds.width, 300)
            XCTAssertGreaterThan(webView.bounds.height, 300)
            try await checkOrientation(webView, scene: scene, controller: controller)
            _ = try await webView.callAsyncJavaScript("await document.exitFullscreen()", arguments: [:], in: nil, contentWorld: .page)
            for _ in 0..<100 {
                if webView.fullscreenState == .notInFullscreen { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertNil(AppDelegate.shared?.fullscreenOrientation)
            XCTAssertNil(controller.fullscreen.requestedOrientation)
            controller.view.layoutIfNeeded()
            let frame = webView.convert(webView.bounds, to: controller.view)
            XCTAssertEqual(frame.minX, controller.view.safeAreaInsets.left, accuracy: 1)
            XCTAssertEqual(webView.frame.width, controller.view.safeAreaLayoutGuide.layoutFrame.width, accuracy: 1)
            XCTAssertGreaterThan(webView.frame.height, 300)
        } catch {
            controller.fullscreen.reset()
            _ = try? await webView.callAsyncJavaScript("if(document.fullscreenElement)await document.exitFullscreen();document.getElementById('ios-fullscreen-fixture')?.remove()", arguments: [:], in: nil, contentWorld: .page)
            throw error
        }
        _ = try await webView.evaluateJavaScript("document.getElementById('ios-fullscreen-fixture')?.remove()")
        let backUnsupported = try await webView.callAsyncJavaScript("""
            const call=enabled=>new Promise((resolve,reject)=>Bridge.exec(resolve,reject,'System','set-fullscreen-back-handler',[enabled]));
            await call(false);try {await call(true);return false;}catch{return true;}
            """, arguments: [:], in: nil, contentWorld: .page) as? Bool
        XCTAssertEqual(backUnsupported, true)
    }

    private func call(_ webView: WKWebView, service: String = "System", action: String, args: [Any]) async throws {
        _ = try await webView.callAsyncJavaScript("await new Promise((resolve,reject)=>Bridge.exec(resolve,reject,service,action,args))", arguments: ["service": service, "action": action, "args": args], in: nil, contentWorld: .page)
    }

    private func checkOrientation(_ webView: WKWebView, scene: UIWindowScene, controller: WebViewController) async throws {
        let result = try await webView.callAsyncJavaScript("""
            try { await acode.require('orientation').lock('landscape'); return ''; }
            catch(error) { return error.message; }
            """, arguments: [:], in: nil, contentWorld: .page) as? String
        let error = try XCTUnwrap(result)
        if !error.isEmpty {
            XCTAssertEqual(UIDevice.current.userInterfaceIdiom, .pad)
            XCTAssertTrue(error.contains("windowing mode"), error)
            XCTAssertNil(AppDelegate.shared?.fullscreenOrientation)
            XCTAssertNil(controller.fullscreen.requestedOrientation)
            XCTAssertEqual(webView.fullscreenState, .inFullscreen)
            _ = try await webView.callAsyncJavaScript("await acode.require('orientation').unlock()", arguments: [:], in: nil, contentWorld: .page)
            XCTAssertNil(AppDelegate.shared?.fullscreenOrientation)
            return
        }
        XCTAssertTrue(scene.effectiveGeometry.interfaceOrientation.isLandscape)
        XCTAssertEqual(AppDelegate.shared?.fullscreenOrientation, .landscape)
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        XCTAssertNil(AppDelegate.shared?.fullscreenOrientation)
        XCTAssertEqual(controller.fullscreen.requestedOrientation, .landscape)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertEqual(AppDelegate.shared?.fullscreenOrientation, .landscape)
        _ = try await webView.callAsyncJavaScript("await acode.require('orientation').lock('portrait');await acode.require('orientation').unlock()", arguments: [:], in: nil, contentWorld: .page)
        XCTAssertNil(AppDelegate.shared?.fullscreenOrientation)
        _ = try await webView.callAsyncJavaScript("await acode.require('orientation').lock('portrait')", arguments: [:], in: nil, contentWorld: .page)
    }
}
