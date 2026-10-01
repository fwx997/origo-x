# Origo X XBS iOS 体验版

基于 [miloquinn/origo-x](https://github.com/miloquinn/origo-x) 的个人修改版，保留上游名称、图标、阅读器、字体与 WebDAV。不是上游官方发布版本。修改源码见 [fwx997/origo-x](https://github.com/fwx997/origo-x/tree/feat/xiangse-xbs)。

## 本版功能

- 原始 `.xbs` / 香色 JSON 导入，小说源完整保存，不因检测失败删除。
- 独立跨源搜索、书名/作者及精确/包含筛选、同书聚合、详情页查找其他来源。
- 原始分类筛选、分类翻页、失败重试；搜索、发现和管理采用现有主题样式。
- 最多 12 路并发、同站点最多 2 个 HTTP 请求、结果增量显示及取消。
- 书源管理名称/域名筛选、批量搜索或完整阅读链检测。

## 下载与使用

下载 Release 中的 `Origo-X-XBS-unsigned.ipa`。这是未签名安装包，可按已有 LiveContainer 流程导入，或使用自己的签名工具签名后安装。直接点开 IPA 不会完成 iOS 安装。本版尚未完成实际手机和 LiveContainer 验证。

进入书源管理，导入自己的原始 XBS 文件。先启用少量熟悉的小说源，搜索一本确认存在的书，再检查详情、目录和正文。应用不内置用户原始书源包。

本版使用独立 Bundle ID `com.fwx997.origox.xbs`，显示名称及图标保留上游配置。同步使用现有 WebDAV；不配置原作者的 iCloud 容器，也不承诺 App Store 版本的 iCloud 数据可直接访问。

`SOURCE_COMMIT.txt` 记录构建提交；`SHA256SUMS.txt` 用于校验 IPA。源码中保留上游许可及新增依赖许可。

## 已知限制

- 这是核心功能体验版，未完整兼容香色全部规则。`nativeTool`、WebView、站点登录/Cookie、辅助文件和部分复杂解析仍未完成。
- 原文件 185 条小说源可无损保存，不等于 185 个网站均可搜索或阅读。网站离线、验证页和空结果需分别检测。
- “查找其他书源”保留候选来源，尚不支持对已入架书籍自动替换来源并对齐章节进度。
- 书单、联想词、自定义分组/排序、规则编辑/导出、新增 XBS 同步冲突恢复仍在计划中。
- Windows 离线回归、macOS 编译和 IPA 结构校验不能替代 iPhone 实测。

详细实现、验证证据与兼容边界见 [实施记录](https://github.com/fwx997/origo-x/blob/feat/xiangse-xbs/docs/XIANGSE_PROGRESS.zh-CN.md) 和 [行为依据与验收](https://github.com/fwx997/origo-x/blob/feat/xiangse-xbs/docs/XIANGSE_BEHAVIOR_REFERENCE.zh-CN.md)。
