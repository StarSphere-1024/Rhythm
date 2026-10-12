# Rhythm · 节律

Android 优先的免费、离线日程与执行记录应用。Flutter 工程、代码、测试和详细验收记录位于 `app/`；产品目标见 [docs/goal.md](docs/goal.md)。应用代码采用 [MIT](app/LICENSE) 许可，中文字体采用独立的 OFL 许可。

## 当前交付与验证范围

已实现今日时间轴、周一至周日七列课表、收集箱、任务编辑、重复规则、打卡/跳过/撤销/改期、执行历史、周回顾、JSON 完整替换恢复和 Android 本地提醒调度。

已通过无桌面 Chromium、真实 SQLite 文件和 Android 11/17 真机验证。Android 11 覆盖后台送达、重启恢复、原生规则/历史/备份及放大字体软键盘，并修复 release 通知图标资源压缩问题；Android 17（API 37）覆盖运行时通知拒绝/允许/撤销、精确闹钟独立授权/撤销与非精确降级，以及重新授权后的后台真实送达。详细证据见 [Android 11 验收](app/docs/android-verification.md)、[Android 17 验收](app/docs/android17-verification.md)；早期 Web 证据见 [验证记录](app/docs/verification.md)。飞行模式按用户选择未执行，也不宣称所有系统版本与设备均已验收。

Web 是同一套 Flutter 界面的验证入口，不是 Android 通知能力的替代品。Web 的本地存储是浏览器存储；清理站点数据会删除它。Android 使用 SQLite，不以 `shared_preferences` 保存任务或历史。

## 开发环境

本次实际使用：Linux x64、Flutter 3.47.7 stable、Dart 3.13.5、OpenJDK 21、Android SDK 36。APK 实际 manifest 的最低 Android API 为 24，目标 API 为 36。依赖版本提交在 `pubspec.lock`，复现时使用已验证的 Flutter 版本。

安装 Flutter SDK 和 Android 官方 command-line tools 后：

```sh
export ANDROID_SDK_ROOT=/opt/android-sdk
export PATH="/opt/flutter/bin:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"
flutter config --android-sdk "$ANDROID_SDK_ROOT"
sdkmanager 'platform-tools' 'platforms;android-36' 'build-tools;36.0.0'
flutter doctor --android-licenses
flutter doctor -v
```

Flutter 来源：[flutter/flutter](https://github.com/flutter/flutter)。Android command-line tools：[官方下载](https://developer.android.com/studio#command-tools)。第一次 Android 构建会下载 Gradle、所需 SDK/NDK 组件和依赖；**构建需要网络，安装后的应用核心功能不需要网络或账号。**

以下命令都在 `app/` 中执行：

```sh
flutter pub get
flutter test
flutter analyze
flutter run -d <android-device-id>
flutter build apk --release --split-per-abi
```

在受限容器中，若 Flutter 解压引擎文件时报无法修改属主，可仅为该命令设置 `TAR_OPTIONS=--no-same-owner`。本次 APK 构建使用：

```sh
env TAR_OPTIONS=--no-same-owner flutter build apk --release --split-per-abi
```

APK 位于 `build/app/outputs/flutter-apk/`。**当前 release 构建仍使用开发用 debug 签名，仅供验证与侧载，不是正式发布签名。** 分发正式版本前需提供自己的 Android 签名密钥。

`workmanager_android` 当前版本在构建中提示未来 Flutter 内置 Kotlin 支持的迁移要求；本次版本可以构建，升级 Flutter/插件时必须重新验证，不能靠关闭检查掩盖该问题。

## 无桌面页面验证

不安装、不启动 Android 模拟器。先构建包含本地 Flutter Web 资源的实际应用：

```sh
flutter build web --target lib/main.dart --no-web-resources-cdn --no-wasm-dry-run
python3 -m http.server 18080 --directory build/web
```

另一个终端启动真实无界面浏览器，并让自动化工具连接 CDP：

```sh
chromium --headless=new --no-sandbox --disable-dev-shm-usage \
  --remote-debugging-port=19222 --remote-allow-origins='*' \
  --user-data-dir=/tmp/rhythm-validation-chromium about:blank
```

`--no-sandbox` 仅用于此隔离容器，不应作为普通桌面浏览器的默认配置。页面地址为 `http://127.0.0.1:18080/`。本次采用 390×844 CSS 像素视口、真实点击/键盘输入/文件选择/下载，并截图核对；在页面资源加载后通过 CDP 断网继续操作。浏览器冷启动离线加载网页不在此证明范围内，本应用没有把 Web 包装成离线 PWA。

两倍字体验证使用临时入口，加载同一个 `Planner`、`ReminderService` 和 `RhythmShell`，仅在 `MediaQuery` 中设置 `TextScaler.linear(2)`；验证后已移除临时入口。390×500 的缩短视口验证滚动保存入口可访问，**不等同于 Android 真实软键盘测试**。

## 数据与时间约定

- `core/models.dart`：任务、版本化日程规则、单次覆盖和不可变执行快照。
- `core/recurrence.dart`：按查询窗口计算实例；不预生成多年数据。实例身份来自规则 ID 与原计划 UTC 时刻，改期不产生新身份。
- `core/planner.dart`：唯一状态源与串行事务入口。持久化成功后才发布状态；失败保留原状态，后续操作仍可继续。
- `core/snapshot_store.dart`：Android SQLite 内单文档事务存储，使用 WAL 与 FULL 同步；Web 为单文档浏览器存储。此规模采用直接 SQLite，不另建 ORM/状态管理/路由层。
- `core/reminders.dart`：根据同一批实例重建通知，不保存第二套业务日程。
- `features/`：实际四个页面、任务面板与设置；主题跟随系统，动作提供轻量触感。

新规则默认使用首次成功读取的设备时区；读取失败使用并记录 UTC 回退，设置页可选择计划时区。**既有规则保留其创建时区的墙上时间，不随旅行或设备时区改变重新解释。** 日历视图和执行时间按当前设备本地时间显示。

夏令时重复时段采用较早的合法时刻；不存在的墙上时间推进到该缺口结束后的首个合法时刻。时长是实际经过的分钟数，因此跨 DST 的结束墙上时间可能不等于简单的钟面加法。

周回顾中，计划次数按规则原时区的原计划周计算，改期和跨周完成不迁移该分母。跳过仍在分母中；完成率仅计算该计划周的计划完成数。实际完成次数按设备本地的实际执行周计算，包含未排期打卡。无计划时不显示百分比。执行记录保留当时的名称、分类、计划时间及实际时间，后续编辑或删除不改写已有完成/跳过快照。

仅本次修改保存为覆盖；本次及以后产生规则版本；整个系列沿用系列原始日期锚点。删除取消未执行日程并保留执行历史，而不是级联删除历史。

## 提醒与备份

Android 提醒需要通知权限；精确闹钟权限单独请求。没有精确权限时显式降级为系统允许的非精确提醒，设置页显示可能延迟；没有通知权限不影响核心业务。

调度窗口为未来 30 天，由每日 WorkManager 作业及应用启动/恢复前台刷新，插件 boot receiver 恢复已排闹钟。执行、跳过、改期和备份恢复会触发重建。Android 的强行停止、厂商省电策略、后台作业延迟会影响提醒，不能保证任意设备下的无限期准点送达。Web 明确显示提醒不受支持，但仍保留规则中的提醒配置。

JSON 包含任务、版本规则、单次变更、执行历史、分类和计划时区设置。导入先校验类型、身份和关系，再完整替换；无合并或样例填充。覆盖确认支持取消和先导出当前数据。Android 系统权限不是应用备份数据，换设备后仍需自行授权。设备数据不可替代外部备份，建议定期导出。

中文字体来自 [Noto CJK](https://github.com/notofonts/noto-cjk)，许可证见 [app/assets/fonts/OFL.txt](app/assets/fonts/OFL.txt)；应用设置中也可查看开源许可。
