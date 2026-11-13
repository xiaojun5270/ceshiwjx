# BulkSurvey · 问卷批量提交（iOS）

一个原生 iOS App：把名单贴进去，点一下就开始逐条自动打开问卷、填写、提交，全程真浏览器环境，进度和结果在页面上实时看。

---

## 一、工程结构

```
BulkSurvey/
├── BulkSurvey.xcodeproj/          # Xcode 工程（直接双击打开）
│   └── xcshareddata/xcschemes/    # 已配好共享 Scheme，命令行也能打包
└── BulkSurvey/
    ├── BulkSurveyApp.swift        # App 入口
    ├── ContentView.swift          # 界面（名单 / 控制 / 结果 / 设置）
    ├── SurveyRunner.swift         # 核心引擎：加载问卷、填表、点提交、判结果
    ├── Models.swift               # 数据模型 + 名单解析
    ├── WebContainer.swift         # WKWebView 封装
    └── Assets.xcassets            # App 图标
```

- 最低系统：iOS 16.0
- 语言：Swift 5 + SwiftUI + WebKit，无第三方依赖，不需要 CocoaPods / SPM

---

## 二、打包成 IPA（在 Mac 上）

### 方式 0：GitHub Actions 自动打无签名包

仓库已配置 `.github/workflows/build-unsigned-ipa.yml`。推送到 `main` 分支后会自动构建，也可以在 GitHub 的 **Actions → Build unsigned IPA → Run workflow** 手动触发。

构建成功后，打开对应的 workflow run，在页面底部下载 `BulkSurvey-unsigned-ipa` artifact，解压后可得到 `BulkSurvey-unsigned.ipa`。

> 这是未签名 IPA，不含证书和 provisioning profile，不能直接安装到普通 iPhone。安装前需要用你自己的 Apple ID/证书通过 AltStore、SideStore、Sideloadly、Xcode 或其他签名工具重新签名。

### 方式 A：Xcode 图形界面（推荐）

1. 双击 `BulkSurvey.xcodeproj` 打开。
2. 左上角选中 **BulkSurvey** target → **Signing & Capabilities** 标签：
   - 勾上 `Automatically manage signing`
   - **Team** 选你自己的 Apple ID（没有就点 Add Account 登录一个，免费账号也行）
   - 如果提示 Bundle ID 被占用，把 `com.zaka.bulksurvey` 改成 `com.你的名字.bulksurvey`
3. 顶部设备选 **Any iOS Device (arm64)**（不能选模拟器，模拟器 Archive 是灰的）。
4. 菜单 **Product → Archive**。
5. 弹出的 Organizer 窗口里点右侧 **Distribute App**：
   - 只自己装 → `Development`（或 `Ad Hoc`，需要已注册设备 UDID）
   - 上架 / TestFlight → `App Store Connect`
6. 下一步选 `Export`，选个导出目录，导出来的文件夹里就是 **`BulkSurvey.ipa`**。

### 方式 B：命令行

```bash
cd BulkSurvey

xcodebuild -project BulkSurvey.xcodeproj \
  -scheme BulkSurvey \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/BulkSurvey.xcarchive \
  archive

xcodebuild -exportArchive \
  -archivePath build/BulkSurvey.xcarchive \
  -exportPath build/ipa \
  -exportOptionsPlist ExportOptions.plist
```

`ExportOptions.plist` 示例（Development 签名，只给自己装）：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>development</string>
    <key>teamID</key>
    <string>你的TeamID</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>compileBitcode</key>
    <false/>
</dict>
</plist>
```

> 免费 Apple ID 签的 App 装机后 **7 天到期**，到期重新 Run / 重新导一次就行。付费开发者账号是一年。

---

## 三、App 怎么用

### 1. 填名单

每行一条，三列：**姓名,工号,邮箱**

```
张三,10001,zhangsan@example.com
李四,10002,lisi@example.com
王五,10003
```

- 邮箱可以留空（问卷目前没有邮箱题）
- 分隔符支持：英文逗号 `,`、中文逗号 `，`、制表符（Excel 直接复制粘贴）、分号、竖线
- 列顺序：姓名在前、工号在后；**如果工号在前也能自动认出来**（会看哪一列是纯编号）
- 带表头的第一行（含「姓名/工号/邮箱」字样）会自动跳过
- 也可以点「粘贴名单」直接从剪贴板灌进来

### 2. 先试跑

点 **先试跑第一条**，只跑名单第一条。等它显示「成功」再点正式的「开始批量提交」。

### 3. 批量跑

- **开始批量提交**：按名单顺序逐条跑，每条之间随机停顿（默认 8–20 秒）
- **暂停 / 继续**：中途可以停一下
- **停止**：随时中止，已提交的记录都保留
- **页面**：右上角按钮，可以切到实时页面看当前在做什么（也能手动操作、手动过验证）

运行期间 **App 必须在前台，别锁屏**（App 已自动禁止自动锁屏）。iOS 不允许后台长时间跑网页，切出去太久会中断。

### 4. 看结果

- 每条都有状态：成功 / 失败 / 需人工
- 失败会写原因（比如「没找到输入框」「出现验证滑块」「等待结果超时」）
- 点 **复制失败名单**，把失败的条目一次性复制出来，改完再跑

---

## 四、验证是怎么处理的

问卷用的是「点提交 → 页面自己生成加密参数 + 走一遍无感验证」的流程。所以这个 App **不去伪造参数、也不硬怼接口**（硬怼会被拦，返回空包）。

做法是让 WebKit 真正加载问卷页面，像人一样填完再点页面上的提交按钮 —— 页面自己的脚本会把该带的 token、验证信息都生成好，无感验证在真实浏览器环境里会静默通过。

如果某一条被判成机器、弹出滑块：

- 默认会**自动暂停**并提示你
- 点右上角「页面」切到实时画面，手动滑一下
- 回到列表点「继续」，接着往下跑

设置里可以关掉「遇到验证就暂停」这个开关（不建议关）。

---

## 五、字段是怎么对上的

App 不写死 `q1`、`q2` 这种编号（问卷一改版就废），而是**按题目标题文字匹配**：

| 名单字段 | 匹配的题目关键词 |
|---|---|
| 工号 | 工号 / 员工编号 / 员工号 / 职工号 / 工牌号 / 学号 / 编号 |
| 姓名 | 姓名 / 名字 / 真实姓名 / 联系人 |
| 邮箱 | 邮箱 / 电子邮件 / 邮件 / email |

- 以后问卷里加了「邮箱」题，会自动把名单第三列填进去
- 万一题目文字全都认不出来，会按页面顺序兜底（工号在第一个框、姓名在第二个框）

---

## 六、参数怎么调

设置面板里可以改：

| 参数 | 默认 | 说明 |
|---|---|---|
| 问卷地址 | 当前问卷 | 换问卷只改这里，代码不用动 |
| 两条间隔最短 | 8 秒 | 太快容易触发风控 |
| 两条间隔最长 | 20 秒 | 每条会在区间内随机取，不是固定值 |
| 单条等待结果 | 70 秒 | 超过就判超时 |
| 失败重试次数 | 1 次 | 单条失败后自动再试 |
| 遇到验证就暂停 | 开 | 建议保持开启 |

名单和设置都会自动保存，App 关掉再打开还在。

---

## 七、常见问题

**Q：Archive 是灰的，点不了？**
顶部设备选成了模拟器。改成 `Any iOS Device (arm64)`。

**Q：报错 "No signing certificate" / "Failed to register bundle identifier"？**
Signing 里 Team 没选，或者 Bundle ID 被别人占了。换一个自己的 Bundle ID（比如 `com.你的名字.bulksurvey`）。

**Q：装到手机上提示「未受信任的开发者」？**
设置 → 通用 → VPN与设备管理 → 找到你的 Apple ID → 信任。免费账号 7 天后要重新签。

**Q：第一条就显示「没找到输入框」？**
把设置里的问卷地址核对一下，或者点「页面」看问卷是不是改版了。日志里会打印出页面上识别到的题目文字，照着改规则就行。

**Q：跑到一半停了？**
看状态栏文字。多半是遇到验证自动暂停了，或者 App 被切到后台了。

**Q：能不能同时开很多条？**
不建议。同一个设备/IP 并发太高最容易被拦。串行 + 随机间隔的通过率最高。
