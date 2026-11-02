# 打卡日历

纯本地的习惯打卡记录应用，Flutter 编写，数据只存在手机里，不联网、不注册。

## 下载安装

| 架构 | 适用设备 | 安装包 |
| --- | --- | --- |
| `arm64-v8a` | 绝大多数手机（2017 年以后） | **[⬇ 下载 APK](https://github.com/Yunbuqingluan/checkin-calendar/releases/latest/download/checkin-calendar-arm64-v8a.apk)** |
| `armeabi-v7a` | 较老的 32 位手机 | [下载 APK](https://github.com/Yunbuqingluan/checkin-calendar/releases/latest/download/checkin-calendar-armeabi-v7a.apk) |
| `x86_64` | 安卓模拟器 | [下载 APK](https://github.com/Yunbuqingluan/checkin-calendar/releases/latest/download/checkin-calendar-x86_64.apk) |

上面的链接始终指向最新版本，想装旧版到 [Releases](https://github.com/Yunbuqingluan/checkin-calendar/releases) 页面挑。
第一次安装时系统可能提示「未知来源」，在设置里给浏览器或文件管理器放行一次即可。

- 包名：`com.yunluan.checkincalendar`
- 版本：1.2.3+6
- 平台：Android（主要目标）；Windows / Web 可编译但未适配

## 功能

**项目**
- 新建 / 编辑 / 删除 / 拖拽排序 / 按名称搜索
- 16 个预设立绘图标，也支持从相册选图
- 打卡频率：每日、每隔 N 天、每周指定周几、每月指定几号
- 每日打卡次数：1 次、N 次、无上限
- 自定义数据指标（名称 + 单位），例如「页数/页」「体重/kg」

**打卡**
- 一键打卡，可填备注、指标数值、多张图片
- 补打卡：在任意历史日期补记（只能选今天及以前，且受每日次数上限约束）
- 补打卡只记日期，不写入具体时间；正常打卡才记录时刻
- 跨天判定：凌晨 0:00–0:30 打卡时会问「算今天还是算前一天」
- 长按当天记录可编辑或删除

**日历与统计**
- 月历着色：绿色已打卡、琥珀色补打卡、红色漏卡、灰色今天待打卡
- 自绘折线图 / 柱状图，按指标切换，支持全部 / 7 天 / 30 天 / 本月
- 多指标同图对比：各指标按自身范围归一化后叠在一张图上比较趋势
- 首页卡片显示本周完成进度、今日状态、最近一次指标值

**概览（1.2 新增）**
- 首次进入在主界面上做箭头引导：挖空高亮按钮 + 箭头指向 + 一句话说明，
  依次介绍「新建项目」「搜索」「侧边栏」，有项目时再多一步指向项目卡片；
  可跳过，看过一次不再出现（设置里能重新查看）
- 侧边栏快捷入口：全部项目 / 今日待打卡 / 统计总览 / 设置
- 今日待打卡：只列今天该打且没打满的项目，下面另列今日已完成
- 统计总览：项目数、累计打卡次数、今日待打卡、近 30 天完成率，
  以及每个项目的累计次数、打卡天数、连续天数、完成率进度条

**提醒（1.1 新增）**
- 每个项目可单独开启提醒并设置时间（默认 20:00）
- 已打卡的那天自动跳过，不会重复打扰

**数据**
- 单项目 JSON 导入 / 导出
- 可更改数据目录并自动迁移

## 截图

![首页](docs/screenshots/home.png)

页面预览走 `lib/main_preview.dart`，在浏览器里切页看样式：

```bash
flutter build web -t lib/main_preview.dart --no-web-resources-cdn
```

`?page=detail` 详情页、`?page=overview` 统计总览、`?page=today` 今日待打卡、
`?page=guide` 箭头引导、`?page=empty` 空状态。APK 的入口是 `lib/main.dart`。

## 提醒是怎么工作的

实现放在 `lib/notification_service.dart`：

- 用 `flutter_local_notifications` 一次性排好未来 **30 天**里每个项目需要打卡的具体时刻，
  而不是用「每天重复通知」。因为频率规则（隔天 / 周几 / 每月几号）系统重复通知表达不了，
  只有提前排具体日期才能精确跳过节假日的空档。
- 每次数据变化（打卡、编辑、删除、导入）都会整体重排一次，所以当天打完卡就不会再提醒。
- 使用 `inexactAllowWhileIdle` 非精确闹钟：省电，也不需要用户单独授权「精确闹钟」权限，
  代价是提醒可能有几分钟偏差。
- Android 13+ 第一次打开提醒开关时会弹出通知权限申请；被拒绝时会有提示，
  设置页里也能跳到系统通知设置手动放行。
- 重启手机后由插件的 `ScheduledNotificationBootReceiver` 恢复已排的提醒。

> 注意：如果超过 30 天完全不打开 App，排好的提醒会用完。打开一次 App 就会重新排。

## 代码结构

```
lib/
  main.dart                 应用入口、主题（主题色 / 明暗模式）
  home_page.dart            项目列表、新建/编辑对话框、设置、导入导出、侧边栏
  project_detail_page.dart  月历视图、打卡对话框、记录列表、统计图表（自绘）
  overview_page.dart        统计总览（跨项目汇总与完成率）
  today_page.dart           今日待打卡
  coach_guide.dart          主界面箭头引导（挖空遮罩 + 箭头 + 气泡，Overlay 实现）
  compare_chart.dart        多指标对比折线（各自归一化）
  project_icon.dart         项目图标（预设资源 / 本地图片 / 首字兜底）
  models.dart               Project / CheckInRecord / Metric 与频率、提醒排期、连续天数与完成率
  storage.dart              本地 JSON 读写（原子写 + 备份）、图片与导出目录
  notification_service.dart 通知初始化、权限、提醒排期
  main_preview.dart         各页面的浏览器预览入口
test/
  models_test.dart          频率规则、次数上限、提醒排期、序列化的单元测试
  stats_test.dart           连续天数、累计打卡天数、完成率的单元测试
  widget_test.dart          首页空状态、新建项目落盘、搜索过滤
  detail_page_test.dart     详情页日历、记录展示、补打卡、打卡流程、多指标对比
  pages_test.dart           统计总览、今日待打卡
  coach_guide_test.dart     箭头引导：逐步前进、跳过、只弹一次、设置里重看
  storage_test.dart         导出到「下载/打卡日历导出/」的位置与文件名处理
tool/
  optimize_icons.py         预设图标压缩为 webp、生成应用图标（可选，已执行过）
```

## 数据存储

默认在应用文档目录下：

```
<应用文档目录>/checkin_app/
  projects.json     全部项目与打卡记录
  projects.json.bak 上一次成功的版本（主文件损坏时自动回退）
  images/           打卡附带的图片
  exports/          导出的单项目 JSON
```

写入采用「临时文件 → 写盘 → 备份旧文件 → 原子替换」，中途断电最多丢掉最后一次改动，
不会出现半个 JSON 导致所有数据读不出来。

## 开发

```bash
flutter pub get
flutter run          # 需要连真机或模拟器
flutter test
flutter analyze
flutter build apk --release
```

### 签名

发布签名信息在 `android/key.properties`（已加入 `.gitignore`），密钥库为
`android/app/upload-keystore.jks`：

```properties
storePassword=checkin-2026-release
keyPassword=checkin-2026-release
keyAlias=upload
storeFile=upload-keystore.jks
```

这两个文件请自己备份好，丢了就没法给已安装的用户升级。没有 `key.properties` 时
构建会自动退回 debug 签名，方便在别的机器上编译。

### 网络与镜像

这台机器访问不了 `maven.google.com`，所以 Android 仓库走阿里云镜像
（`android/build.gradle.kts`、`android/settings.gradle.kts`）。依赖
`com.android.tools:desugar_jdk_libs:2.1.4` 是 `flutter_local_notifications` 需要的核心库脱糖，
少了它 release 构建会失败。

## 已知限制

- 只在 Android 上实际运行验证过；Windows / Web 能编译，但没有针对桌面调整布局（打卡提醒只在 Android / iOS 生效）。
- 提醒用非精确闹钟，时间可能有几分钟偏差；国产 ROM 的后台限制可能直接掐掉提醒，需要在系统设置里允许自启动和通知。
- iOS 侧没有验证，Bundle ID 仍是模板值。
- 应用图标是脚本画的（`tool/optimize_icons.py`），要换成品图直接替换 `mipmap-*/ic_launcher.png`。
- 项目数据全量读写单个 JSON，项目数量上千后会变慢。

## 版本记录

**1.2.3+6（第三版）**
- 统计总览：项目数、累计打卡次数、今日待打卡、近 30 天完成率，
  以及每个项目的累计次数 / 打卡天数 / 连续天数 / 完成率进度条
- 今日待打卡页：只列今天该打且没打满的项目，下面另列今日已完成；
  侧边栏加了快捷入口和待打卡数量徽标
- 主界面箭头引导：挖空高亮目标按钮 + 箭头 + 一句话说明，依次介绍新建项目、
  搜索、侧边栏，有项目时多一步指向卡片；可跳过，看过一次不再出现
- 统计支持多指标同图对比：统一时间轴，各指标按自身范围归一化后比较趋势
- 补打卡修正：日期选择器不再允许选未来，已达每日上限的日子置灰并拦截，
  记录只存日期不写时刻
- 导出改为自动写入「下载/打卡日历导出/」：Android 10+ 走 MediaStore 不需要权限，
  Android 9 及以下写公共下载目录，失败才退回应用私有目录
- 设置弹窗不再等磁盘读取，先弹出再异步补上数据目录
- 测试 23 → 47 个

**1.1.0+2（第二版）**
- 新增打卡提醒（时间可设、已打卡自动跳过、重启恢复）
- 预设图标 44.7 MB → 0.59 MB，APK 体积大幅下降
- 换成正式包名 `com.yunluan.checkincalendar` 并配置 release 签名
- 新增应用启动图标
- 修复：间隔天数填 0 时除零崩溃；数据目录异常时首页卡在加载中
- 数据改为原子写入 + `.bak` 备份
- 补充 23 个测试（模型 + 首页 + 详情页）
- 清理未使用依赖（`image_picker`、`image`）

**1.0.0+1（第一版）**
- 核心功能完成，安卓可运行
