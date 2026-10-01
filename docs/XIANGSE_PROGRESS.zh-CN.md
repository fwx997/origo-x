# 香色书源集成：实施记录

更新日期：2026-10-02。分支：`feat/xiangse-xbs`，官方基线 `f14f841`。

## 当前状态

已实现独立找书、同书找源和按源分类浏览的核心交互，并接入原始 XBS。仍不是香色全功能兼容版。名称、图标、阅读器、字体和 WebDAV 保留 Origo X 仓库原样；没有迁入 dudu 代码或品牌资产。公开基底本就不依赖商业账号/会员服务。

原包核对依据、当前用户目标的逐项验收与边界见 [行为依据与验收](XIANGSE_BEHAVIOR_REFERENCE.zh-CN.md)。本轮取得的是原包资源和规则，没有完整原生源码。

## iOS 体验版交付（2026-10-02）

- 源码已推送到 [fwx997/origo-x](https://github.com/fwx997/origo-x)，默认分支为 `feat/xiangse-xbs`。
- [下载 IPA 与校验文件](https://github.com/fwx997/origo-x/releases/tag/xbs-preview-3-1)；构建源码提交为 `11f4784de2b7bcb00b86e7d7a8f1ff56469a925f`。
- [GitHub Actions #3](https://github.com/fwx997/origo-x/actions/runs/36929759448) 成功完成全仓库分析、66 项功能回归、8 项 XPath 测试、iOS release 编译、ARM64 和运行库检查、IPA 完整性检查及 Release 发布。
- IPA 大小为 24,299,712 字节；Release 同时提供 `SHA256SUMS.txt`、`SOURCE_COMMIT.txt` 和中文说明。
- 使用独立应用标识 `com.fwx997.origox.xbs`，名称与图标保留上游配置；移除上游开发团队及原作者的 iCloud 容器声明，沿用现有 WebDAV。
- 本版是未签名核心功能体验版，实际 iPhone / LiveContainer 安装、性能和复杂规则兼容仍待验证，不能视为香色全兼容版。使用方法见 [体验版说明](XBS_IOS_PREVIEW.zh-CN.md)。

## 已实现并验证

- 原始 XBS 解码与香色 JSON 识别，独立的 XBS 协议与运行时路由，不再转换成 Legado 字段。
- 管理页接受 `.xbs`，展示小说数、其他类型数和格式错误数。未检测书源不会被注册表隐藏；重复导入保留启停状态。
- HTML/XPath、基础 JSON 路径、字段 JavaScript、动态 GET/POST 和返回结构化列表的 `JSParser`。
- 搜索、详情、分页目录、正文和现有阅读入口连接；`bookWorld` 的字典、分组字符串及数组筛选接到发现页。数组中的数字值保留类型，同时支持 `params.filters` 与旧 `params.filter`。
- 独立搜索页提供书名/作者、精确/包含/不过滤；同书按书名和作者聚合，每个来源仍可选择，作者冲突或缺失不强行合并。
- 发现和搜索的详情页均可“查找其他书源”，自动带入书名、作者并排除原来源同一条记录。
- 搜索和分类复用同一套主题筛选卡片；同书来源按钮纳入原有书籍卡片，更多筛选默认折叠。沿用原配色、圆角和书籍组件；窄屏/大字体自动单列，标签高度随字号调整，兼容浅色、深色及玻璃风格。
- 识别原包中的 Apple 编码标识，分离请求与响应编码，避免关键词二次编码；目录/正文分页使用原规则的 `nextPageUrl`。
- 搜索任务默认最多 12 路，实际网络请求共享全局 12 / 同主机 2 的预算；结果增量出现，可停止、换查询、换范围，旧结果不回填新查询。
- 发现任务上限 12，逐源增量显示，失败重试保留成功内容；分类支持多组筛选、追加分页、失败重试和切换取消。批量检测上限 8，JavaScript 同时执行上限 2；取消传播到排队任务、HTTP 和脚本。
- 书源管理增加名称/域名筛选与批量检测；用户提供检测书名，可以选择只搜书或检测到正文。失败不会删除或禁用源。
- 修复注册表串行写队列空闲后保留旧 Zone Future 导致的跨测试卡住问题。
- 新增 GitHub Actions 工作流 `.github/workflows/xbs-ios.yml`，支持分支推送或手动运行，包含测试、iOS 编译、未签名 IPA 打包、校验值和预发布版本上传；已成功运行并交付。

## 验证证据

- 使用原文件 `D:/Downloads/sourceModelList+3.xbs`：225 条解码成功，185 条小说、40 条其他类型、0 条格式错误。185 个小说 ID 不重复，注册模型 JSON 往返后原规则保持一致。288 个发现动作包含 585 个筛选组，三种已有格式均已解析。
- 本地 132 项 Flutter 回归通过，覆盖导入、注册、调度、精确/模糊/作者搜索、同书聚合、从发现找源、分类筛选与分页、管理页面、阅读模式、网络策略、原有 WebDAV 和自定义字体。结果见 `.dart_tool/xbs-regression-final.log`。
- 原生 FJS 测试使用真实 Windows 动态库，覆盖动态 POST / JSParser、结构化返回值、原始分类参数、死循环超时与重新执行、主动取消死循环。结果见 `.dart_tool/xbs-native-tests.log`。不能将 Windows 结果视为 iOS 真机结果。
- 6 项原生脚本测试通过；8 项界面布局场景通过，覆盖 390 宽常规屏、320 宽窄屏、1.6 倍字号、浅深色/玻璃风格。预览位于 `.dart_tool/ui-previews/`，使用测试书籍；系统封面字库在桌面测试器中不完整，真机字体效果另验。
- 手动联网抽查前 12 个静态搜索请求，以“剑来”为关键词：1 条返回结果、9 条空结果、2 条错误。样本含同站不同规则，且不是全部 185 条逐站验收；空结果不能直接判为失效。诊断文件 `.dart_tool/xbs-live-report.json` 不包含原始规则或凭据。
- 测试文件中的 HTML/JSON 页面为可重复离线样例。**没有据此宣称原来的 185 个网站全部在线可读。**

可重复执行：

```text
flutter test --no-pub test/source_task_pool_test.dart test/xbs_runtime_test.dart test/book_search_filter_test.dart test/source_finding_flows_test.dart test/source_search_incremental_test.dart test/book_source_search_page_test.dart test/book_source_discovery_page_test.dart test/book_source_management_page_test.dart test/webdav_online_content_sync_test.dart
dart --packages=.dart_tool/package_config.json tool/xbs_import_check.dart <原始书源文件>
```

原生执行验证需要提供与 FJS 3.3.2 匹配的动态库，再运行：

```text
flutter test --no-pub --dart-define=XBS_NATIVE_TEST=true test/xbs_javascript_native_test.dart
```

## 尚未完成，不能作为已支持功能

- `nativeTool` 完整语义与缓存持久化、同步 XPath 桥接、辅助文件；需要浏览器的请求目前明确报错，没有伪装成普通 HTTP 成功。
- WKWebView、站点登录/Cookie 会话、复杂规则链和完整 GB18030 生僻字符编码。
- 书单、联想词、常用分类收藏和独立作者检索接口扩展。
- 用户自定义分组/排序、规则编辑与导出、在已入架书籍上替换来源并对齐章节进度。
- 原始源的逐站联网阅读链验证、请求身份与源间会话隔离、解析后台执行和前台阅读优先级。
- XBS WebDAV 配置的凭据分离、跨版本与跨设备冲突恢复；现有 WebDAV 回归通过不等于这些新增场景已经完成。
- 真实手机 / LiveContainer 安装与性能验证。iOS 编译与 IPA 打包已由 GitHub macOS runner 完成；云端构建不等于真机验证。

完整需求与后续阶段见 `XIANGSE_INTEGRATION_PLAN.zh-CN.md`。
