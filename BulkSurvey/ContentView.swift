import SwiftUI
import UIKit

struct ContentView: View {

    @StateObject private var runner = SurveyRunner()
    @AppStorage("draft_list") private var draft: String = ""
    @State private var entries: [SurveyEntry] = []
    @State private var showSettings = false
    @State private var toast: String?

    private let sampleList = """
    张三,10001,zhangsan@example.com
    李四,10002,lisi@example.com
    王五,10003,wangwu@example.com
    """

    var body: some View {
        ZStack(alignment: .top) {

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(spacing: 14) {
                        listCard
                        controlCard
                        recordsCard
                        settingsCard
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }

            // 实时页面（默认几乎透明地挂在底层跑，点「页面」可全屏查看）
            WebContainer(webView: runner.webView)
                .opacity(runner.showWebView ? 1 : 0.02)
                .allowsHitTesting(runner.showWebView)
                .ignoresSafeArea()

            if runner.showWebView {
                VStack {
                    HStack {
                        Text("实时页面").font(.footnote.bold())
                        Spacer()
                        Button {
                            runner.showWebView = false
                        } label: {
                            Text("关闭").font(.footnote.bold())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    Spacer()
                }
            }

            if let toast {
                Text(toast)
                    .font(.footnote)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                    .padding(.top, 60)
                    .transition(.opacity)
            }
        }
        .onAppear {
            entries = EntryParser.parse(draft)
        }
        .onChange(of: draft) { newValue in
            entries = EntryParser.parse(newValue)
        }
    }

    // MARK: - 顶栏

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("问卷批量提交")
                    .font(.headline)
                Text(runner.statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                runner.showWebView.toggle()
            } label: {
                Label("页面", systemImage: "safari")
                    .font(.footnote.bold())
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: - 名单

    private var listCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("名单").font(.subheadline.bold())
                Spacer()
                Text("\(entries.count) 条")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            TextEditor(text: $draft)
                .font(.system(.footnote, design: .monospaced))
                .frame(minHeight: 132)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)

            HStack(spacing: 16) {
                Button {
                    if let s = UIPasteboard.general.string, !s.isEmpty {
                        draft = s
                        showToast("已粘贴 \(EntryParser.parse(s).count) 条")
                    } else {
                        showToast("剪贴板是空的")
                    }
                } label: { Text("粘贴名单").font(.caption.bold()) }

                Button {
                    draft = ""
                } label: { Text("清空").font(.caption) }

                Button {
                    if draft.isEmpty { draft = sampleList } else { draft += "\n" + sampleList }
                } label: { Text("插入示例").font(.caption) }

                Spacer()
            }

            Text("每行一条：姓名,工号,邮箱（邮箱可留空）\n工号姓名顺序反了也能自动认，支持逗号 / 制表符 / 分号")
                .font(.caption2)
                .foregroundColor(.secondary)

            if !entries.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(entries.prefix(3)) { e in
                        Text("· \(e.name)  \(e.jobNo)  \(e.email)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    if entries.count > 3 {
                        Text("… 共 \(entries.count) 条")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }

    // MARK: - 控制

    private var controlCard: some View {
        VStack(spacing: 12) {
            if runner.progressTotal > 0 {
                ProgressView(value: Double(runner.progressDone),
                             total: Double(max(1, runner.progressTotal)))
                    .tint(.accentColor)
                HStack {
                    Text("\(runner.progressDone)/\(runner.progressTotal)")
                    Spacer()
                    Text("成功 \(runner.successCount)   失败 \(runner.failCount)   需人工 \(runner.blockedCount)")
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }

            if let attention = runner.attentionText {
                Text(attention)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if runner.isRunning {
                HStack(spacing: 10) {
                    Button {
                        if runner.isPaused { runner.resume() } else { runner.pause() }
                    } label: {
                        Text(runner.isPaused ? "继续" : "暂停")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        runner.stop()
                    } label: {
                        Text("停止")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            } else {
                VStack(spacing: 8) {
                    Button {
                        runner.start(entries)
                    } label: {
                        Text("开始批量提交（\(entries.count) 条）")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(entries.isEmpty)

                    Button {
                        runner.testFirst(entries)
                    } label: {
                        Text("先试跑第一条")
                            .font(.footnote.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.bordered)
                    .disabled(entries.isEmpty)
                }
            }

            Text("运行时请保持本页在前台，不要锁屏。")
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }

    // MARK: - 记录

    private var recordsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("结果").font(.subheadline.bold())
                Spacer()
                if !runner.records.isEmpty {
                    Button {
                        copyFailed()
                    } label: {
                        Text("复制失败名单").font(.caption2.bold())
                    }
                }
            }

            if runner.records.isEmpty {
                Text("还没有记录。先点「试跑第一条」看看通不通。")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                ForEach(runner.records.reversed().prefix(60)) { r in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(color(for: r.status))
                            .frame(width: 7, height: 7)
                        Text("\(r.name)  \(r.jobNo)")
                            .font(.footnote)
                            .lineLimit(1)
                        Spacer()
                        Text(r.status.rawValue)
                            .font(.caption2.bold())
                            .foregroundColor(color(for: r.status))
                    }
                    .padding(.vertical, 3)

                    if !r.note.isEmpty {
                        Text(r.note)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .padding(.leading, 15)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }

    // MARK: - 设置

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation { showSettings.toggle() }
            } label: {
                HStack {
                    Text("设置").font(.subheadline.bold())
                    Spacer()
                    Image(systemName: showSettings ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showSettings {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("问卷地址").font(.caption).foregroundColor(.secondary)
                        TextField("https://", text: $runner.config.url)
                            .font(.system(.footnote, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                    }

                    stepperRow(title: "两条间隔最短", value: "\(Int(runner.config.minDelay)) 秒",
                               onMinus: { runner.config.minDelay = max(1, runner.config.minDelay - 1) },
                               onPlus: { runner.config.minDelay = min(600, runner.config.minDelay + 1) })

                    stepperRow(title: "两条间隔最长", value: "\(Int(runner.config.maxDelay)) 秒",
                               onMinus: { runner.config.maxDelay = max(runner.config.minDelay, runner.config.maxDelay - 1) },
                               onPlus: { runner.config.maxDelay = min(1800, runner.config.maxDelay + 1) })

                    stepperRow(title: "单条等待结果", value: "\(Int(runner.config.perEntryTimeout)) 秒",
                               onMinus: { runner.config.perEntryTimeout = max(20, runner.config.perEntryTimeout - 5) },
                               onPlus: { runner.config.perEntryTimeout = min(300, runner.config.perEntryTimeout + 5) })

                    stepperRow(title: "失败重试次数", value: "\(runner.config.maxRetry) 次",
                               onMinus: { runner.config.maxRetry = max(0, runner.config.maxRetry - 1) },
                               onPlus: { runner.config.maxRetry = min(3, runner.config.maxRetry + 1) })

                    Toggle("遇到验证就暂停等我手动处理", isOn: $runner.config.stopOnCaptcha)
                        .font(.caption)

                    Text("间隔别调太小，太快更容易被风控盯上。默认 8–20 秒比较稳。")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }

    private func stepperRow(title: String, value: String,
                            onMinus: @escaping () -> Void,
                            onPlus: @escaping () -> Void) -> some View {
        HStack {
            Text(title).font(.caption)
            Spacer()
            Text(value).font(.caption.bold()).foregroundColor(.secondary)
            Button(action: onMinus) {
                Image(systemName: "minus.circle").font(.body)
            }
            .buttonStyle(.borderless)
            Button(action: onPlus) {
                Image(systemName: "plus.circle").font(.body)
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - 小工具

    private func color(for status: EntryStatus) -> Color {
        switch status {
        case .success: return .green
        case .failed:  return .red
        case .blocked: return .orange
        case .running: return .blue
        case .pending: return .gray
        }
    }

    private func copyFailed() {
        let lines = runner.records
            .filter { $0.status != .success }
            .map { "\($0.name),\($0.jobNo),\($0.email)  # \($0.status.rawValue) \($0.note)" }
        if lines.isEmpty {
            showToast("没有失败的条目")
            return
        }
        UIPasteboard.general.string = lines.joined(separator: "\n")
        showToast("已复制 \(lines.count) 条失败记录")
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { toast = nil }
        }
    }
}
