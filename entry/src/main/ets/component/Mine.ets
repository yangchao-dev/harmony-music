import { songs } from '../models/songData'
import { SongItemType } from '../models/music'
import { AppStorageV2 } from '@kit.ArkUI'
import { playerManager } from '../utils/AvPlayerManager'
import { PlayerState, getPlayerState } from '../models/PlayerState'
import { formatCount as formatCountText } from '../utils/Formatter'
import { toast } from '../utils/Toast'
import { resolveContext } from '../utils/ContextHelper'
import {
  UserStats,
  QuickEntry,
  PlaylistItem,
  ContentTab,
  DEFAULT_USER_STATS,
  QUICK_ENTRIES,
  CONTENT_TABS,
  createPlaylists,
  createCreatedPlaylists,
  createFavPlaylists
} from '../models/MineModels'
import {
  HistoryStore,
  LikedStore,
  PlaylistStore,
  SettingsStore,
  findSongsByIds,
  getHistoryStore,
  getLikedStore,
  getPlaylistStore,
  getSettingsStore,
  preferencesService
} from '../models/UserSettings'

@ComponentV2
export struct Mine {
  @Local userStats: UserStats = DEFAULT_USER_STATS

  // 用户偏好（昵称等，持久化在 PreferencesService）
  settings: SettingsStore = getSettingsStore()
  // 全局喜欢列表（与播放页红心共用）
  likedStore: LikedStore = getLikedStore()
  // 全局播放历史（最近播放数据源）
  historyStore: HistoryStore = getHistoryStore()
  // 歌单变更广播（其他页面「加入歌单」后自动刷新）
  playlistStore: PlaylistStore = getPlaylistStore()
  @Local playlistRevision: number = 0

  @Local badgeCount: number = 3
  @Local showBadgePanel: boolean = false  // 徽章面板
  @Local currentTab: number = 0
  @Local scrollY: number = 0
  @Local pressedRow: string = ''  // 当前按压的歌单行名称
  @Local isRefreshing: boolean = false  // 下拉刷新状态
  @Local imageLoadStatus: Record<string, boolean> = {}  // 图片加载状态
  @Local avatarScale: number = 1  // 头像缩放动画
  @Local avatarOpacity: number = 1  // 头像透明度动画
  @Local isEditProfileOpen: boolean = false  // 编辑资料弹窗
  @Local editNickname: string = ''  // 编辑中的昵称
  @Local isSortMode: boolean = false  // 歌单排序模式
  @Local headerHeight: number = 260  // 头部区域动态高度

  // 歌单名称输入弹窗（新建 / 重命名）
  @Local isPlaylistDialogOpen: boolean = false
  @Local playlistDialogTitle: string = ''
  @Local playlistDialogInput: string = ''
  private playlistDialogConfirm: ((name: string) => void) | null = null

  // 歌曲列表面板状态
  @Local isSongPanelOpen: boolean = false
  @Local currentPanelTitle: string = ''
  @Local currentPanelSongs: SongItemType[] = []

  pathStack: NavPathStack = AppStorageV2.connect(NavPathStack, 'navStack', () => new NavPathStack())!
  playState: PlayerState = getPlayerState()
  private scroller: Scroller = new Scroller()
  // 刷新模拟定时器 id
  private refreshTimer: number = -1
  // 头像点击动画定时器 id
  private avatarTimer: number = -1

  aboutToAppear(): void {
    // 恢复已创建的歌单（首次启动时把默认歌单落盘）
    preferencesService.init(resolveContext(this.getUIContext()))
      .then(() => {
        return preferencesService.loadPlaylists(this.createdPlaylists)
      })
      .then((list: PlaylistItem[]) => {
        this.createdPlaylists = list
      })
      .catch(() => {
        // 读取失败保持默认数据，不影响页面
      })
  }

  /** 其他页面修改歌单后，重新拉取磁盘数据 */
  @Monitor('playlistStore.revision')
  onPlaylistRevisionChange() {
    const revision = this.playlistStore.revision
    if (revision === this.playlistRevision) {
      return
    }
    this.playlistRevision = revision
    preferencesService.loadPlaylists(this.createdPlaylists).then((list: PlaylistItem[]) => {
      this.createdPlaylists = list
    })
  }

  aboutToDisappear(): void {
    // 组件销毁时清理所有定时器，避免回调访问已释放的组件状态
    if (this.refreshTimer !== -1) {
      clearTimeout(this.refreshTimer)
      this.refreshTimer = -1
    }
    if (this.avatarTimer !== -1) {
      clearTimeout(this.avatarTimer)
      this.avatarTimer = -1
    }
  }

  // 最近播放列表（基于持久化的播放历史，去重 + 时间倒序 Top5）
  private getRecentPlayList(): SongItemType[] {
    const list = this.getRecentAllSongs()
    return list.slice(0, 5)
  }

  // 最近播放完整列表（真实历史，按时间倒序去重）
  private getRecentAllSongs(): SongItemType[] {
    return findSongsByIds(this.historyStore.records.map(record => record.id))
  }

  // 「我喜欢的音乐」：直接由全局喜欢 id 列表计算，与播放页红心实时同步
  private getLikedSongs(): SongItemType[] {
    return findSongsByIds(this.likedStore.likedSongIds)
  }

  // 打开「我喜欢的音乐」面板
  openLikedPanel() {
    this.openSongPanel('我喜欢的音乐', this.getLikedSongs(), '还没有喜欢的歌曲，去播放页点红心吧')
  }

  // 保存歌单列表（增 / 删 / 改 / 排序后调用）
  private savePlaylists(): void {
    preferencesService.persistPlaylists(this.createdPlaylists)
  }

  // 新建歌单
  createPlaylist(name: string) {
    const value = name.trim()
    if (value.length === 0) {
      toast({ message: '歌单名不能为空', duration: 1000 })
      return
    }
    if (this.createdPlaylists.some(item => item.name === value)) {
      toast({ message: '已存在同名歌单', duration: 1000 })
      return
    }
    const item: PlaylistItem = {
      id: `pl_${Date.now()}`,
      name: value,
      count: 0,
      coverImg: '',
      songs: []
    }
    this.createdPlaylists = [...this.createdPlaylists, item]
    this.savePlaylists()
    toast({ message: '歌单创建成功', duration: 1000 })
  }

  // 重命名歌单
  renamePlaylist(target: PlaylistItem, name: string) {
    const value = name.trim()
    if (value.length === 0) {
      toast({ message: '歌单名不能为空', duration: 1000 })
      return
    }
    if (value === target.name) {
      return
    }
    if (this.createdPlaylists.some(item => item !== target && item.name === value)) {
      toast({ message: '已存在同名歌单', duration: 1000 })
      return
    }
    target.name = value
    this.createdPlaylists = [...this.createdPlaylists]
    this.savePlaylists()
    toast({ message: '重命名成功', duration: 1000 })
  }

  // 删除歌单
  deletePlaylist(target: PlaylistItem) {
    this.createdPlaylists = this.createdPlaylists.filter(item => item !== target)
    this.savePlaylists()
    toast({ message: '已删除歌单', duration: 1000 })
  }

  // 置顶 / 取消置顶（置顶项固定排在最前）
  togglePin(target: PlaylistItem) {
    target.showPin = !target.showPin
    const pinned = this.createdPlaylists.filter(item => item.showPin)
    const rest = this.createdPlaylists.filter(item => !item.showPin)
    this.createdPlaylists = [...pinned, ...rest]
    this.savePlaylists()
    toast({ message: target.showPin ? '已置顶' : '已取消置顶', duration: 1000 })
  }

  // 弹出歌单名称输入框（新建 / 重命名共用）
  openPlaylistNameDialog(title: string, initial: string, onConfirm: (name: string) => void) {
    this.playlistDialogTitle = title
    this.playlistDialogInput = initial
    this.playlistDialogConfirm = onConfirm
    this.isPlaylistDialogOpen = true
  }

  // 「最近播放」快捷入口（历史为空时提示）
  private getQuickRecentSongs(): SongItemType[] {
    const ids = this.historyStore.records.map(record => record.id)
    return findSongsByIds(ids)
  }

  // 快捷入口数据
  private quickEntries: QuickEntry[] = QUICK_ENTRIES

  // 内容Tab
  private contentTabs: ContentTab[] = CONTENT_TABS

  // 歌单列表（数据定义见 models/MineModels.ets）
  @Local playlists: PlaylistItem[] = createPlaylists()

  // 创建的歌单
  @Local createdPlaylists: PlaylistItem[] = createCreatedPlaylists()

  // 收藏的歌单
  @Local favPlaylists: PlaylistItem[] = createFavPlaylists()

  // 大数字格式化（实现见 utils/Formatter.ets）
  formatCount(count: number): string {
    return formatCountText(count)
  }

  // 打开歌曲列表面板
  openSongPanel(title: string, songs: SongItemType[], emptyTip: string = '暂无歌曲') {
    if (songs.length === 0) {
      toast({ message: emptyTip, duration: 1200 })
      return
    }
    this.currentPanelTitle = title
    this.currentPanelSongs = songs
    this.isSongPanelOpen = true
  }

  // 关闭歌曲列表面板
  closeSongPanel() {
    this.isSongPanelOpen = false
    this.currentPanelSongs = []
  }

  // 播放歌曲
  playSong(song: SongItemType) {
    playerManager.singPlay(song)
    this.closeSongPanel()
    this.pathStack.pushPathByName('Play', null, true)
  }

  // 播放全部
  playAllSongs() {
    if (this.currentPanelSongs.length > 0) {
      // 将歌单中所有歌曲添加到播放列表，然后播放第一首
      playerManager.playAllSongs(this.currentPanelSongs)
      this.closeSongPanel()
      this.pathStack.pushPathByName('Play', null, true)
    }
  }

  // 下拉刷新处理
  handleRefresh() {
    this.isRefreshing = true
    // 模拟刷新：更新听歌小时和听歌排行计数
    if (this.refreshTimer !== -1) {
      clearTimeout(this.refreshTimer)
    }
    this.refreshTimer = setTimeout(() => {
      this.refreshTimer = -1
      this.userStats.hours = Math.floor(Math.random() * 10) + 1
      const playCountItem = this.playlists.find(item => item.playCount !== undefined)
      if (playCountItem && playCountItem.playCount !== undefined) {
        playCountItem.playCount = playCountItem.playCount + Math.floor(Math.random() * 5)
      }
      this.isRefreshing = false
      toast({ message: '刷新成功', duration: 1000 })
    }, 1000)
  }

  // 歌单排序：上移（顺序落盘）
  movePlaylistUp(index: number) {
    if (index > 0) {
      // 置顶项固定在顶部，不参与排序
      if (this.createdPlaylists[index].showPin || this.createdPlaylists[index - 1].showPin) {
        return
      }
      const temp = this.createdPlaylists[index]
      this.createdPlaylists[index] = this.createdPlaylists[index - 1]
      this.createdPlaylists[index - 1] = temp
      this.createdPlaylists = [...this.createdPlaylists]  // 触发UI刷新
      this.savePlaylists()
    }
  }

  // 歌单排序：下移（顺序落盘）
  movePlaylistDown(index: number) {
    if (index < this.createdPlaylists.length - 1) {
      if (this.createdPlaylists[index].showPin || this.createdPlaylists[index + 1].showPin) {
        return
      }
      const temp = this.createdPlaylists[index]
      this.createdPlaylists[index] = this.createdPlaylists[index + 1]
      this.createdPlaylists[index + 1] = temp
      this.createdPlaylists = [...this.createdPlaylists]  // 触发UI刷新
      this.savePlaylists()
    }
  }

  // ========== Builders ==========

  // 顶部导航栏（滚动时透明度渐变）
  @Builder
  topNavBar() {
    Row() {
      Image($r('app.media.ic_list'))
        .width(24)
        .height(24)
        .fillColor(this.scrollY > 75 ? $r('app.color.nav_icon_dark') : $r('app.color.text_primary'))
        .onClick(() => {
          toast({ message: '菜单', duration: 1000 })
        })

      Stack() {
        Row({ space: 6 }) {
          Text('+ 添加状态')
            .fontSize(14)
            .fontColor(this.scrollY > 75 ? $r('app.color.text_disabled') : $r('app.color.text_primary'))
          Circle()
            .width(8)
            .height(8)
            .fill($r('app.color.brand_primary'))
        }
      }
      .layoutWeight(1)
      .alignContent(Alignment.Center)

      Row({ space: 18 }) {
        Image($r('app.media.ic_search'))
          .width(22)
          .height(22)
          .fillColor(this.scrollY > 75 ? $r('app.color.nav_icon_dark') : $r('app.color.text_primary'))
          .onClick(() => {
            toast({ message: '搜索', duration: 1000 })
          })
        Image($r('app.media.ic_more'))
          .width(22)
          .height(22)
          .fillColor(this.scrollY > 75 ? $r('app.color.nav_icon_dark') : $r('app.color.text_primary'))
          .onClick(() => {
            toast({ message: '设置', duration: 1000 })
          })
      }
    }
    .width('100%')
    .height(48)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(`rgba(19,19,19,${Math.min(1, Math.max(0, this.scrollY / 150))})`)
    .backdropBlur(this.scrollY > 0 ? 10 : 0)
  }

  // 用户统计项
  @Builder
  statItem(value: string, label: string) {
    Column({ space: 2 }) {
      Text(value)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
    }
    .layoutWeight(1)
    .onClick(() => {
      toast({ message: `${label}: ${value}`, duration: 1000 })
    })
  }

  // 快捷入口项
  @Builder
  quickEntryItem(entry: QuickEntry) {
    Column({ space: 8 }) {
      Column() {
        if (entry.label === '最近') {
          Image($r('app.media.ic_recommend'))
            .width(28)
            .height(28)
            .fillColor($r('app.color.text_secondary'))
        } else if (entry.label === '本地') {
          Image($r('app.media.ic_find'))
            .width(28)
            .height(28)
            .fillColor($r('app.color.text_secondary'))
        } else if (entry.label === 'VIP') {
          Image($r('app.media.ic_moment'))
            .width(28)
            .height(28)
            .fillColor($r('app.color.accent_gold_soft'))
        } else if (entry.label === '装扮') {
          Image($r('app.media.ic_code'))
            .width(28)
            .height(28)
            .fillColor($r('app.color.text_secondary'))
        } else {
          Image($r('app.media.ic_more'))
            .width(28)
            .height(28)
            .fillColor($r('app.color.text_secondary'))
        }
      }
      .width(48)
      .height(48)
      .borderRadius(24)
      .backgroundColor($r('app.color.bg_elevated'))
      .justifyContent(FlexAlign.Center)

      Text(entry.label)
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
    }
    .layoutWeight(1)
    .onClick(() => {
      if (entry.label === '最近') {
        this.openSongPanel('最近播放', this.getQuickRecentSongs())
      } else if (entry.label === '本地') {
        // 本地歌单 = 导入发现页所有歌曲
        this.openSongPanel('本地下载', [...songs])
      } else {
        toast({ message: `进入: ${entry.label}`, duration: 1000 })
      }
    })
  }

  // 内容Tab项 - 带动画过渡
  @Builder
  contentTabItem(tab: ContentTab, index: number) {
    Column({ space: 4 }) {
      Text(tab.label)
        .fontSize(16)
        .fontWeight(this.currentTab === index ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.currentTab === index ? $r('app.color.text_primary') : $r('app.color.text_quaternary'))
        .animation({ duration: 200, curve: Curve.EaseInOut })
      // Tab指示器 - 使用显式动画实现平滑过渡
      Column()
        .width(20)
        .height(3)
        .borderRadius(1.5)
        .backgroundColor(this.currentTab === index ? $r('app.color.brand_primary') : Color.Transparent)
        .animation({ duration: 300, curve: Curve.EaseInOut })
    }
    .padding({ left: 16, right: 16 })
    .onClick(() => {
      this.currentTab = index
    })
  }

  // 歌单列表项（竖向）- 支持长按菜单
  @Builder
  playlistRow(item: PlaylistItem) {
    Row({ space: 12 }) {
      // 封面区域
      if (item.isNew || item.isImport) {
        Column() {
          Image(item.isNew ? $r('app.media.ic_code') : $r('app.media.ic_find'))
            .width(24)
            .height(24)
            .fillColor($r('app.color.text_quaternary'))
        }
        .width(48)
        .height(48)
        .borderRadius(8)
        .border({ width: 1, color: $r('app.color.bg_elevated_hover'), style: BorderStyle.Dashed })
        .justifyContent(FlexAlign.Center)
      } else if (item.isLiked) {
        Column() {
          Text('♥')
            .fontSize(22)
            .fontColor(Color.White)
        }
        .width(48)
        .height(48)
        .borderRadius(8)
        .backgroundColor($r('app.color.brand_primary'))
        .justifyContent(FlexAlign.Center)
      } else if (item.playCount !== undefined) {
        Column() {
          Image($r('app.media.ic_moment'))
            .width(24)
            .height(24)
            .fillColor($r('app.color.text_tertiary'))
        }
        .width(48)
        .height(48)
        .borderRadius(8)
        .backgroundColor($r('app.color.bg_elevated'))
        .justifyContent(FlexAlign.Center)
      } else {
        Stack() {
          // 骨架屏占位（加载中）
          Column()
            .width(48)
            .height(48)
            .borderRadius(8)
            .backgroundColor($r('app.color.bg_elevated'))
            .justifyContent(FlexAlign.Center)
          Image($r('app.media.ic_moment'))
            .width(20)
            .height(20)
            .fillColor($r('app.color.icon_muted'))
            .visibility(!(this.imageLoadStatus[item.coverImg] ?? false) ? Visibility.Visible : Visibility.Hidden)

          Image(item.coverImg)
            .width(48)
            .height(48)
            .borderRadius(8)
            .objectFit(ImageFit.Cover)
            .visibility((this.imageLoadStatus[item.coverImg] ?? false) ? Visibility.Visible : Visibility.Hidden)
            .onComplete(() => {
              this.imageLoadStatus[item.coverImg] = true
            })
            .onError(() => {
              this.imageLoadStatus[item.coverImg] = true  // 加载失败也显示占位
            })
        }
      }

      // 文字信息
      Column({ space: 4 }) {
        Row({ space: 6 }) {
          Text(item.name)
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (item.isNew) {
            Text('NEW')
              .fontSize(10)
              .fontColor(Color.White)
              .padding({ left: 4, right: 4, top: 1, bottom: 1 })
              .backgroundColor($r('app.color.brand_primary'))
              .borderRadius(3)
          }
        }

        Row({ space: 6 }) {
          if (item.playCount !== undefined) {
            Text(`累计听歌${item.playCount}首`)
              .fontSize(12)
              .fontColor($r('app.color.text_quaternary'))
          } else if (item.isLiked) {
            // 喜欢数量实时跟随全局喜欢列表
            Text(`${this.likedStore.likedSongIds.length}首`)
              .fontSize(12)
              .fontColor($r('app.color.text_quaternary'))
          } else if (item.count > 0) {
            Text(`${item.count}首`)
              .fontSize(12)
              .fontColor($r('app.color.text_quaternary'))
          }
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 右侧操作区
      Row({ space: 12 }) {
        if (item.showPin && this.canManage(item)) {
          Text('不置顶')
            .fontSize(12)
            .fontColor($r('app.color.text_quaternary'))
            .onClick(() => {
              this.togglePin(item)
            })
        }
        if (!item.isNew && !item.isImport) {
          Image($r('app.media.ic_more'))
            .width(18)
            .height(18)
            .fillColor($r('app.color.text_faint'))
        }
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(this.pressedRow === item.name ? $r('app.color.overlay_light') : Color.Transparent)
    .animation({ duration: 150 })
    .onClick(() => {
      if (item.isNew) {
        // 新建歌单：输入名称后真正创建并落盘
        this.openPlaylistNameDialog('新建歌单', '', (name: string) => {
          this.createPlaylist(name)
        })
      } else if (item.isImport) {
        this.openSongPanel('导入外部歌单', [...songs])
      } else if (item.isLiked) {
        // 我喜欢的音乐：与播放页红心共用同一份数据
        this.openLikedPanel()
      } else if (item.playCount !== undefined) {
        this.openSongPanel('听歌排行', this.getRecentAllSongs())
      } else if (item.songs && item.songs.length > 0) {
        this.openSongPanel(item.name, item.songs)
      } else {
        toast({ message: `${item.name}暂无歌曲`, duration: 1000 })
      }
    })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressedRow = item.name
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressedRow = ''
      }
    })
    .bindContextMenu(this.playlistContextMenu(item), ResponseType.LongPress)
  }

  // 歌单长按菜单（仅用户创建的歌单可管理，修改会真正落盘）
  @Builder
  playlistContextMenu(item: PlaylistItem) {
    Menu() {
      if (this.canManage(item)) {
        MenuItem({ content: item.showPin ? '取消置顶' : '置顶' })
          .onClick(() => {
            this.togglePin(item)
          })
        MenuItem({ content: '重命名' })
          .onClick(() => {
            this.openPlaylistNameDialog('重命名歌单', item.name, (name: string) => {
              this.renamePlaylist(item, name)
            })
          })
        MenuItem({ content: '删除' })
          .onClick(() => {
            this.deletePlaylist(item)
          })
      } else {
        MenuItem({ content: '查看歌曲' })
          .onClick(() => {
            this.openSongPanel(item.name, item.songs)
          })
      }
    }
  }

  // 是否可管理（置顶/重命名/删除）：只有用户创建且有 id 的歌单
  private canManage(item: PlaylistItem): boolean {
    return !!item.id && this.createdPlaylists.includes(item)
  }

  // 区域标题栏
  @Builder
  sectionHeader(title: string) {
    Row() {
      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Blank()
      Row({ space: 4 }) {
        Image($r('app.media.ic_share'))
          .width(18)
          .height(18)
          .fillColor($r('app.color.text_quaternary'))
        Image($r('app.media.ic_more'))
          .width(18)
          .height(18)
          .fillColor($r('app.color.text_quaternary'))
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 8 })
  }

  // 最近播放空状态（无播放历史时展示）
  @Builder
  recentEmptyPlaceholder() {
    Column({ space: 6 }) {
      Text('还没有播放记录')
        .fontSize(13)
        .fontColor($r('app.color.text_disabled'))
      Text('去发现页听几首歌吧~')
        .fontSize(11)
        .fontColor($r('app.color.text_faint'))
    }
    .height(90)
    .padding({ left: 4, right: 20 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
  }

  // 最近播放歌曲项（横向滚动）
  @Builder
  recentSongItem(song: SongItemType) {
    Column({ space: 6 }) {
      Stack() {
        // 骨架屏占位
        Column()
          .width(55)
          .height(55)
          .borderRadius(6)
          .backgroundColor($r('app.color.bg_elevated'))
          .justifyContent(FlexAlign.Center)
        Image($r('app.media.ic_moment'))
          .width(20)
          .height(20)
          .fillColor($r('app.color.icon_muted'))
          .visibility(!(this.imageLoadStatus[song.img] ?? false) ? Visibility.Visible : Visibility.Hidden)

        Image(song.img)
          .width(55)
          .height(55)
          .borderRadius(6)
          .objectFit(ImageFit.Cover)
          .visibility((this.imageLoadStatus[song.img] ?? false) ? Visibility.Visible : Visibility.Hidden)
          .onComplete(() => {
            this.imageLoadStatus[song.img] = true
          })
          .onError(() => {
            this.imageLoadStatus[song.img] = true
          })

        if (this.playState.url === song.url && this.playState.isPlay) {
          Column()
            .width(55)
            .height(55)
            .borderRadius(6)
            .backgroundColor($r('app.color.overlay_dark_40'))
            .justifyContent(FlexAlign.Center)
          Image($r('app.media.wave'))
            .width(22)
            .height(22)
        }
      }
      Text(song.name)
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width(55)
    }
    .margin({ right: 14 })
    .opacity(this.pressedRow === `song_${song.id}` ? 0.7 : 1)
    .animation({ duration: 150 })
    .onClick(() => {
      playerManager.singPlay(song)
      this.pathStack.pushPathByName('Play', null, true)
    })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressedRow = `song_${song.id}`
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressedRow = ''
      }
    })
  }

  // ========== 歌曲列表面板 ==========
  @Builder
  songPanel() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 半透明遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.overlay_dark_50'))
        .onClick(() => {
          this.closeSongPanel()
        })

      // 面板内容
      Column() {
        // 面板头部
        Row() {
          Text(this.currentPanelTitle)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)

          // 播放全部按钮
          Button('播放全部')
            .fontSize(13)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.brand_primary'))
            .borderRadius(16)
            .height(32)
            .padding({ left: 14, right: 14 })
            .onClick(() => {
              this.playAllSongs()
            })

          Image($r('app.media.ic_close'))
            .width(22)
            .height(22)
            .fillColor($r('app.color.text_quaternary'))
            .margin({ left: 12 })
            .onClick(() => {
              this.closeSongPanel()
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 12 })
        .border({ width: { bottom: 0.5 }, color: $r('app.color.bg_elevated') })

        // 歌曲列表
        List({ space: 0 }) {
          ForEach(this.currentPanelSongs, (song: SongItemType, index: number) => {
            ListItem() {
              Row({ space: 12 }) {
                // 序号
                Text((index + 1).toString().padStart(2, '0'))
                  .fontSize(16)
                  .fontColor(this.playState.url === song.url && this.playState.isPlay ? $r('app.color.brand_primary') : $r('app.color.text_quaternary'))
                  .fontWeight(this.playState.url === song.url && this.playState.isPlay ? FontWeight.Bold : FontWeight.Normal)
                  .width(30)

                // 封面
                Stack() {
                  // 骨架屏占位
                  Column()
                    .width(44)
                    .height(44)
                    .borderRadius(6)
                    .backgroundColor($r('app.color.bg_elevated'))
                    .justifyContent(FlexAlign.Center)
                  Image($r('app.media.ic_moment'))
                    .width(18)
                    .height(18)
                    .fillColor($r('app.color.icon_muted'))
                    .visibility(!(this.imageLoadStatus[song.img] ?? false) ? Visibility.Visible : Visibility.Hidden)

                  Image(song.img)
                    .width(44)
                    .height(44)
                    .borderRadius(6)
                    .objectFit(ImageFit.Cover)
                    .visibility((this.imageLoadStatus[song.img] ?? false) ? Visibility.Visible : Visibility.Hidden)
                    .onComplete(() => {
                      this.imageLoadStatus[song.img] = true
                    })
                    .onError(() => {
                      this.imageLoadStatus[song.img] = true
                    })

                  if (this.playState.url === song.url && this.playState.isPlay) {
                    Column()
                      .width(44)
                      .height(44)
                      .borderRadius(6)
                      .backgroundColor($r('app.color.overlay_dark_30'))
                      .justifyContent(FlexAlign.Center)
                    Image($r('app.media.wave'))
                      .width(18)
                      .height(18)
                  }
                }

                // 歌曲信息
                Column({ space: 4 }) {
                  Text(song.name)
                    .fontSize(15)
                    .fontColor(this.playState.url === song.url && this.playState.isPlay ? $r('app.color.brand_primary') : $r('app.color.text_primary'))
                    .fontWeight(FontWeight.Medium)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(song.author)
                    .fontSize(12)
                    .fontColor($r('app.color.text_quaternary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                // 更多按钮
                Image($r('app.media.ic_more'))
                  .width(18)
                  .height(18)
                  .fillColor($r('app.color.text_faint'))
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              .backgroundColor(this.pressedRow === `panel_${index}` ? $r('app.color.overlay_light') : Color.Transparent)
              .animation({ duration: 150 })
              .onClick(() => {
                this.playSong(song)
              })
              .onTouch((event: TouchEvent) => {
                if (event.type === TouchType.Down) {
                  this.pressedRow = `panel_${index}`
                } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                  this.pressedRow = ''
                }
              })
            }
          }, (song: SongItemType, index: number) => `${song.id}_${index}`)

          // 底部留白
          ListItem() {
            Column()
              .height(30)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('70%')
      .backgroundColor($r('app.color.bg_panel'))
      .borderRadius({ topLeft: 16, topRight: 16 })
      .transition(TransitionEffect.translate({ y: 600 }).animation({ duration: 300, curve: Curve.EaseOut }))
    }
    .width('100%')
    .height('100%')
    .position({ x: 0, y: 0 })
    .transition(TransitionEffect.OPACITY.animation({ duration: 300 }))
  }

  // ========== 编辑资料弹窗 ==========
  @Builder
  editProfileDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.overlay_dark_50'))
        .onClick(() => {
          this.isEditProfileOpen = false
        })

      Column({ space: 20 }) {
        Text('编辑资料')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))

        // 头像预览
        Image($r('app.media.QQp5'))
          .width(80)
          .height(80)
          .borderRadius(40)
          .border({ width: 3, color: $r('app.color.text_primary') })

        // 昵称编辑
        TextInput({ text: $$this.editNickname, placeholder: '请输入昵称' })
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_quaternary'))
          .backgroundColor($r('app.color.bg_elevated'))
          .borderRadius(8)
          .padding({ left: 12, right: 12 })
          .height(44)
          .width('100%')

        // 按钮
        Row({ space: 16 }) {
          Button('取消')
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.bg_elevated_hover'))
            .borderRadius(20)
            .layoutWeight(1)
            .height(40)
            .onClick(() => {
              this.isEditProfileOpen = false
            })

          Button('保存')
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.brand_primary'))
            .borderRadius(20)
            .layoutWeight(1)
            .height(40)
            .onClick(() => {
              if (this.editNickname.trim().length === 0) {
                toast({ message: '昵称不能为空', duration: 1000 })
                return
              }
              // 昵称落盘，重启后保留
              preferencesService.setNickname(this.editNickname)
              this.isEditProfileOpen = false
              toast({ message: '保存成功', duration: 1000 })
            })
        }
        .width('100%')
      }
      .width('80%')
      .padding(24)
      .backgroundColor($r('app.color.bg_panel'))
      .borderRadius(16)
    }
    .width('100%')
    .height('100%')
    .position({ x: 0, y: 0 })
    .transition(TransitionEffect.OPACITY.animation({ duration: 300 }))
  }

  // ========== 歌单名称输入弹窗（新建 / 重命名） ==========
  @Builder
  playlistNameDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.overlay_dark_50'))
        .onClick(() => {
          this.isPlaylistDialogOpen = false
        })

      Column({ space: 20 }) {
        Text(this.playlistDialogTitle)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))

        TextInput({ text: $$this.playlistDialogInput, placeholder: '请输入歌单名称' })
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_quaternary'))
          .backgroundColor($r('app.color.bg_elevated'))
          .borderRadius(8)
          .padding({ left: 12, right: 12 })
          .height(44)
          .width('100%')
          .maxLength(30)

        Row({ space: 16 }) {
          Button('取消')
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.bg_elevated_hover'))
            .borderRadius(20)
            .layoutWeight(1)
            .height(40)
            .onClick(() => {
              this.isPlaylistDialogOpen = false
            })

          Button('确定')
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.brand_primary'))
            .borderRadius(20)
            .layoutWeight(1)
            .height(40)
            .onClick(() => {
              const name = this.playlistDialogInput.trim()
              if (name.length === 0) {
                toast({ message: '歌单名不能为空', duration: 1000 })
                return
              }
              this.isPlaylistDialogOpen = false
              const confirm = this.playlistDialogConfirm
              this.playlistDialogConfirm = null
              if (confirm) {
                confirm(name)
              }
            })
        }
        .width('100%')
      }
      .width('80%')
      .padding(24)
      .backgroundColor($r('app.color.bg_panel'))
      .borderRadius(16)
    }
    .width('100%')
    .height('100%')
    .position({ x: 0, y: 0 })
    .transition(TransitionEffect.OPACITY.animation({ duration: 300 }))
  }

  // ========== 徽章面板 ==========
  @Builder
  badgePanel() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.overlay_dark_50'))
        .onClick(() => {
          this.showBadgePanel = false
        })

      Column({ space: 20 }) {
        // 头部
        Row() {
          Text('我的徽章')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          Image($r('app.media.ic_close'))
            .width(22)
            .height(22)
            .fillColor($r('app.color.text_quaternary'))
            .onClick(() => {
              this.showBadgePanel = false
            })
        }
        .width('100%')

        // 徽章网格
        Grid() {
          GridItem() {
            this.badgeItem('🎵', '音乐达人', '累计听歌100首', this.userStats.hours >= 5)
          }
          GridItem() {
            this.badgeItem('⭐', '收藏家', '收藏10个歌单', this.favPlaylists.length >= 3)
          }
          GridItem() {
            this.badgeItem('🔥', '活跃用户', '连续登录7天', this.userStats.level >= 3)
          }
          GridItem() {
            this.badgeItem('👑', 'VIP会员', '开通VIP', true)
          }
          GridItem() {
            this.badgeItem('🎸', '摇滚达人', '听摇滚100首', false)
          }
          GridItem() {
            this.badgeItem('🌙', '夜猫子', '凌晨听歌30次', false)
          }
        }
        .columnsTemplate('1fr 1fr 1fr')
        .columnsGap(12)
        .rowsGap(12)
        .width('100%')
        .height(200)
      }
      .width('85%')
      .padding(24)
      .backgroundColor($r('app.color.bg_panel'))
      .borderRadius(16)
    }
    .width('100%')
    .height('100%')
    .position({ x: 0, y: 0 })
    .transition(TransitionEffect.OPACITY.animation({ duration: 300 }))
  }

  // 徽章项
  @Builder
  badgeItem(icon: string, name: string, desc: string, obtained: boolean) {
    Column({ space: 8 }) {
      Text(icon)
        .fontSize(32)
        .opacity(obtained ? 1 : 0.3)
      Text(name)
        .fontSize(12)
        .fontColor(obtained ? $r('app.color.text_primary') : $r('app.color.text_disabled'))
        .fontWeight(FontWeight.Medium)
      Text(desc)
        .fontSize(10)
        .fontColor($r('app.color.text_disabled'))
        .maxLines(2)
        .textAlign(TextAlign.Center)
      if (obtained) {
        Text('已获得')
          .fontSize(10)
          .fontColor($r('app.color.accent_gold'))
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .border({ width: 0.5, color: $r('app.color.accent_gold'), radius: 8 })
      }
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(obtained ? $r('app.color.bg_badge_obtained') : $r('app.color.bg_section'))
    .borderRadius(10)
    .border({ width: 0.5, color: obtained ? $r('app.color.accent_gold') : $r('app.color.bg_elevated') })
  }

  // ========== 主 Build ==========
  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Refresh({ refreshing: $$this.isRefreshing }) {
        Scroll(this.scroller) {
          Column() {
            // ========== 0. 背景图 + 导航栏 + 头部区域 ==========
            Stack({ alignContent: Alignment.TopStart }) {
              // 背景图（底层）
              Image($r('app.media.mine_bg'))
                .width('100%')
                .height(this.headerHeight + 48 + Math.max(0, -this.scrollY))
                .objectFit(ImageFit.Cover)

              Column() {
                // 导航栏
                this.topNavBar()

                // 用户头部区域（可收起）
                Stack({ alignContent: Alignment.Bottom }) {
                  // 透明占位
                  Column()
                    .width('100%')
                    .height(this.headerHeight + Math.max(0, -this.scrollY))

                  Column({ space: 10 }) {
                    // 头像和昵称随滚动缩小
                    Image($r('app.media.QQp5'))
                      .width(72 * Math.min(1, this.headerHeight / 260))
                      .height(72 * Math.min(1, this.headerHeight / 260))
                      .borderRadius(36)
                      .border({ width: 2, color: $r('app.color.text_primary') })
                      .shadow({ radius: 8, color: 'rgba(0,0,0,0.15)', offsetX: 0, offsetY: 2 })
                      .scale({ x: this.avatarScale, y: this.avatarScale })
                      .opacity(Math.min(1, this.headerHeight / 120) * this.avatarOpacity)
                      .animation({ duration: 200, curve: Curve.EaseInOut })
                      .onClick(() => {
                        this.avatarScale = 0.9
                        this.avatarOpacity = 0.8
                        if (this.avatarTimer !== -1) {
                          clearTimeout(this.avatarTimer)
                        }
                        this.avatarTimer = setTimeout(() => {
                          this.avatarTimer = -1
                          this.avatarScale = 1
                          this.avatarOpacity = 1
                        }, 150)
                        this.editNickname = this.settings.nickname
                        this.isEditProfileOpen = true
                      })

                    // 昵称行（滚到一定程度后隐藏）
                    if (this.headerHeight > 80) {
                      Column({ space: 6 }) {
                        Row({ space: 6 }) {
                          Text(this.settings.nickname)
                            .fontSize(18)
                            .fontWeight(FontWeight.Bold)
                            .fontColor($r('app.color.text_primary'))
                          Text('P+')
                            .fontSize(10)
                            .fontColor($r('app.color.text_primary'))
                            .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                            .backgroundColor($r('app.color.brand_primary_light'))
                            .borderRadius(4)
                          Image($r('app.media.ic_more'))
                            .width(14)
                            .height(14)
                            .fillColor($r('app.color.text_primary'))
                        }
                      }
                      .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
                    }

                    // 徽章行
                    if (this.headerHeight > 100) {
                      Row({ space: 4 }) {
                        Image($r('app.media.ic_moment'))
                          .width(16)
                          .height(16)
                          .fillColor($r('app.color.accent_gold'))
                        Text(`${this.badgeCount}枚徽章`)
                          .fontSize(13)
                          .fontColor($r('app.color.text_primary'))
                        Image($r('app.media.ic_more'))
                          .width(12)
                          .height(12)
                          .fillColor($r('app.color.text_primary'))
                      }
                      .onClick(() => {
                        this.showBadgePanel = true
                      })
                      .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
                    }

                    // 统计行
                    if (this.headerHeight > 130) {
                      Row() {
                        this.statItem(this.userStats.follows.toString(), '关注')
                        Divider()
                          .vertical(true)
                          .strokeWidth(0.5)
                          .color($r('app.color.divider_white_30'))
                          .height(20)
                        this.statItem(this.userStats.fans.toString(), '粉丝')
                        Divider()
                          .vertical(true)
                          .strokeWidth(0.5)
                          .color($r('app.color.divider_white_30'))
                          .height(20)
                        this.statItem(`Lv.${this.userStats.level}`, '等级')
                        Divider()
                          .vertical(true)
                          .strokeWidth(0.5)
                          .color($r('app.color.divider_white_30'))
                          .height(20)
                        this.statItem(`${this.userStats.hours} 小时`, '听歌')
                      }
                      .width('75%')
                      .justifyContent(FlexAlign.SpaceAround)
                      .margin({ top: 4 })
                      .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
                    }
                  }
                  .alignItems(HorizontalAlign.Center)
                  .margin({ bottom: 16 })
                }
                .width('100%')
                .height(this.headerHeight + Math.max(0, -this.scrollY))
              }
            }
            .width('100%')

            // ========== 3. 快捷功能入口 ==========
            Row() {
              ForEach(this.quickEntries, (entry: QuickEntry) => {
                this.quickEntryItem(entry)
              }, (entry: QuickEntry) => entry.label)
            }
            .width('100%')
            .padding({ left: 8, right: 8, top: 16, bottom: 12 })
            .backgroundColor($r('app.color.bg_section'))

            // 分隔
            Column()
              .width('100%')
              .height(8)
              .backgroundColor($r('app.color.bg_gap'))

            // ========== 4. 内容Tab切换 ==========
            Row() {
              ForEach(this.contentTabs, (tab: ContentTab, index: number) => {
                this.contentTabItem(tab, index)
              }, (tab: ContentTab) => tab.label)
              Blank()
            }
            .width('100%')
            .padding({ top: 12, bottom: 4 })
            .backgroundColor($r('app.color.bg_section'))

            Divider()
              .strokeWidth(0.5)
              .color($r('app.color.bg_elevated'))
              .width('100%')

            // ========== 5. 歌单区域标题 ==========
            Row() {
              Text('近期')
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .padding({ left: 16, top: 12, bottom: 8 })
              Text('创建¹')
                .fontSize(12)
                .fontColor($r('app.color.text_quaternary'))
                .padding({ top: 12, bottom: 8 })
              Blank()
              Row({ space: 12 }) {
                // 排序模式切换
                Text(this.isSortMode ? '完成' : '排序')
                  .fontSize(13)
                  .fontColor(this.isSortMode ? $r('app.color.brand_primary') : $r('app.color.text_quaternary'))
                  .onClick(() => {
                    this.isSortMode = !this.isSortMode
                  })
                Image($r('app.media.ic_share'))
                  .width(18)
                  .height(18)
                  .fillColor($r('app.color.text_quaternary'))
                Image($r('app.media.ic_more'))
                  .width(18)
                  .height(18)
                  .fillColor($r('app.color.text_quaternary'))
                  .margin({ right: 16 })
              }
            }
            .width('100%')
            .backgroundColor($r('app.color.bg_section'))

            // ========== 6. 歌单列表（竖向） ==========
            Column() {
              ForEach(this.playlists, (item: PlaylistItem) => {
                this.playlistRow(item)
              }, (item: PlaylistItem) => item.name)

              Divider()
                .strokeWidth(0.5)
                .color($r('app.color.bg_elevated'))
                .margin({ left: 16, right: 16 })

              if (this.createdPlaylists.length > 0) {
                ForEach(this.createdPlaylists, (item: PlaylistItem, index: number) => {
                  Row() {
                    Column() {
                      this.playlistRow(item)
                    }
                    .layoutWeight(1)

                    // 排序模式下显示上移/下移按钮
                    if (this.isSortMode) {
                      Column({ space: 4 }) {
                        Image($r('app.media.ic_share'))
                          .width(16)
                          .height(16)
                          .fillColor(index > 0 ? $r('app.color.text_quaternary') : $r('app.color.icon_muted'))
                          .rotate({ angle: -90 })
                          .onClick(() => {
                            this.movePlaylistUp(index)
                          })
                        Image($r('app.media.ic_share'))
                          .width(16)
                          .height(16)
                          .fillColor(index < this.createdPlaylists.length - 1 ? $r('app.color.text_quaternary') : $r('app.color.icon_muted'))
                          .rotate({ angle: 90 })
                          .onClick(() => {
                            this.movePlaylistDown(index)
                          })
                      }
                      .padding({ right: 12 })
                      .animation({ duration: 200 })
                    }
                  }
                  .width('100%')
                }, (item: PlaylistItem) => item.name)
              } else {
                // 空状态提示
                Column({ space: 8 }) {
                  Image($r('app.media.ic_code'))
                    .width(40)
                    .height(40)
                    .fillColor($r('app.color.icon_muted'))
                    .opacity(0.5)
                  Text('还没有创建歌单')
                    .fontSize(14)
                    .fontColor($r('app.color.text_disabled'))
                  Text('点击上方"新建歌单"开始创建')
                    .fontSize(12)
                    .fontColor($r('app.color.text_faint'))
                }
                .width('100%')
                .padding({ top: 24, bottom: 24 })
                .alignItems(HorizontalAlign.Center)
              }
            }
            .width('100%')
            .backgroundColor($r('app.color.bg_section'))

            // 分隔
            Column()
              .width('100%')
              .height(8)
              .backgroundColor($r('app.color.bg_gap'))

            // ========== 7. 收藏歌单 ==========
            this.sectionHeader('收藏歌单')

            Column() {
              if (this.favPlaylists.length > 0) {
                ForEach(this.favPlaylists, (item: PlaylistItem) => {
                  this.playlistRow(item)
                }, (item: PlaylistItem) => item.name)
              } else {
                // 空状态提示
                Column({ space: 8 }) {
                  Image($r('app.media.ic_moment'))
                    .width(40)
                    .height(40)
                    .fillColor($r('app.color.icon_muted'))
                    .opacity(0.5)
                  Text('还没有收藏歌单')
                    .fontSize(14)
                    .fontColor($r('app.color.text_disabled'))
                  Text('去发现页看看吧~')
                    .fontSize(12)
                    .fontColor($r('app.color.text_faint'))
                }
                .width('100%')
                .padding({ top: 30, bottom: 30 })
                .alignItems(HorizontalAlign.Center)
              }
            }
            .width('100%')
            .backgroundColor($r('app.color.bg_section'))

            // 分隔
            Column()
              .width('100%')
              .height(8)
              .backgroundColor($r('app.color.bg_gap'))

            // ========== 8. 最近播放 ==========
            Column() {
              Row() {
                Text('最近播放')
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))
                  .layoutWeight(1)
                Row({ space: 4 }) {
                  Text('全部')
                    .fontSize(13)
                    .fontColor($r('app.color.text_quaternary'))
                  Image($r('app.media.ic_more'))
                    .width(14)
                    .height(14)
                    .fillColor($r('app.color.text_quaternary'))
                }
                .onClick(() => {
                  this.openSongPanel('最近播放', this.getRecentAllSongs(), '还没有播放记录，去听听歌吧~')
                })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 16, bottom: 10 })

              Scroll() {
                Row() {
                  if (this.historyStore.records.length === 0) {
                    this.recentEmptyPlaceholder()
                  }
                  // 播放全部入口
                  Column({ space: 6 }) {
                    Column() {
                      Image($r('app.media.wave'))
                        .width(28)
                        .height(28)
                        .fillColor($r('app.color.brand_primary'))
                    }
                    .width(55)
                    .height(55)
                    .borderRadius(6)
                    .backgroundColor($r('app.color.bg_recent_playall'))
                    .justifyContent(FlexAlign.Center)
                    Text('播放全部')
                      .fontSize(11)
                      .fontColor($r('app.color.brand_primary'))
                      .maxLines(1)
                      .width(55)
                  }
                  .margin({ right: 14 })
                  .opacity(this.pressedRow === 'playAllRecent' ? 0.7 : 1)
                  .animation({ duration: 150 })
                  .onClick(() => {
                    const allSongs = this.getRecentAllSongs()
                    if (allSongs.length > 0) {
                      playerManager.singPlay(allSongs[0])
                      this.pathStack.pushPathByName('Play', null, true)
                    }
                  })
                  .onTouch((event: TouchEvent) => {
                    if (event.type === TouchType.Down) {
                      this.pressedRow = 'playAllRecent'
                    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                      this.pressedRow = ''
                    }
                  })

                  ForEach(this.getRecentPlayList(), (song: SongItemType) => {
                    this.recentSongItem(song)
                  }, (song: SongItemType) => song.id)
                }
                .padding({ left: 16 })
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              .width('100%')
              .height(90)
            }
            .width('100%')
            .backgroundColor($r('app.color.bg_section'))

            // 底部留白
            Column()
              .height(70)
              .backgroundColor($r('app.color.bg_section'))
          }
          .width('100%')
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .backgroundColor($r('app.color.bg_page'))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        // onScroll 自 API 12 起废弃，改用 onDidScroll（滚动完成回调）
        .onDidScroll(() => {
          this.scrollY = this.scroller.currentOffset().yOffset
          // 滚动时头部区域逐渐收起，最小保留48（导航栏高度）
          this.headerHeight = Math.max(48, 260 - this.scrollY)
        })
      }
      .refreshOffset(64)
      .onRefreshing(() => {
        this.handleRefresh()
      })
      .backgroundColor($r('app.color.bg_page'))

      // ========== 9. 歌曲列表面板（弹出层） ==========
      if (this.isSongPanelOpen) {
        this.songPanel()
      }

      // ========== 10. 编辑资料弹窗 ==========
      if (this.isEditProfileOpen) {
        this.editProfileDialog()
      }

      // ========== 10.1 歌单名称弹窗 ==========
      if (this.isPlaylistDialogOpen) {
        this.playlistNameDialog()
      }

      // ========== 11. 徽章面板 ==========
      if (this.showBadgePanel) {
        this.badgePanel()
      }
    }
    .width('100%')
    .height('100%')
  }
}