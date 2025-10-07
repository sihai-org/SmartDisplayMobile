# 事故复盘：启动页红屏与无限 Loading 问题

日期：2025-10-07
负责人：Mobile App

## 摘要

应用冷启动出现 Flutter 红屏（构建期异常）。尝试加“等待本地化就绪”的热修后，应用又在部分设备/时序下一直停留在 Splash 页面 Loading，不再跳转。

## 影响

- 用户无法到达登录/首页，冷启动不可用。
- 团队排障时间增加（堆栈信息噪声大、启动逻辑绕圈）。

## 时间线（约）

- T0：冷启动出现红屏。
- T0+?：在 Splash 加了等待本地化的循环以“保证就绪”→ 某些时序下一直不满足条件，卡在 Splash。
- T0+later：注册本地化委托、引入全局安全兜底、修正导航时序 → 启动恢复正常。

## 根因

1) `MaterialApp.router` 未注册生成的本地化委托/语言列表，导致 `Localizations.of<AppLocalizations>(context, AppLocalizations)` 在构建期返回 `null`。

2) Splash 页面对本地化对象进行非空断言/无兜底的解引用，构建期拿到 `null` 后抛异常 → Flutter 红屏。

3) 后续补丁采用“忙等”本地化就绪的循环；在某些设备/时序下条件始终不满足，造成无限 Splash。

## 修复

- 在应用层正确注册本地化委托与支持语言：
  - 文件：`lib/main.dart:1`
  - 方案：使用 `AppLocalizations.localizationsDelegates` 与 `AppLocalizations.supportedLocales`。

- 增加全局非空的本地化访问扩展，提供英文兜底：
  - 文件：`lib/core/l10n/l10n_extensions.dart:1`
  - API：`context.l10n` → `AppLocalizations.of(context) ?? AppLocalizationsEn()`。

- 将关键页面替换为安全访问：
  - `lib/core/router/app_router.dart:1`（错误页）
  - `lib/presentation/pages/profile_page.dart:1`
  - `lib/presentation/pages/settings_page.dart:1`
  - `lib/presentation/pages/main_page.dart:1`

- 调整 Splash 导航时序并移除脆弱等待：
  - 文件：`lib/presentation/pages/splash_page.dart:1`
  - 使用 `WidgetsBinding.instance.addPostFrameCallback` 在首帧后触发导航。
  - 延时约 300ms 以便 UX；读取 Supabase 会话放入 try/catch，异常时回退登录。
  - 文案使用本地化并带安全回退。

## 为什么可行

- 生成的本地化委托通常同步加载（`SynchronousFuture`），但我们仍提供英文兜底，抵御极端时序/环境差异。
- 导航挪到首帧后，避免 `initState` 早期使用 `context` 或依赖 `Localizations` 的时序问题。
- 全面移除对本地化对象的非空断言，杜绝构建期 NPE。

## 预防建议

- 在 `MaterialApp` 始终注册生成的本地化委托与支持语言。
- 禁止对 `AppLocalizations.of(context)` 使用 `!`；统一使用 `context.l10n`。
- 依赖 `context` 的导航逻辑优先放到 `addPostFrameCallback`。
- 避免“忙等”框架就绪；优先使用兜底对象或首帧回调。

## 行动项

-【已完成】新增 `context.l10n` 并在路由与多个页面落地。
-【计划】继续排查剩余 `Localizations.of<AppLocalizations>` 直接用法，必要时替换为 `context.l10n`。
-【可选】在 Code Review 检查清单中加入禁止 `!` 解引用本地化对象；或添加 lint 约束。

## 代码参考

- 启动入口：`lib/main.dart:1`
- 安全本地化扩展：`lib/core/l10n/l10n_extensions.dart:1`
- 路由错误页：`lib/core/router/app_router.dart:1`
- 启动页：`lib/presentation/pages/splash_page.dart:1`
- 已替换页面示例：`lib/presentation/pages/profile_page.dart:1`，`lib/presentation/pages/settings_page.dart:1`，`lib/presentation/pages/main_page.dart:1`
