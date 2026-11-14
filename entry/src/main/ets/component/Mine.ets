import { songs } from '../models/songData'
import { SongItemType } from '../models/music'
import { AppStorageV2, promptAction } from '@kit.ArkUI'
import { playerManager } from '../utils/AvPlayerManager'
import { GlobalMusic } from '../models/globalMusic'

// 用户统计数据接口
interface UserStats {
  follows: number
  fans: number
  level: number
  hours: number
}

// 快捷入口接口
interface QuickEntry {
  icon: string
  label: string
}

// 歌单列表项接口
interface PlaylistItem {
  name: string
  count: number
  coverImg: string
  songs: SongItemType[]    // 歌单内的歌曲列表
  isLiked?: boolean
  isNew?: boolean
  isImport?: boolean
  showPin?: boolean
  playCount?: number
  isRecent?: boolean       // 是否"最近播放"入口
  isLocal?: boolean        // 是否"本地下载"入口
}

// 内容Tab接口
interface ContentTab {
  label: string
}

@Component
export struct Mine {
  @State userStats: UserStats = {
    follows: 1,
    fans: 1,
    level: 3,
    hours: 3
  }

  @State nickname: string = '爱丁堡随性春卷'
  @State badgeCount: number = 3
  @State showBadgePanel: boolean = false  // 徽章面板
  @State currentTab: number = 0
  @State scrollY: number = 0
  @State pressedRow: string = ''  // 当前按压的歌单行名称
  @State isRefreshing: boolean = false  // 下拉刷新状态
  @State imageLoadStatus: Record<string, boolean> = {}  // 图片加载状态
  @State avatarScale: number = 1  // 头像缩放动画
  @State avatarOpacity: number = 1  // 头像透明度动画
  @State isEditProfileOpen: boolean = false  // 编辑资料弹窗
  @State editNickname: string = ''  // 编辑中的昵称
  @State isSortMode: boolean = false  // 歌单排序模式
  @State headerHeight: number = 260  // 头部区域动态高度

  // 歌曲列表面板状态
  @State isSongPanelOpen: boolean = false
  @State currentPanelTitle: string = ''
  @State currentPanelSongs: SongItemType[] = []

  pathStack: NavPathStack = AppStorageV2.connect(NavPathStack, 'navStack', () => new NavPathStack())!
  playState: GlobalMusic = AppStorageV2.connect(GlobalMusic, 'SONG_KEY', () => new GlobalMusic())!
  private scroller: Scroller = new Scroller()

  // 最近播放列表（基于全局播放历史）
  private getRecentPlayList(): SongItemType[] {
    const list = this.playState.playList.length > 0 ? this.playState.playList : songs
    return list.slice(0, 5)
  }

  // 最近播放完整列表
  private getRecentAllSongs(): SongItemType[] {
    return this.playState.playList.length > 0 ? this.playState.playList : songs
  }

  // 快捷入口数据
  private quickEntries: QuickEntry[] = [
    { icon: '\ue600', label: '最近' },
    { icon: '\ue601', label: '本地' },
    { icon: '\ue602', label: 'VIP' },
    { icon: '\ue603', label: '装扮' },
    { icon: '\ue604', label: '更多' },
  ]

  // 内容Tab
  private contentTabs: ContentTab[] = [
    { label: '音乐' },
    { label: '播客' },
    { label: '笔记' },
  ]

  // 歌单列表
  @State playlists: PlaylistItem[] = [
    {
      name: '我喜欢的音乐',
      count: 3,
      coverImg: 'http://yjy-teach-oss.oss-cn-beijing.aliyuncs.com/HeimaCloudMusic/1.jpg',
      songs: [songs[0], songs[6], songs[14]], // 画、孤独、海阔天空
      isLiked: true
    },
    {
      name: '听歌排行',
      count: 0,
      coverImg: '',
      songs: [],
      playCount: 75,
      showPin: true
    },
    {
      name: '新建歌单',
      count: 0,
      coverImg: '',
      songs: [],
      isNew: true
    },
    {
      name: '导入外部歌单',
      count: 0,
      coverImg: '',
      songs: [],
      isImport: true
    },
  ]

  // 创建的歌单
  @State createdPlaylists: PlaylistItem[] = [
    {
      name: '经典华语老歌',
      count: 5,
      coverImg: 'http://yjy-teach-oss.oss-cn-beijing.aliyuncs.com/HeimaCloudMusic/9.jpg',
      songs: [songs[8], songs[11], songs[12], songs[13], songs[14]] // 倩女幽魂、一生所爱、月半小夜曲、Rolling in the Deep、海阔天空
    },
    {
      name: '睡前轻音乐',
      count: 4,
      coverImg: 'http://yjy-teach-oss.oss-cn-beijing.aliyuncs.com/HeimaCloudMusic/2.jpg',
      songs: [songs[0], songs[1], songs[6], songs[9]] // 画、Sweet Dreams、孤独、北京北京
    },
  ]

  // 收藏的歌单
  @State favPlaylists: PlaylistItem[] = [
    {
      name: '欧美热门精选',
      count: 4,
      coverImg: 'http://yjy-teach-oss.oss-cn-beijing.aliyuncs.com/HeimaCloudMusic/8.jpg',
      songs: [songs[1], songs[5], songs[7], songs[13]] // Sweet Dreams、No.9、Lose Control、Rolling in the Deep
    },
    {
      name: '粤语经典',
      count: 3,
      coverImg: 'http://yjy-teach-oss.oss-cn-beijing.aliyuncs.com/HeimaCloudMusic/13.jpg',
      songs: [songs[8], songs[11], songs[12]] // 倩女幽魂、一生所爱、月半小夜曲
    },
    {
      name: '电音派对',
      count: 2,
      coverImg: 'http://yjy-teach-oss.oss-cn-beijing.aliyuncs.com/HeimaCloudMusic/6.jpg',
      songs: [songs[4], songs[5]] // 反转地球、No.9
    },
  ]

  formatCount(count: number): string {
    if (count >= 10000) {
      return (count / 10000).toFixed(1) + '万'
    }
    return count.toString()
  }

  // 打开歌曲列表面板
  openSongPanel(title: string, songs: SongItemType[]) {
    if (songs.length === 0) {
      promptAction.showToast({ message: '暂无歌曲', duration: 1000 })
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
    setTimeout(() => {
      this.userStats.hours = Math.floor(Math.random() * 10) + 1
      const playCountItem = this.playlists.find(item => item.playCount !== undefined)
      if (playCountItem && playCountItem.playCount !== undefined) {
        playCountItem.playCount = playCountItem.playCount + Math.floor(Math.random() * 5)
      }
      this.isRefreshing = false
      promptAction.showToast({ message: '刷新成功', duration: 1000 })
    }, 1000)
  }

  // 歌单排序：上移
  movePlaylistUp(index: number) {
    if (index > 0) {
      const temp = this.createdPlaylists[index]
      this.createdPlaylists[index] = this.createdPlaylists[index - 1]
      this.createdPlaylists[index - 1] = temp
      this.createdPlaylists = [...this.createdPlaylists]  // 触发UI刷新
    }
  }

  // 歌单排序：下移
  movePlaylistDown(index: number) {
    if (index < this.createdPlaylists.length - 1) {
      const temp = this.createdPlaylists[index]
      this.createdPlaylists[index] = this.createdPlaylists[index + 1]
      this.createdPlaylists[index + 1] = temp
      this.createdPlaylists = [...this.createdPlaylists]  // 触发UI刷新
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
        .fillColor(this.scrollY > 75 ? '#333333' : '#ffffff')
        .onClick(() => {
          promptAction.showToast({ message: '菜单', duration: 1000 })
        })

      Stack() {
        Row({ space: 6 }) {
          Text('+ 添加状态')
            .fontSize(14)
            .fontColor(this.scrollY > 75 ? '#666666' : '#ffffff')
          Circle()
            .width(8)
            .height(8)
            .fill('#ff3b30')
        }
      }
      .layoutWeight(1)
      .alignContent(Alignment.Center)

      Row({ space: 18 }) {
        Image($r('app.media.ic_search'))
          .width(22)
          .height(22)
          .fillColor(this.scrollY > 75 ? '#333333' : '#ffffff')
          .onClick(() => {
            promptAction.showToast({ message: '搜索', duration: 1000 })
          })
        Image($r('app.media.ic_more'))
          .width(22)
          .height(22)
          .fillColor(this.scrollY > 75 ? '#333333' : '#ffffff')
          .onClick(() => {
            promptAction.showToast({ message: '设置', duration: 1000 })
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
        .fontColor('#ffffff')
      Text(label)
        .fontSize(11)
        .fontColor('#cccccc')
    }
    .layoutWeight(1)
    .onClick(() => {
      promptAction.showToast({ message: `${label}: ${value}`, duration: 1000 })
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
            .fillColor('#ffcccccc')
        } else if (entry.label === '本地') {
          Image($r('app.media.ic_find'))
            .width(28)
            .height(28)
            .fillColor('#ffcccccc')
        } else if (entry.label === 'VIP') {
          Image($r('app.media.ic_moment'))
            .width(28)
            .height(28)
            .fillColor('#ffd4a74a')
        } else if (entry.label === '装扮') {
          Image($r('app.media.ic_code'))
            .width(28)
            .height(28)
            .fillColor('#ffcccccc')
        } else {
          Image($r('app.media.ic_more'))
            .width(28)
            .height(28)
            .fillColor('#ffcccccc')
        }
      }
      .width(48)
      .height(48)
      .borderRadius(24)
      .backgroundColor('#2a2a2a')
      .justifyContent(FlexAlign.Center)

      Text(entry.label)
        .fontSize(12)
        .fontColor('#bbbbbb')
    }
    .layoutWeight(1)
    .onClick(() => {
      if (entry.label === '最近') {
        this.openSongPanel('最近播放', this.getRecentAllSongs())
      } else if (entry.label === '本地') {
        // 本地歌单 = 导入发现页所有歌曲
        this.openSongPanel('本地下载', [...songs])
      } else {
        promptAction.showToast({ message: `进入: ${entry.label}`, duration: 1000 })
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
        .fontColor(this.currentTab === index ? '#ffffff' : '#888888')
        .animation({ duration: 200, curve: Curve.EaseInOut })
      // Tab指示器 - 使用显式动画实现平滑过渡
      Column()
        .width(20)
        .height(3)
        .borderRadius(1.5)
        .backgroundColor(this.currentTab === index ? '#ec4141' : Color.Transparent)
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
            .fillColor('#888888')
        }
        .width(48)
        .height(48)
        .borderRadius(8)
        .border({ width: 1, color: '#3a3a3a', style: BorderStyle.Dashed })
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
        .backgroundColor('#ec4141')
        .justifyContent(FlexAlign.Center)
      } else if (item.playCount !== undefined) {
        Column() {
          Image($r('app.media.ic_moment'))
            .width(24)
            .height(24)
            .fillColor('#bbbbbb')
        }
        .width(48)
        .height(48)
        .borderRadius(8)
        .backgroundColor('#2a2a2a')
        .justifyContent(FlexAlign.Center)
      } else {
        Stack() {
          // 骨架屏占位（加载中）
          Column()
            .width(48)
            .height(48)
            .borderRadius(8)
            .backgroundColor('#2a2a2a')
            .justifyContent(FlexAlign.Center)
          Image($r('app.media.ic_moment'))
            .width(20)
            .height(20)
            .fillColor('#444444')
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
            .fontColor('#ffffff')
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (item.isNew) {
            Text('NEW')
              .fontSize(10)
              .fontColor(Color.White)
              .padding({ left: 4, right: 4, top: 1, bottom: 1 })
              .backgroundColor('#ec4141')
              .borderRadius(3)
          }
        }

        Row({ space: 6 }) {
          if (item.playCount !== undefined) {
            Text(`累计听歌${item.playCount}首`)
              .fontSize(12)
              .fontColor('#888888')
          } else if (item.count > 0) {
            Text(`${item.count}首`)
              .fontSize(12)
              .fontColor('#888888')
          }
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 右侧操作区
      Row({ space: 12 }) {
        if (item.showPin) {
          Text('不置顶')
            .fontSize(12)
            .fontColor('#888888')
            .onClick(() => {
              promptAction.showToast({ message: '取消置顶', duration: 1000 })
            })
        }
        if (!item.isNew && !item.isImport) {
          Image($r('app.media.ic_more'))
            .width(18)
            .height(18)
            .fillColor('#555555')
        }
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(this.pressedRow === item.name ? 'rgba(255,255,255,0.05)' : Color.Transparent)
    .animation({ duration: 150 })
    .onClick(() => {
      if (item.isNew) {
        promptAction.showToast({ message: '新建歌单', duration: 1000 })
      } else if (item.isImport) {
        this.openSongPanel('导入外部歌单', [...songs])
      } else if (item.playCount !== undefined) {
        this.openSongPanel('听歌排行', this.getRecentAllSongs())
      } else if (item.songs && item.songs.length > 0) {
        this.openSongPanel(item.name, item.songs)
      } else {
        promptAction.showToast({ message: `${item.name}暂无歌曲`, duration: 1000 })
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

  // 歌单长按菜单
  @Builder
  playlistContextMenu(item: PlaylistItem) {
    Menu() {
      MenuItem({ content: item.showPin ? '取消置顶' : '置顶' })
        .onClick(() => {
          item.showPin = !item.showPin
          promptAction.showToast({ message: item.showPin ? '已置顶' : '已取消置顶', duration: 1000 })
        })
      MenuItem({ content: '重命名' })
        .onClick(() => {
          promptAction.showToast({ message: '重命名功能', duration: 1000 })
        })
      MenuItem({ content: '删除' })
        .onClick(() => {
          promptAction.showToast({ message: '删除功能', duration: 1000 })
        })
    }
  }

  // 区域标题栏
  @Builder
  sectionHeader(title: string) {
    Row() {
      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor('#ffffff')
      Blank()
      Row({ space: 4 }) {
        Image($r('app.media.ic_share'))
          .width(18)
          .height(18)
          .fillColor('#888888')
        Image($r('app.media.ic_more'))
          .width(18)
          .height(18)
          .fillColor('#888888')
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 8 })
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
          .backgroundColor('#2a2a2a')
          .justifyContent(FlexAlign.Center)
        Image($r('app.media.ic_moment'))
          .width(20)
          .height(20)
          .fillColor('#444444')
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
            .backgroundColor('rgba(0,0,0,0.4)')
            .justifyContent(FlexAlign.Center)
          Image($r('app.media.wave'))
            .width(22)
            .height(22)
        }
      }
      Text(song.name)
        .fontSize(11)
        .fontColor('#bbbbbb')
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
        .backgroundColor('rgba(0,0,0,0.5)')
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
            .fontColor('#ffffff')
            .layoutWeight(1)

          // 播放全部按钮
          Button('播放全部')
            .fontSize(13)
            .fontColor('#ffffff')
            .backgroundColor('#ec4141')
            .borderRadius(16)
            .height(32)
            .padding({ left: 14, right: 14 })
            .onClick(() => {
              this.playAllSongs()
            })

          Image($r('app.media.ic_close'))
            .width(22)
            .height(22)
            .fillColor('#888888')
            .margin({ left: 12 })
            .onClick(() => {
              this.closeSongPanel()
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 12 })
        .border({ width: { bottom: 0.5 }, color: '#2a2a2a' })

        // 歌曲列表
        List({ space: 0 }) {
          ForEach(this.currentPanelSongs, (song: SongItemType, index: number) => {
            ListItem() {
              Row({ space: 12 }) {
                // 序号
                Text((index + 1).toString().padStart(2, '0'))
                  .fontSize(16)
                  .fontColor(this.playState.url === song.url && this.playState.isPlay ? '#ec4141' : '#888888')
                  .fontWeight(this.playState.url === song.url && this.playState.isPlay ? FontWeight.Bold : FontWeight.Normal)
                  .width(30)

                // 封面
                Stack() {
                  // 骨架屏占位
                  Column()
                    .width(44)
                    .height(44)
                    .borderRadius(6)
                    .backgroundColor('#2a2a2a')
                    .justifyContent(FlexAlign.Center)
                  Image($r('app.media.ic_moment'))
                    .width(18)
                    .height(18)
                    .fillColor('#444444')
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
                      .backgroundColor('rgba(0,0,0,0.3)')
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
                    .fontColor(this.playState.url === song.url && this.playState.isPlay ? '#ec4141' : '#ffffff')
                    .fontWeight(FontWeight.Medium)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(song.author)
                    .fontSize(12)
                    .fontColor('#888888')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                // 更多按钮
                Image($r('app.media.ic_more'))
                  .width(18)
                  .height(18)
                  .fillColor('#555555')
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              .backgroundColor(this.pressedRow === `panel_${index}` ? 'rgba(255,255,255,0.05)' : Color.Transparent)
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
      .backgroundColor('#1e1e1e')
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
        .backgroundColor('rgba(0,0,0,0.5)')
        .onClick(() => {
          this.isEditProfileOpen = false
        })

      Column({ space: 20 }) {
        Text('编辑资料')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#ffffff')

        // 头像预览
        Image($r('app.media.QQp5'))
          .width(80)
          .height(80)
          .borderRadius(40)
          .border({ width: 3, color: '#ffffff' })

        // 昵称编辑
        TextInput({ text: $$this.editNickname, placeholder: '请输入昵称' })
          .fontSize(16)
          .fontColor('#ffffff')
          .placeholderColor('#888888')
          .backgroundColor('#2a2a2a')
          .borderRadius(8)
          .padding({ left: 12, right: 12 })
          .height(44)
          .width('100%')

        // 按钮
        Row({ space: 16 }) {
          Button('取消')
            .fontSize(15)
            .fontColor('#ffffff')
            .backgroundColor('#3a3a3a')
            .borderRadius(20)
            .layoutWeight(1)
            .height(40)
            .onClick(() => {
              this.isEditProfileOpen = false
            })

          Button('保存')
            .fontSize(15)
            .fontColor('#ffffff')
            .backgroundColor('#ec4141')
            .borderRadius(20)
            .layoutWeight(1)
            .height(40)
            .onClick(() => {
              if (this.editNickname.trim().length > 0) {
                this.nickname = this.editNickname.trim()
              }
              this.isEditProfileOpen = false
              promptAction.showToast({ message: '保存成功', duration: 1000 })
            })
        }
        .width('100%')
      }
      .width('80%')
      .padding(24)
      .backgroundColor('#1e1e1e')
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
        .backgroundColor('rgba(0,0,0,0.5)')
        .onClick(() => {
          this.showBadgePanel = false
        })

      Column({ space: 20 }) {
        // 头部
        Row() {
          Text('我的徽章')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#ffffff')
            .layoutWeight(1)
          Image($r('app.media.ic_close'))
            .width(22)
            .height(22)
            .fillColor('#888888')
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
      .backgroundColor('#1e1e1e')
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
        .fontColor(obtained ? '#ffffff' : '#666666')
        .fontWeight(FontWeight.Medium)
      Text(desc)
        .fontSize(10)
        .fontColor('#666666')
        .maxLines(2)
        .textAlign(TextAlign.Center)
      if (obtained) {
        Text('已获得')
          .fontSize(10)
          .fontColor('#d4a74a')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .border({ width: 0.5, color: '#d4a74a', radius: 8 })
      }
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(obtained ? '#2a2520' : '#1a1a1a')
    .borderRadius(10)
    .border({ width: 0.5, color: obtained ? '#d4a74a' : '#2a2a2a' })
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
                      .border({ width: 2, color: '#ffffff' })
                      .shadow({ radius: 8, color: 'rgba(0,0,0,0.15)', offsetX: 0, offsetY: 2 })
                      .scale({ x: this.avatarScale, y: this.avatarScale })
                      .opacity(Math.min(1, this.headerHeight / 120) * this.avatarOpacity)
                      .animation({ duration: 200, curve: Curve.EaseInOut })
                      .onClick(() => {
                        this.avatarScale = 0.9
                        this.avatarOpacity = 0.8
                        setTimeout(() => {
                          this.avatarScale = 1
                          this.avatarOpacity = 1
                        }, 150)
                        this.editNickname = this.nickname
                        this.isEditProfileOpen = true
                      })

                    // 昵称行（滚到一定程度后隐藏）
                    if (this.headerHeight > 80) {
                      Column({ space: 6 }) {
                        Row({ space: 6 }) {
                          Text(this.nickname)
                            .fontSize(18)
                            .fontWeight(FontWeight.Bold)
                            .fontColor('#ffffff')
                          Text('P+')
                            .fontSize(10)
                            .fontColor('#ffffff')
                            .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                            .backgroundColor('#ff6b6b')
                            .borderRadius(4)
                          Image($r('app.media.ic_more'))
                            .width(14)
                            .height(14)
                            .fillColor('#ffffff')
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
                          .fillColor('#d4a74a')
                        Text(`${this.badgeCount}枚徽章`)
                          .fontSize(13)
                          .fontColor('#ffffff')
                        Image($r('app.media.ic_more'))
                          .width(12)
                          .height(12)
                          .fillColor('#ffffff')
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
                          .color('rgba(255,255,255,0.3)')
                          .height(20)
                        this.statItem(this.userStats.fans.toString(), '粉丝')
                        Divider()
                          .vertical(true)
                          .strokeWidth(0.5)
                          .color('rgba(255,255,255,0.3)')
                          .height(20)
                        this.statItem(`Lv.${this.userStats.level}`, '等级')
                        Divider()
                          .vertical(true)
                          .strokeWidth(0.5)
                          .color('rgba(255,255,255,0.3)')
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
            .backgroundColor('#1a1a1a')

            // 分隔
            Column()
              .width('100%')
              .height(8)
              .backgroundColor('#0f0f0f')

            // ========== 4. 内容Tab切换 ==========
            Row() {
              ForEach(this.contentTabs, (tab: ContentTab, index: number) => {
                this.contentTabItem(tab, index)
              }, (tab: ContentTab) => tab.label)
              Blank()
            }
            .width('100%')
            .padding({ top: 12, bottom: 4 })
            .backgroundColor('#1a1a1a')

            Divider()
              .strokeWidth(0.5)
              .color('#2a2a2a')
              .width('100%')

            // ========== 5. 歌单区域标题 ==========
            Row() {
              Text('近期')
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor('#ffffff')
                .padding({ left: 16, top: 12, bottom: 8 })
              Text('创建¹')
                .fontSize(12)
                .fontColor('#888888')
                .padding({ top: 12, bottom: 8 })
              Blank()
              Row({ space: 12 }) {
                // 排序模式切换
                Text(this.isSortMode ? '完成' : '排序')
                  .fontSize(13)
                  .fontColor(this.isSortMode ? '#ec4141' : '#888888')
                  .onClick(() => {
                    this.isSortMode = !this.isSortMode
                  })
                Image($r('app.media.ic_share'))
                  .width(18)
                  .height(18)
                  .fillColor('#888888')
                Image($r('app.media.ic_more'))
                  .width(18)
                  .height(18)
                  .fillColor('#888888')
                  .margin({ right: 16 })
              }
            }
            .width('100%')
            .backgroundColor('#1a1a1a')

            // ========== 6. 歌单列表（竖向） ==========
            Column() {
              ForEach(this.playlists, (item: PlaylistItem) => {
                this.playlistRow(item)
              }, (item: PlaylistItem) => item.name)

              Divider()
                .strokeWidth(0.5)
                .color('#2a2a2a')
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
                          .fillColor(index > 0 ? '#888888' : '#444444')
                          .rotate({ angle: -90 })
                          .onClick(() => {
                            this.movePlaylistUp(index)
                          })
                        Image($r('app.media.ic_share'))
                          .width(16)
                          .height(16)
                          .fillColor(index < this.createdPlaylists.length - 1 ? '#888888' : '#444444')
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
                    .fillColor('#444444')
                    .opacity(0.5)
                  Text('还没有创建歌单')
                    .fontSize(14)
                    .fontColor('#666666')
                  Text('点击上方"新建歌单"开始创建')
                    .fontSize(12)
                    .fontColor('#555555')
                }
                .width('100%')
                .padding({ top: 24, bottom: 24 })
                .alignItems(HorizontalAlign.Center)
              }
            }
            .width('100%')
            .backgroundColor('#1a1a1a')

            // 分隔
            Column()
              .width('100%')
              .height(8)
              .backgroundColor('#0f0f0f')

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
                    .fillColor('#444444')
                    .opacity(0.5)
                  Text('还没有收藏歌单')
                    .fontSize(14)
                    .fontColor('#666666')
                  Text('去发现页看看吧~')
                    .fontSize(12)
                    .fontColor('#555555')
                }
                .width('100%')
                .padding({ top: 30, bottom: 30 })
                .alignItems(HorizontalAlign.Center)
              }
            }
            .width('100%')
            .backgroundColor('#1a1a1a')

            // 分隔
            Column()
              .width('100%')
              .height(8)
              .backgroundColor('#0f0f0f')

            // ========== 8. 最近播放 ==========
            Column() {
              Row() {
                Text('最近播放')
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#ffffff')
                  .layoutWeight(1)
                Row({ space: 4 }) {
                  Text('全部')
                    .fontSize(13)
                    .fontColor('#888888')
                  Image($r('app.media.ic_more'))
                    .width(14)
                    .height(14)
                    .fillColor('#888888')
                }
                .onClick(() => {
                  this.openSongPanel('最近播放', this.getRecentAllSongs())
                })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 16, bottom: 10 })

              Scroll() {
                Row() {
                  // 播放全部入口
                  Column({ space: 6 }) {
                    Column() {
                      Image($r('app.media.wave'))
                        .width(28)
                        .height(28)
                        .fillColor('#ec4141')
                    }
                    .width(55)
                    .height(55)
                    .borderRadius(6)
                    .backgroundColor('#2a2020')
                    .justifyContent(FlexAlign.Center)
                    Text('播放全部')
                      .fontSize(11)
                      .fontColor('#ec4141')
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
            .backgroundColor('#1a1a1a')

            // 底部留白
            Column()
              .height(70)
              .backgroundColor('#1a1a1a')
          }
          .width('100%')
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .backgroundColor('#131313')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .onScroll(() => {
          this.scrollY = this.scroller.currentOffset().yOffset
          // 滚动时头部区域逐渐收起，最小保留48（导航栏高度）
          this.headerHeight = Math.max(48, 260 - this.scrollY)
        })
      }
      .refreshOffset(64)
      .onRefreshing(() => {
        this.handleRefresh()
      })
      .backgroundColor('#131313')

      // ========== 9. 歌曲列表面板（弹出层） ==========
      if (this.isSongPanelOpen) {
        this.songPanel()
      }

      // ========== 10. 编辑资料弹窗 ==========
      if (this.isEditProfileOpen) {
        this.editProfileDialog()
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