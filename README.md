# 鸿蒙云音乐 HarmonyCloudMusic

基于 HarmonyOS NEXT（API 19 / 5.1.1）与 ArkTS 声明式开发的一款音乐播放应用，包含推荐、发现、动态、我的四大主页，以及独立播放页与歌词同步面板。

个人实践项目，按鸿蒙应用开发课程体系逐日迭代完成，用于技术学习与求职展示。界面素材与音频仅作演示，不含商业音乐版权内容。

## 技术栈

| 分类    | 实际使用                                                           |
| ----- | -------------------------------------------------------------- |
| 开发语言  | ArkTS / TypeScript                                             |
| UI 框架 | ArkUI 声明式开发，Stage 模型                                           |
| 状态管理  | 状态管理 V2：`@Local`、`@Param`、`@Event`、`@ObservedV2`、`@Trace`、`@Monitor`、`AppStorageV2.connect` |
| 页面导航  | `Navigation` + `NavPathStack` + `routerMap` 路由表                |
| 布局与列表 | `Tabs`、`Swiper`、`ForEach` + `ListItem`、`@Builder` 自定义构建函数      |
| 音频播放  | `@kit.MediaKit` AVPlayer（`stateChange` / `timeUpdate` / `durationUpdate` / `error` 事件监听） |
| 后台播控  | `@kit.AVSessionKit`，创建 audio 类型 AVSession，同步桌面卡片/锁屏/灵动岛 |
| 通知与长时任务 | `@kit.NotificationKit`、`@kit.BackgroundTasksKit`（AUDIO_PLAYBACK） |
| 工程工具  | DevEco Studio、Hvigor、hvigorfile.ts                             |

## 项目结构

```
entry/src/main/ets/
├── pages/
│   ├── Index.ets          入口页（Navigation 容器）
│   ├── Start.ets          启动页（3s 自动跳转）
│   ├── Layout.ets         主框架（Tabs 承载四大主页）
│   └── Play.ets           播放页（唱片动画、进度条、控制区、播放列表）
├── component/
│   ├── Recommend.ets      推荐页
│   ├── Found.ets          发现页（歌曲列表）
│   ├── Moment.ets         动态页
│   ├── Mine.ets           我的页（歌单管理、编辑资料、徽章面板）
│   └── LyricView.ets      歌词面板（二分查找定位当前行）
├── models/
│   ├── music.ets          歌曲/动态数据模型
│   ├── songData.ets       歌曲列表数据
│   ├── RecommendData.ets  推荐位数据
│   ├── momentData.ets     动态数据
│   ├── lyricData.ets      歌词数据
│   ├── LyricItem.ets      单行歌词结构（时间戳 + 文本）
│   ├── PlayerState.ets    全局播放状态（@ObservedV2）+ getPlayerState()
│   ├── PlaybackObserver.ets  播放事件观察者接口（解耦播放器与会话）
│   └── MineModels.ets     我的页数据模型与静态数据
├── utils/
│   ├── AvPlayerManager.ets    播放器封装：初始化、状态/进度回调、播放控制
│   ├── AvSessionManager.ets   媒体会话封装：后台播控、元数据上报、通知
│   └── Formatter.ets          纯函数工具：时长/数字格式化、歌词二分、角度换算
├── entryability/          应用入口与生命周期
└── entrybackupability/    备份能力

entry/src/main/resources/base/element/color.json   设计令牌配色
entry/src/test/LocalUnit.test.ets                  关键逻辑单元测试
```

## 关键实现

### 1. 状态管理与循环依赖治理

全局播放状态 `PlayerState`（`@ObservedV2` + `@Trace`）作为唯一数据源，通过 `getPlayerState()`（内部封装 `AppStorageV2.connect`）跨组件共享。

播放器 `AvPlayerManager` 与会话管理器 `AvSessionManager` 之间**不再互相 import**：前者通过 `PlaybackObserver` 接口回调事件，后者实现该接口被动接收；系统媒体控制命令由 `EntryAbility` 通过 `bindPlaybackControls()` 注入。接口定义在独立的 `models/PlaybackObserver.ets`，彻底打破循环依赖。

### 2. 歌词定位：二分查找代替逐行遍历

歌词时间戳为升序数组，逐行遍历需 O(n) 次比较。`computeLyricIndex()`（`utils/Formatter.ets`）改为二分查找最后一个 `time <= currentTime` 的索引，复杂度降为 O(log n)，并已补充边界单元测试。

### 3. 单一数据源驱动 UI（功耗治理）

唱片旋转与歌词高亮均由 `AvPlayer` 的 `timeUpdate` 事件更新 `playState.time`，再通过 `@Monitor('playState.time')` 触发：

- **唱片**：`time` 线性换算旋转角度 + 属性动画（`animation`）平滑跟随；暂停时 `time` 不变 → 自然停转
- **歌词**：`time` 变化时二分计算高亮行并滚动

替代了原先 25ms / 50ms 两个轮询 `setInterval`，消除每秒约 60 次空转唤醒，显著降低功耗。

### 4. 后台播控与状态同步

`AvSessionManager` 通过 `avSession.createAVSession(context, 'bgPlay', 'audio')` 创建会话，播放/暂停/切歌/进度均通过 `setAVPlaybackState` 与 `setAVMetadata` 上报系统，支持桌面媒体卡片、锁屏与灵动岛操作。

> 注意：`setAVPlaybackState` 的 `speed` 字段必须大于 0（暂停态也传 `1.0`），否则会返回 `401` 参数错误导致系统图标不同步。

### 5. 生命周期与资源清理

- 应用退出时 `EntryAbility.onDestroy` 统一 `playerManager.release()` + `sessionManager.destroy()`（幂等，真正调用 `session.destroy()` 并解绑全部监听）
- 所有组件定时器均在 `aboutToDisappear` 中清理，避免回调访问已释放的组件状态

## 关键逻辑单元测试

`entry/src/test/LocalUnit.test.ets` 基于 `@ohos/hypium`，覆盖 `utils/Formatter.ets` 的纯函数：

- `formatDuration`：毫秒转 `mm:ss`，含 0、负数、秒级、分钟级、整分边界
- `formatCount`：≥1万转 `x.x万`
- `timeToRecordAngle`：播放时长换算唱片角度（含自定义角速度）
- `computeLyricIndex`：二分查找歌词行（空数组、首行前、区间、精确命中、末行后）

## 运行方式

1. DevEco Studio 5.1 及以上，安装 HarmonyOS SDK API 19
2. Clone 本仓库，用 DevEco Studio 打开根目录
3. `File → Project Structure → Signing Configs` 勾选自动签名（需登录华为开发者账号）
4. 选择模拟器或真机，运行 `entry` 模块
5. 运行单元测试：右键 `entry/src/test` → `Run`，或在测试类上点击运行

> 仓库不含签名材料与 `local.properties`，需在本地自行生成。构建产物 `build/`、`.hvigor/`、`oh_modules/` 已加入 `.gitignore`。

## 已知不足

- 列表使用 `ForEach` 全量渲染，未接入 `LazyForEach` 懒加载，数据量增大后需要改造
- 播放数据为本地 mock，未接入在线音乐接口
- 快速拖动进度条时歌词/唱片跟随存在轻微延迟

## 后续计划

- [ ] 列表改造为 `LazyForEach` + `IDataSource`，补充滚动帧率实测数据
- [ ] 接入在线音乐接口，替换本地 mock 数据
- [ ] 增加歌单编辑与搜索联想
- [ ] 适配平板与折叠屏多端布局
