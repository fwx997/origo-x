# x-松鹤阅读脚本失败诊断

日期：2026-10-02。基线：`471c941`（已交付 `2.4.6+261002003`）。

## 复现与原因

使用用户原始 `sourceModelList+3.xbs` 中的 `x-松鹤阅读`，通过本项目真实 FJS 引擎和 HTTP 传输测试。女频分类能返回截图中的《穿书后我傍上了男主他叔》（书籍 ID `1131822340`），请求目录之前即抛出：

```text
chapterList: TypeError: cannot read property 'detailUrl' of undefined
```

这是运行时兼容缺陷。该源的脚本只需要正常 JavaScript 和请求上下文，此次报错不需要引入 WebView 或 nativeTool 才能解决。

修复内容：

- 详情、目录和正文动作获得 `params.queryInfo`，包含 `detailUrl`、`bookId`、`url`、`id`、书名和当前章节标题；目录上下文与正文上下文区分。章节标题按源和书籍隔离，缓存最多 10 本。
- 保留 `1131822340_1` 这样的数字复合 ID，避免变成站点网址后污染正文请求的 `BookID`。
- 按 `Content-Type` 序列化 JSON POST 对象和数组；原始字符串与普通表单仍使用原有行为。
- JSON 路径支持递归查找、通配符和本源需要的字面量过滤，正确执行 `$..state[?(@.dataID==360)]` 与 `$..docId`。不支持的表达式明确报错，不执行任意过滤代码。
- 本源没有独立详情规则，直接沿用搜索或分类返回的书籍资料，避免对数字 ID 发起无意义的详情请求。

## 真实网络复核

最终复核使用正式 `XbsRuntime` / `XbsQuickJs`；没有替换 JavaScript 引擎，没有用离线样例替代网络结果。

| 项目 | 结果 |
| --- | --- |
| 女频分类 | 20 本 |
| 《穿书后我傍上了男主他叔》目录 | 776 章 |
| 上述书籍第 1、2 章 | 分别 1,188、1,143 个字符，内容不同 |
| 男频分类 | 20 本 |
| 《校花的贴身高手》目录 | 13,213 章 |
| 上述书籍第 1、2 章 | 分别 2,962、2,303 个字符，内容不同 |
| 搜索截图中的书名 | 20 条结果，首条为目标书籍 |

字符数为 Dart 字符串长度，仅作为诊断指标。只检查上述章节，没有进行整本下载。

本地诊断记录：`.dart_tool/songhe-probe-before.log`、`.dart_tool/songhe-probe-final.log`、`.dart_tool/songhe-probe/report.json`。网络响应保留在被 Git 忽略的本地诊断目录，未加入版本库。

## 自动回归

`test/fixtures/xbs_songhe.json` 保留本源相关动作规则，测试 GUID 已替换；自动测试的书名、目录、正文均为合成数据，不联网。

- `xbs_songhe_native_test.dart`：原始脚本串联搜索、详情、目录、正文；校验复合 ID、JSON 正文请求、章节标题上下文以及新建运行时后的恢复阅读。
- `xbs_json_path_test.dart`：递归、筛选、索引、数组、属性存在性及不支持语法。
- `xbs_runtime_test.dart`：HTML 分页阅读等原有场景，以及 JSON 对象/数组、原始字符串和表单 POST。

原生测试需 FJS 动态库，并使用 `--dart-define=XBS_NATIVE_TEST=true`。最终相关回归 30 项通过，包含上述测试、已有原生脚本与章节缓存测试；修改涉及的 Dart 文件静态分析通过。

全量首次执行 759 项通过、2 项失败：新增 POST 测试的样例 Map 类型推断过窄（已修正），以及既有章节缓存写入等待超时（未改缓存实现，复核通过）。完整记录在 `.dart_tool/songhe-full-regression.log`，修正后的 30 项回归记录在 `.dart_tool/songhe-rerun.log`；不将首次全量运行描述为全部通过。

## 交付边界

这些修改当前在本地源码中，尚未生成包含本次修复的新 IPA，已交付的 `2.4.6+261002003` 不包含本次修复。Windows 实际联网结果不等同于 iPhone / LiveContainer 真机验证，也不代表其他所有 XBS 书源已兼容。
