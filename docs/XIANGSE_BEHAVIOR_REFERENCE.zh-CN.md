# 香色原包行为依据与本轮验收

日期：2026-10-01。Origo X 分支：`feat/xiangse-xbs`。

## 原始材料与结论

核对的是本地香色闺阁 2.56.1 安装包中提取的资源，以及用户原始 XBS；没有取得完整 Objective-C / Swift 原生源码。

- `book/xsg_extracted/Payload/StandarReader.app/dir_res/plist_settingSearchView.plist`：搜索页面分别配置站点类型和结果过滤。
- 同目录 `plist_settingKeyInfo.plist`：`search_filterResultT` 的 0 为不过滤，2 为匹配关键字，1 为包含关键字（原版推荐默认）。这支持将请求关键词与返回结果过滤分开处理。本项目保留原有不过滤默认值，同时提供精确、包含选项。
- `SearchWebView.js` 是网页内文本高亮、替换和删除脚本，不是跨源搜索调度器，未将其当作搜索引擎源码迁入。
- 原文件 `sourceModelList+3.xbs`：225 条记录，185 条小说；小说中 167 条有发现配置，共 288 个 `bookWorld` 动作。筛选配置为字典 1、字符串 207、数组 48、无筛选 32；解析出 585 个筛选组。
- 字符串形式使用组名与 `标题::值`；数组使用 `key` / `items` / `title` / `value`。实际数组包含整数值，传入脚本时保留数字类型。请求使用 `params.filters.<key>`、`params.filter`、`params.pageIndex`。

`book/_tools/香色闺阁页面结构.md` 只作为已有说明材料，未将其或旧 dudu 代码视为原版源码。实现没有复制原包脚本或品牌资产。

## 本轮用户目标

| 目标 | 已实现行为 | 验证 |
| --- | --- | --- |
| 独立页面跨源找书 | 保留原搜索路由；书名、作者或两者；不过滤、精确、包含 | `book_search_filter_test.dart`、`source_finding_flows_test.dart` |
| 找同一本书的来源 | 同名同作者聚合，保留每个来源候选；不同作者不合并，缺少作者的候选单独保留 | 同上 |
| 从发现的书找其他源 | 详情中的“查找其他书源”带入详情返回的书名、作者；自动并发搜索，排除原来源同一条记录 | `source_finding_flows_test.dart` |
| 按源浏览分类 | 展示原始分类与三种筛选格式，选择条件后从第一页重新请求；按源切换 | `xbs_runtime_test.dart`、`book_source_discovery_page_test.dart`、`source_finding_flows_test.dart` |
| 分类翻页与重试 | 追加页保留已显示的书；失败重试同一页；切换源/筛选时取消旧任务并防止旧结果回填 | `source_finding_flows_test.dart` |
| 并发和增量显示 | 搜索/找源/发现最多 12 个任务，HTTP 共享全局 12、同主机 2，JS 同时执行 2；快源先显示 | `source_task_pool_test.dart`、`source_search_incremental_test.dart`、`source_finding_flows_test.dart` |
| 避免无效反复请求 | 重复页去重并停止继续翻页；空关键词提交取消旧搜索；发现重试保留成功源 | `source_finding_flows_test.dart` |
| 原始脚本接收分类参数 | 字符串多组筛选、数组数字类型和旧 `filter` 别名，真实 FJS 引擎执行 | `xbs_javascript_native_test.dart` |
| 界面风格统一 | 复用原有主题和书籍卡片，共用筛选控件；复杂筛选折叠，窄屏和大字体调整布局 | `source_ui_layout_test.dart`，8 个浅深色/尺寸场景及渲染图检查 |

这里的模糊匹配指包含关键词，不包含错别字纠正或拼音搜索。作者搜索使用原书源关键词接口，再匹配返回的作者；如果网站本身只搜索书名，应用无法让它返回作者名对应的作品。按书找其他来源不会自动替换已入架书籍的阅读进度。

## 验收边界

测试覆盖了上述交互和请求语义；真实 XBS 全量检查覆盖了无损保存与分类格式。它们不等于 185 个网站全部在线，也不等于完整兼容香色所有规则。`nativeTool`、WebView 请求、辅助文件及部分复杂规则仍需后续适配。iOS 构建、安装和真机性能验证单独进行，不能用 Windows 测试结果代替。
