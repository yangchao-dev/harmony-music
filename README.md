# 鸿蒙云音乐 HarmonyCloudMusic

基于 HarmonyOS NEXT（API 19 / 5.1.1）与 ArkTS 声明式开发的一款音乐播放应用，包含推荐、发现、动态、我的四大主页，以及独立播放页与歌词同步面板。

个人实践项目，按鸿蒙应用开发课程体系逐日迭代完成，用于技术学习与求职展示。界面素材仅作演示，不含商业音乐版权内容。

## 技术栈

| 分类    | 实际使用                                                           |
| ----- | -------------------------------------------------------------- |
| 开发语言  | ArkTS / TypeScript                                             |
| UI 框架 | ArkUI 声明式开发，Stage 模型                                           |
| 状态管理  | 状态管理 V2：`@Local`、`@ObservedV2`、`@Trace`、`AppStorageV2.connect` |
| 页面导航  | `Navigation` + `NavPathStack`                                  |
| 布局与列表 | `Tabs`、`Swiper`、`ForEach` + `ListItem`、`@Builder` 自定义构建函数      |
| 音频播放  | `@kit.MediaKit` AVPlayer（`stateChange` / `timeUpdate` 事件监听）    |
| 后台播控  | `@kit.AVSessionKit`，创建 audio 类型 AVSession                      |
| 工程工具  | DevEco Studio、Hvigor、hvigorfile.ts                             |

## 项目结构

```
entry/src/main/ets/
├── pages/
│   ├── Start.ets          启动页
│   ├── Layout.ets         主框架（Tabs 承载四大主页）
│   ├── Index.ets          入口页
│   └── Play.ets           播放页（560 行，含进度条、控制区、歌词联动）
├── component/
│   ├── Recommend.ets      推荐页
│   ├── Found.ets          发现页
│   ├── Moment.ets         动态页
│   ├── Mine.ets           我的页
│   └── LyricView.ets      歌词面板（二分查找定位当前行）
├── models/
│   ├── music.ets          歌曲数据模型
│   ├── songData.ets       歌曲列表数据
│   ├── RecommendData.ets  推荐位数据
│   ├── momentData.ets     动态数据
│   ├── lyricData.ets      歌词数据（617 行）
│   ├── LyricItem.ets      单行歌词结构（时间戳 + 文本）
│   └── globalMusic.ets    全局播放状态模型
├── utils/
│   ├── AvPlayerManager.ets    播放器封装：初始化、状态回调、进度回调
│   └── AvSessionManager.ets   媒体会话封装：后台播控、元数据上报
├── entryability/          应用入口与生命周期
└── entrybackupability/    备份能力
```

## 关键实现

### 1. 歌词定位：二分查找代替逐行遍历

歌词时间戳为升序数组，若逐行遍历比对当前播放进度，需 O(n) 次比较。`LyricView.ets` 的 `computeCurrentIndex()` 改为二分查找目标行（最后一个 `time <= currentTime` 的索引），复杂度降为 O(log n)：

```typescript
// LyricView.ets 第 111-121 行
// 歌词按时间升序排列，用二分查找最后一个 time <= currentTime 的索引
let lo = 0
let hi = this.lyrics.length - 1
let result = -1
while (lo <= hi) {
  const mid = (lo + hi) >>> 1
  if (this.lyrics[mid].time <= currentTime) {
    result = mid
    lo = mid + 1
  } else {
    hi = mid - 1
  }
}
```

- 歌词总量：`lyricData.ets` 共 617 行数据
- 优化前后耗时：待用 DevEco Studio Profiler 实测补充

### 2. 播放位置刷新与状态同步

播放器在 `timeUpdate` 事件中回传实时播放位置。歌词面板不直接依赖 `AppStorageV2` 的响应式值，而是从播放器读取实时位置，避免定时器闭包中拿到旧值导致高亮滞后（见 `LyricView.ets` 第 92 行注释）。

### 3. 跨页面共享播放状态

播放页、迷你播放条、歌词面板需要共享当前歌曲与播放状态。项目使用状态管理 V2 的 `AppStorageV2.connect` 建立全局单例：

```typescript
playState: GlobalMusic = AppStorageV2.connect(GlobalMusic, 'SONG_KEY', () => new GlobalMusic())!
```

`GlobalMusic` 以 `@ObservedV2` 声明，内部字段以 `@Trace` 标记，实现跨组件自动更新。

### 4. 后台播控

`AvSessionManager.ets` 通过 `avSession.createAVSession(context, 'bgPlay', 'audio')` 创建媒体会话，将播放状态与歌曲元数据上报系统，支持控制中心与锁屏操作。

## 运行方式

1. DevEco Studio 5.1 及以上，安装 HarmonyOS SDK API 19
2. Clone 本仓库，用 DevEco Studio 打开根目录
3. `File → Project Structure → Signing Configs` 勾选自动签名（需登录华为开发者账号）
4. 选择模拟器或真机，运行 `entry` 模块

> 仓库不含签名材料与 `local.properties`，需在本地自行生成。构建产物 `build/`、`.hvigor/`、`oh_modules/` 已加入 `.gitignore`。

## 已知不足

- 列表使用 `ForEach` 全量渲染，未接入 `LazyForEach` 懒加载，数据量增大后需要改造
- 播放数据为本地 mock，未接入在线音乐接口
- 歌词面板的滚动跟随在快速拖动进度条时存在轻微延迟

## 后续计划

- [ ] 列表改造为 `LazyForEach` + `IDataSource`，补充滚动帧率实测数据
- [ ] 接入在线音乐接口，替换本地 mock 数据
- [ ] 增加歌单编辑与搜索联想
- [ ] 适配平板与折叠屏多端布局
