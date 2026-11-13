import Foundation
import UIKit
import WebKit

// MARK: - 核心引擎：真浏览器逐条填写 + 提交

@MainActor
final class SurveyRunner: NSObject, ObservableObject {

    // 对外状态
    @Published var isRunning = false
    @Published var isPaused = false
    @Published var showWebView = false
    @Published var statusText = "待开始"
    @Published var progressDone = 0
    @Published var progressTotal = 0
    @Published var records: [RunRecord] = []
    @Published var successCount = 0
    @Published var failCount = 0
    @Published var blockedCount = 0
    @Published var attentionText: String?

    var config = RunConfig() {
        didSet { config.save() }
    }

    private(set) lazy var webView: WKWebView = makeWebView()

    private var runTask: Task<Void, Never>?
    private var bgTask: UIBackgroundTaskIdentifier = .invalid
    private var queue: [SurveyEntry] = []

    // MARK: - 初始化

    override init() {
        super.init()
        self.config = RunConfig.load()
    }

    private func makeWebView() -> WKWebView {
        let conf = WKWebViewConfiguration()
        conf.websiteDataStore = .default()
        conf.defaultWebpagePreferences.allowsContentJavaScript = true
        conf.allowsInlineMediaPlayback = true
        conf.mediaTypesRequiringUserActionForPlayback = []

        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 780), configuration: conf)
        wv.allowsBackForwardNavigationGestures = false
        wv.scrollView.isScrollEnabled = true
        if #available(iOS 16.4, *) {
            wv.isInspectable = true
        }
        return wv
    }

    // MARK: - 对外操作

    func start(_ entries: [SurveyEntry]) {
        guard !isRunning, !entries.isEmpty else { return }

        queue = entries
        records = []
        successCount = 0
        failCount = 0
        blockedCount = 0
        progressDone = 0
        progressTotal = entries.count
        attentionText = nil
        isPaused = false
        isRunning = true
        statusText = "准备开始…"

        UIApplication.shared.isIdleTimerDisabled = true
        beginBackgroundTask()

        runTask = Task { [weak self] in
            await self?.loop()
        }
    }

    func pause() {
        guard isRunning else { return }
        isPaused = true
        statusText = "已暂停"
    }

    func resume() {
        guard isRunning else { return }
        isPaused = false
        attentionText = nil
        statusText = "继续运行…"
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
        isRunning = false
        isPaused = false
        statusText = "已停止"
        UIApplication.shared.isIdleTimerDisabled = false
        endBackgroundTask()
    }

    /// 只跑第一条，验证配置是否可用
    func testFirst(_ entries: [SurveyEntry]) {
        guard let first = entries.first else { return }
        start([first])
    }

    // MARK: - 主循环

    private func loop() async {
        for (index, entry) in queue.enumerated() {
            if Task.isCancelled { break }
            await waitIfPaused()
            if Task.isCancelled { break }

            statusText = "第 \(index + 1)/\(queue.count) 条：\(entry.name)"

            var status: EntryStatus = .failed
            var note = "未执行"

            var attempt = 0
            let maxAttempt = max(0, config.maxRetry) + 1
            while attempt < maxAttempt {
                attempt += 1
                if Task.isCancelled { break }

                let r = await submitOnce(entry)
                status = r.0
                note = r.1

                if r.0 == .success || r.0 == .blocked { break }
                if attempt < maxAttempt {
                    statusText = "第 \(index + 1) 条失败，3 秒后重试…"
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                }
            }

            if Task.isCancelled && status != .success {
                status = .failed
                note = "已停止"
            }

            let rec = RunRecord(name: entry.name, jobNo: entry.jobNo, email: entry.email,
                                status: status, note: note)
            records.append(rec)
            progressDone += 1

            switch status {
            case .success: successCount += 1
            case .failed:  failCount += 1
            case .blocked: blockedCount += 1
            default: break
            }

            if status == .blocked && config.stopOnCaptcha {
                attentionText = "第 \(index + 1) 条卡在验证。点右上角「页面」手动滑一下，再点继续。"
                statusText = "需要手动过验证"
                isPaused = true
                await waitIfPaused()
                attentionText = nil
            }

            if index < queue.count - 1 && !Task.isCancelled {
                let low  = max(1.0, config.minDelay)
                let high = max(low, config.maxDelay)
                let delay = Double.random(in: low...high)
                statusText = "等待 \(Int(delay)) 秒后继续（\(records.count)/\(queue.count) 已完成）"
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        if Task.isCancelled {
            statusText = "已停止：成功 \(successCount)，失败 \(failCount)，需人工 \(blockedCount)"
        } else {
            statusText = "全部完成：成功 \(successCount)，失败 \(failCount)，需人工 \(blockedCount)"
        }
        isRunning = false
        isPaused = false
        UIApplication.shared.isIdleTimerDisabled = false
        endBackgroundTask()
    }

    private func waitIfPaused() async {
        while isPaused && isRunning && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
    }

    // MARK: - 单条提交流程

    private func submitOnce(_ entry: SurveyEntry) async -> (EntryStatus, String) {

        guard await loadPage() else {
            return (.failed, "问卷页面没加载出来")
        }
        if Task.isCancelled { return (.failed, "已停止") }

        // 等页面脚本就绪（模拟人打开页面的停顿）
        try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 1.6...2.8) * 1_000_000_000))
        if Task.isCancelled { return (.failed, "已停止") }

        let fill = await fill(entry)
        guard fill.ok else {
            return (.failed, fill.detail)
        }

        try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.6...1.5) * 1_000_000_000))
        if Task.isCancelled { return (.failed, "已停止") }

        let clicked = await eval(Self.clickScript) as? String
        guard clicked == "clicked" else {
            return (.failed, "没找到提交按钮")
        }

        return await waitResult(timeout: config.perEntryTimeout)
    }

    // MARK: - 页面加载

    private func loadPage() async -> Bool {
        guard let url = URL(string: config.url.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        webView.load(request)

        let deadline = Date().addingTimeInterval(40)
        while Date() < deadline {
            if Task.isCancelled { return false }
            try? await Task.sleep(nanoseconds: 500_000_000)

            let ready = await eval("(function(){return document.readyState;})()") as? String
            if ready == "complete" {
                let hasForm = await eval("(function(){return !!document.querySelector('#divQuestion, #ctlNext, .submitbtn');})()")
                if Self.boolValue(hasForm) == true { return true }
            }
        }
        return false
    }

    // MARK: - 填表

    private struct FillResult {
        var ok: Bool
        var detail: String
    }

    private func fill(_ entry: SurveyEntry) async -> FillResult {
        let script = Self.fillScript
            .replacingOccurrences(of: "__NAME__",  with: Self.jsString(entry.name))
            .replacingOccurrences(of: "__JOB__",   with: Self.jsString(entry.jobNo))
            .replacingOccurrences(of: "__EMAIL__", with: Self.jsString(entry.email))

        guard let raw = await eval(script) as? String,
              let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return FillResult(ok: false, detail: "填写脚本没有返回结果")
        }

        let ok = Self.boolValue(obj["ok"]) ?? false
        let missing = (obj["missing"] as? [String]) ?? []
        let labels = (obj["labels"] as? [String]) ?? []
        let note = (obj["note"] as? String) ?? ""

        if ok {
            return FillResult(ok: true, detail: note.isEmpty ? "已填写" : note)
        }

        let missingText = missing.isEmpty ? "未知字段" : missing.joined(separator: ",")
        let labelText = labels.isEmpty ? "页面上没找到输入框" : "页面题目：\(labels.joined(separator: " / "))"
        return FillResult(ok: false, detail: "缺字段[\(missingText)]，\(labelText)")
    }

    // MARK: - 等提交结果

    private func waitResult(timeout: Double) async -> (EntryStatus, String) {
        let deadline = Date().addingTimeInterval(timeout)
        var retriedClick = false
        let clickAt = Date()

        while Date() < deadline {
            if Task.isCancelled { return (.failed, "已停止") }
            try? await Task.sleep(nanoseconds: 1_000_000_000)

            if let raw = await eval(Self.checkScript) as? String,
               let data = raw.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

                let state = (obj["state"] as? String) ?? "waiting"
                let tip = ((obj["tip"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

                switch state {
                case "success":
                    return (.success, "提交成功")
                case "captcha":
                    return (.blocked, "出现验证滑块")
                case "failed":
                    return (.failed, tip.isEmpty ? "页面提示提交失败" : tip)
                default:
                    break
                }
            }

            // 点击后 5 秒还没反应，补点一次
            if !retriedClick && Date().timeIntervalSince(clickAt) > 5 {
                retriedClick = true
                let again = await eval(Self.clickScript) as? String
                if again != "clicked" { break }
            }
        }
        return (.failed, "等待结果超时")
    }

    // MARK: - JS 求值

    private func eval(_ script: String) async -> Any? {
        await withCheckedContinuation { (cont: CheckedContinuation<Any?, Never>) in
            self.webView.evaluateJavaScript(script) { result, _ in
                cont.resume(returning: result)
            }
        }
    }

    static func boolValue(_ any: Any?) -> Bool? {
        if let b = any as? Bool { return b }
        if let n = any as? NSNumber { return n.boolValue }
        return nil
    }

    // MARK: - 后台保活

    private func beginBackgroundTask() {
        endBackgroundTask()
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "BulkSurvey") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard bgTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(bgTask)
        bgTask = .invalid
    }

    // MARK: - JS 字符串转义

    static func jsString(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

    // MARK: - 注入脚本

    /// 按题目标题自动匹配输入框：工号 / 姓名 / 邮箱
    static let fillScript = #"""
    (function(){
      var D = {name: __NAME__, jobNo: __JOB__, email: __EMAIL__};
      var res = {ok:false, filled:{}, missing:[], labels:[], note:''};

      function setVal(el, v){
        try{
          var proto = (el.tagName === 'TEXTAREA') ? window.HTMLTextAreaElement.prototype
                                                 : window.HTMLInputElement.prototype;
          var d = Object.getOwnPropertyDescriptor(proto, 'value');
          if (el.focus) { el.focus(); }
          if (d && d.set) { d.set.call(el, v); } else { el.value = v; }
          ['input','change','keyup','blur'].forEach(function(t){
            el.dispatchEvent(new Event(t, {bubbles:true}));
          });
          if (typeof window.setTip === 'function')  { try{ window.setTip(el); }catch(e){} }
          if (typeof window.hideTip === 'function') { try{ window.hideTip(el); }catch(e){} }
        }catch(e){}
      }

      function labelOf(n){
        var t = n.querySelector('.topichtml') || n.querySelector('.topic')
             || n.querySelector('.field-label') || n;
        var s = (t.innerText || t.textContent || '') + '';
        return s.replace(/\s+/g,'').trim();
      }

      function inputOf(n){
        return n.querySelector('textarea, input[type=text], input:not([type])');
      }

      var fields = [];
      var nodes = document.querySelectorAll('.field, .ui-field-contain, fieldset > div[id^="div"]');
      for (var i = 0; i < nodes.length; i++){
        if (inputOf(nodes[i])) { fields.push(nodes[i]); }
      }
      if (fields.length === 0){
        var loose = document.querySelectorAll('#divQuestion input[type=text], #divQuestion textarea');
        for (var j = 0; j < loose.length; j++){ fields.push(loose[j].parentNode || loose[j]); }
      }

      res.labels = fields.map(function(f){ return labelOf(f).slice(0,20); });

      var rules = [
        {k:'jobNo', re:/(工号|员工编号|员工号|职工号|工牌号|学号|编号)/},
        {k:'name',  re:/(姓名|名字|真实姓名|联系人)/},
        {k:'email', re:/(邮箱|电子邮件|邮件|e-?mail)/i}
      ];

      var used = [];
      rules.forEach(function(rule){
        var v = D[rule.k];
        if (!v) { return; }
        for (var i = 0; i < fields.length; i++){
          var f = fields[i];
          if (used.indexOf(f) >= 0) { continue; }
          if (rule.re.test(labelOf(f))){
            var inp = inputOf(f);
            if (inp){ setVal(inp, v); used.push(f); res.filled[rule.k] = labelOf(f); }
            break;
          }
        }
      });

      // 题目文字认不出来时，按页面顺序兜底（工号在前、姓名在后）
      if (!res.filled.jobNo && !res.filled.name && fields.length >= 2){
        var a = inputOf(fields[0]);
        var b = inputOf(fields[1]);
        if (a && D.jobNo){ setVal(a, D.jobNo); used.push(fields[0]); res.filled.jobNo = labelOf(fields[0]); }
        if (b && D.name) { setVal(b, D.name);  used.push(fields[1]); res.filled.name  = labelOf(fields[1]); }
        res.note = '按页面顺序填写';
      }

      ['name','jobNo'].forEach(function(k){ if (!res.filled[k]) { res.missing.push(k); } });
      res.ok = res.missing.length === 0;
      return JSON.stringify(res);
    })()
    """#

    /// 点击提交（走页面自身提交链路，加密参数与无感验证由页面生成）
    static let clickScript = #"""
    (function(){
      var btn = document.querySelector('#ctlNext')
             || document.querySelector('.submitbtn')
             || document.querySelector('#submit_button')
             || document.querySelector('input[type=submit]')
             || document.querySelector('button[type=submit]');

      if (!btn){
        var all = document.querySelectorAll('div,a,button,span');
        for (var i = 0; i < all.length; i++){
          var t = (all[i].innerText || '').replace(/\s/g,'');
          if ((t === '提交' || t === '提交问卷' || t === '交卷' || t === '完成') && all[i].offsetParent !== null){
            btn = all[i];
            break;
          }
        }
      }
      if (!btn) { return 'no-button'; }

      try { btn.scrollIntoView({block:'center'}); } catch(e){}
      try {
        ['mousedown','mouseup','click'].forEach(function(type){
          btn.dispatchEvent(new MouseEvent(type, {bubbles:true, cancelable:true, view:window}));
        });
      } catch(e){
        try { btn.click(); } catch(e2){ return 'no-click'; }
      }
      return 'clicked';
    })()
    """#

    /// 判定提交结果
    static let checkScript = #"""
    (function(){
      var out = {state:'waiting', tip:'', url:location.href};
      var body = document.body ? (document.body.innerText || '') : '';

      var cap = document.querySelector('#captchaOut');
      var capVisible = cap && cap.offsetParent !== null;
      var capText = capVisible ? ((cap.innerText || '').replace(/\s/g,'')) : '';
      if (capText.length > 0 && /滑块|滑动|验证|拖动|按住/.test(capText)) {
        out.state = 'captcha';
        out.tip = capText.slice(0, 60);
        return JSON.stringify(out);
      }
      if (/请按住滑块|拖动滑块|向右滑动|请完成安全验证|请拖动滑块/.test(body)) {
        out.state = 'captcha';
        return JSON.stringify(out);
      }

      if (/提交成功|提交完成|感谢您的参与|感谢参与|感谢您的填写|您的答卷已提交|已成功提交|答卷已提交/.test(body)) {
        out.state = 'success';
        return JSON.stringify(out);
      }
      if (/complete=1/i.test(location.href)) {
        out.state = 'success';
        return JSON.stringify(out);
      }

      var errNode = document.querySelector('.errorMessage, #ValError, .layui-layer-content, .wjx-layer-content');
      var errVisible = errNode && errNode.offsetParent !== null;
      var errText = errVisible ? ((errNode.innerText || '').replace(/\s/g,'')) : '';
      if (errText.length > 0) {
        out.state = 'failed';
        out.tip = errText.slice(0, 80);
        return JSON.stringify(out);
      }
      if (/该问卷已结束|问卷已停止|已经提交过|不能重复提交|请勿重复提交|达到上限|提交次数已满|已停止收集/.test(body)) {
        out.state = 'failed';
        out.tip = body.replace(/\s+/g,' ').slice(0, 80);
        return JSON.stringify(out);
      }

      return JSON.stringify(out);
    })()
    """#
}
