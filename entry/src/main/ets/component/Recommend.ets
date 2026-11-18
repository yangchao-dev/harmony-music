// 导入推荐页数据
import {
  swiperList,
  dailyRecommend,
  recommendDailyType,
  recommendList,
  recommendListType
} from '../models/RecommendData'
import { songs } from '../models/songData'
import { SongItemType } from '../models/music'
import { formatCount } from '../utils/Formatter'
import { AppStorageV2 } from '@kit.ArkUI'
import { playerManager } from '../utils/AvPlayerManager'
import { PlayerState, getPlayerState } from '../models/PlayerState'
import { toast } from '../utils/Toast'
import {
  HOT_KEYWORDS,
  SEARCH_HISTORY_MAX,
  filterSongs,
  pushSearchHistory,
  splitByKeyword
} from '../models/SearchModels'
import {
  QueueStore,
  getQueueStore,
  getSettingsStore,
  SettingsStore,
  preferencesService,
  SEARCH_SOURCE_ITUNES,
  SEARCH_SOURCE_NETEASE,
  DEFAULT_NETEASE_API,
  normalizeApiBase
} from '../models/UserSettings'
import { searchService } from '../utils/SearchService'

@ComponentV2
export struct Recommend {
  // 搜索关键字
  @Local keyword: string = ''
  // 是否处于搜索态（输入过内容后一直保持，直到取消）
  @Local searching: boolean = false
  // 搜索历史（内存 + 落盘）
  @Local searchHistory: string[] = []
  // 搜索结果
  @Local searchResult: SongItemType[] = []
  // 全网搜索结果（网络）
  @Local onlineResult: SongItemType[] = []
  @Local onlineLoading: boolean = false
  @Local onlineError: string = ''
  @Local region: 'cn' | 'us' = 'cn'
  @Local onlineFilteredCount: number = 0
  // 网易云 API 地址配置弹层
  @Local showApiDialog: boolean = false
  @Local apiInput: string = ''
  @Local apiInputError: string = ''
  private onlineDebounceTimer: number = -1
  // 推荐歌单面板
  @Local showPodcastPanel: boolean = false
  @Local podcastTitle: string = ''
  @Local podcastSongs: SongItemType[] = []

  pathStack: NavPathStack = AppStorageV2.connect(NavPathStack, 'navStack', () => new NavPathStack())!
  playState: PlayerState = getPlayerState()
  queueStore: QueueStore = getQueueStore()
  settingsStore: SettingsStore = getSettingsStore()

  /** 当前是否网易云数据源 */
  private isNetease(): boolean {
    return this.settingsStore.searchSource === SEARCH_SOURCE_NETEASE
  }

  aboutToAppear(): void {
    // 搜索历史从偏好文件恢复
    preferencesService.getSearchHistory().then((history: string[]) => {
      this.searchHistory = history
    })
    // 输入框回填已保存的 API 地址
    this.apiInput = this.settingsStore.neteaseApiBase
  }

  aboutToDisappear(): void {
    if (this.onlineDebounceTimer !== -1) {
      clearTimeout(this.onlineDebounceTimer)
      this.onlineDebounceTimer = -1
    }
    // 离开页面取消进行中的网络请求
    searchService.cancel()
  }

  // ========== 搜索逻辑 ==========

  /** 提交搜索：写入历史 + 立即全网搜索 */
  submitSearch(value: string) {
    const key = (value ?? this.keyword).trim()
    if (key.length === 0) {
      return
    }
    this.onKeywordChange(key)
    this.searchHistory = pushSearchHistory(this.searchHistory, key, SEARCH_HISTORY_MAX)
    preferencesService.saveSearchHistory(this.searchHistory)
    // 提交时立即发起全网搜索，不等待输入防抖
    this.doOnlineSearch()
  }

  /** 点击热词 / 历史词：本地过滤 + 全网搜索 */
  applyKeyword(word: string) {
    this.submitSearch(word)
  }

  // ========== 全网搜索（iTunes API） ==========

  /** 输入变化：即时本地过滤 + 防抖全网搜索 */
  onKeywordChange(value: string) {
    this.keyword = value
    this.searching = value.trim().length > 0
    this.searchResult = filterSongs(songs, value)
    this.scheduleOnlineSearch(value)
  }

  /** 防抖：停止输入 600ms 后再请求网络，减少无效请求 */
  private scheduleOnlineSearch(value: string): void {
    if (this.onlineDebounceTimer !== -1) {
      clearTimeout(this.onlineDebounceTimer)
    }
    const kw = value.trim()
    if (kw.length === 0) {
      this.onlineResult = []
      this.onlineError = ''
      this.onlineLoading = false
      return
    }
    this.onlineLoading = true
    this.onlineDebounceTimer = setTimeout(() => {
      this.onlineDebounceTimer = -1
      this.doOnlineSearch()
    }, 600)
  }

  /** 真正发起全网搜索 */
  async doOnlineSearch(): Promise<void> {
    if (this.onlineDebounceTimer !== -1) {
      clearTimeout(this.onlineDebounceTimer)
      this.onlineDebounceTimer = -1
    }
    const kw = this.keyword.trim()
    if (kw.length === 0) {
      return
    }
    this.onlineLoading = true
    this.onlineError = ''
    this.onlineFilteredCount = 0
    const result = await searchService.search(kw, this.region)
    this.onlineLoading = false
    this.onlineResult = result.list
    this.onlineError = result.error
    this.onlineFilteredCount = result.filteredCount
  }

  /** 切换曲库地区（中国区 / 全球区）后重新搜索（仅 iTunes 有效） */
  switchRegion(region: 'cn' | 'us'): void {
    if (this.region === region) {
      return
    }
    this.region = region
    if (this.keyword.trim().length > 0) {
      this.doOnlineSearch()
    }
  }

  // ========== 数据源切换 ==========

  /** 切换全网搜索数据源（iTunes / 网易云），切换后清空旧结果并重新搜索 */
  switchSource(source: string): void {
    if (this.settingsStore.searchSource === source) {
      return
    }
    preferencesService.setSearchSource(source)
    this.onlineResult = []
    this.onlineError = ''
    this.onlineFilteredCount = 0
    // 切到网易云时回填已保存地址
    if (source === SEARCH_SOURCE_NETEASE) {
      this.apiInput = this.settingsStore.neteaseApiBase
    }
    if (this.keyword.trim().length > 0) {
      this.doOnlineSearch()
    }
  }

  /** 打开 API 地址配置弹层 */
  openApiDialog(): void {
    this.apiInput = this.settingsStore.neteaseApiBase
    this.apiInputError = ''
    this.showApiDialog = true
  }

  /** 保存 API 地址：校验 -> 落盘 -> 若正在搜索则重试 */
  saveApiBase(): void {
    const normalized = normalizeApiBase(this.apiInput)
    if (normalized.length === 0) {
      this.apiInputError = '请输入有效的接口地址'
      return
    }
    // 简单协议校验：必须 http/https（normalizeApiBase 已补全 https）
    if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
      this.apiInputError = '地址需以 http:// 或 https:// 开头'
      return
    }
    preferencesService.setNeteaseApiBase(normalized)
    this.apiInput = normalized
    this.apiInputError = ''
    this.showApiDialog = false
    toast({ message: '接口地址已保存', duration: 1200 })
    if (this.isNetease() && this.keyword.trim().length > 0) {
      this.doOnlineSearch()
    }
  }

  /** 恢复默认公共实例地址 */
  resetApiBase(): void {
    this.apiInput = DEFAULT_NETEASE_API
    this.apiInputError = ''
  }

  /** 退出搜索态 */
  exitSearch() {
    this.keyword = ''
    this.searching = false
    this.searchResult = []
    this.onlineResult = []
    this.onlineError = ''
    if (this.onlineDebounceTimer !== -1) {
      clearTimeout(this.onlineDebounceTimer)
      this.onlineDebounceTimer = -1
    }
    searchService.cancel()
  }

  /** 清空搜索历史 */
  clearHistory() {
    this.searchHistory = []
    preferencesService.saveSearchHistory([])
  }

  /** 删除单条历史 */
  removeHistory(word: string) {
    this.searchHistory = this.searchHistory.filter((item: string) => item !== word)
    preferencesService.saveSearchHistory(this.searchHistory)
  }

  // ========== 播放 / 歌单 ==========

  /** 播放单曲并跳转播放页 */
  playSong(song: SongItemType) {
    playerManager.singPlay(song)
    this.pathStack.pushPathByName('Play', null, true)
  }

  /** 打开歌单面板 */
  openPodcast(title: string, list: SongItemType[]) {
    if (list.length === 0) {
      toast({ message: '歌单暂无歌曲', duration: 1200 })
      return
    }
    this.podcastTitle = title
    this.podcastSongs = list
    this.showPodcastPanel = true
  }

  /** 播放全部（复用全局播放队列） */
  playAll() {
    if (this.podcastSongs.length === 0) {
      return
    }
    playerManager.playAllSongs(this.podcastSongs)
    this.showPodcastPanel = false
    this.pathStack.pushPathByName('Play', null, true)
  }

  /** 收藏 / 取消收藏当前面板的歌单 */
  toggleFavPodcast() {
    const key = this.podcastTitle
    if (key.length === 0) {
      return
    }
    const fav = preferencesService.togglePodcastFav(key)
    toast({ message: fav ? '已收藏该歌单' : '已取消收藏', duration: 1200 })
  }

  /** 每日推荐 / 推荐歌单卡片：按索引取一段歌曲，模拟不同歌单内容 */
  private pickSongs(offset: number, size: number): SongItemType[] {
    const total = songs.length
    const result: SongItemType[] = []
    for (let i = 0; i < size; i++) {
      result.push(songs[(offset + i) % total])
    }
    return result
  }

  // 搜索中的关键词高亮片段
  private hitSegments(text: string): string[] {
    return splitByKeyword(text, this.keyword)
  }

  // 标题
  @Builder
  titleBuilder(title: string) {
    Row() {
      Text(title)
        .fontColor('#fff')
        .fontWeight(700)
        .layoutWeight(1)
      Image($r('app.media.ic_more'))
        .width(22)
        .fillColor('#fff')
    }
    .padding({ left: 10, right: 10 })
    .width('100%')
    .height(40)
  }

  // 搜索结果行
  @Builder
  searchResultRow(song: SongItemType, index: number) {
    Row({ space: 12 }) {
      Image(song.img)
        .width(48)
        .height(48)
        .borderRadius(8)
        .objectFit(ImageFit.Cover)

      Column({ space: 4 }) {
        // 歌名（命中关键字高亮）
        Text() {
          Span(this.hitSegments(song.name)[0])
            .fontColor(Color.White)
          Span(this.hitSegments(song.name)[1])
            .fontColor('#ff5186')
          Span(this.hitSegments(song.name)[2])
            .fontColor(Color.White)
        }
        .fontSize(15)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

        // 歌手（命中关键字高亮）
        Text() {
          Span(this.hitSegments(song.author)[0])
            .fontColor(Color.Gray)
          Span(this.hitSegments(song.author)[1])
            .fontColor('#ff5186')
          Span(this.hitSegments(song.author)[2])
            .fontColor(Color.Gray)
        }
        .fontSize(12)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 播放按钮 / 正在播放标识
      if (this.playState.url === song.url && this.playState.isPlay) {
        Image($r('app.media.wave'))
          .width(20)
          .height(20)
      } else {
        Image($r('app.media.ic_play'))
          .width(22)
          .height(22)
          .fillColor('#8a8a8a')
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .onClick(() => {
      this.playSong(song)
    })
  }

  // 全网搜索结果行（带"试听"标识）
  @Builder
  onlineResultRow(song: SongItemType, index: number) {
    Row({ space: 12 }) {
      Image(song.img)
        .width(48)
        .height(48)
        .borderRadius(8)
        .objectFit(ImageFit.Cover)
        .alt($r('app.media.ic_music'))

      Column({ space: 4 }) {
        Text(`${index + 1}.  ${song.name}`)
          .fontSize(15)
          .fontColor(this.playState.url === song.url ? '#ff5186' : Color.White)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(song.author)
          .fontSize(12)
          .fontColor(Color.Gray)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(this.isNetease() ? '完整' : '试听')
        .fontSize(10)
        .fontColor(this.isNetease() ? '#4caf50' : '#ff5186')
        .border({ width: 1, color: this.isNetease() ? '#4caf50' : '#ff5186', radius: 8 })
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .onClick(() => {
      this.playSong(song)
    })
  }

  // 搜索面板（历史 / 热搜 / 结果）
  @Builder
  searchPanel() {
    Column() {
      if (this.keyword.trim().length === 0) {
        // 搜索历史
        if (this.searchHistory.length > 0) {
          Row() {
            Text('搜索历史')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
              .layoutWeight(1)
            Text('清空')
              .fontSize(12)
              .fontColor(Color.Gray)
              .onClick(() => {
                this.clearHistory()
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 8 })

          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.searchHistory, (word: string) => {
              Text(word)
                .fontSize(12)
                .fontColor('#d0d0d0')
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .margin({ right: 8, bottom: 8 })
                .backgroundColor('#2a2a2a')
                .borderRadius(14)
                .onClick(() => {
                  this.applyKeyword(word)
                })
            }, (word: string) => word)
          }
          .padding({ left: 16, right: 16 })
        }

        // 热搜
        Row() {
          Text('热门搜索')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 8 })

        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(HOT_KEYWORDS, (word: string) => {
            Text(word)
              .fontSize(12)
              .fontColor('#ffb3cd')
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .margin({ right: 8, bottom: 8 })
              .backgroundColor('#33ff5186')
              .borderRadius(14)
              .onClick(() => {
                this.applyKeyword(word)
              })
          }, (word: string) => word)
        }
        .padding({ left: 16, right: 16 })
      } else {
        // 结果列表：本地歌曲 + 全网歌曲
        List() {
          // ---------- 本地歌曲分组 ----------
          if (this.searchResult.length > 0) {
            ListItem() {
              Row() {
                Text(`本地歌曲  (${this.searchResult.length})`)
                  .fontSize(13)
                  .fontColor('#aaaaaa')
                  .layoutWeight(1)
                Text('播放全部')
                  .fontSize(12)
                  .fontColor('#ff5186')
                  .onClick(() => {
                    playerManager.playAllSongs(this.searchResult)
                    this.pathStack.pushPathByName('Play', null, true)
                  })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 4 })
            }

            ForEach(this.searchResult, (song: SongItemType, index: number) => {
              ListItem() {
                this.searchResultRow(song, index)
              }
            }, (song: SongItemType) => `search_${song.id}`)
          }

          // ---------- 全网歌曲分组 ----------
          ListItem() {
            Column({ space: 8 }) {
              Row({ space: 8 }) {
                Text(`全网歌曲${this.onlineResult.length > 0 ? '  (' + this.onlineResult.length + ')' : ''}`)
                  .fontSize(13)
                  .fontColor('#aaaaaa')
                  .layoutWeight(1)

                // 数据源切换：iTunes（试听） / 网易云（完整）
                Text('iTunes')
                  .fontSize(11)
                  .fontColor(!this.isNetease() ? '#ffff52d2' : '#777777')
                  .backgroundColor(!this.isNetease() ? '#33ffff52d2' : Color.Transparent)
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                  .borderRadius(10)
                  .onClick(() => this.switchSource(SEARCH_SOURCE_ITUNES))
                Text('网易云')
                  .fontSize(11)
                  .fontColor(this.isNetease() ? '#4caf50' : '#777777')
                  .backgroundColor(this.isNetease() ? '#334caf50' : Color.Transparent)
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                  .borderRadius(10)
                  .onClick(() => this.switchSource(SEARCH_SOURCE_NETEASE))
                // 网易云：接口设置入口
                if (this.isNetease()) {
                  Text('⚙')
                    .fontSize(15)
                    .fontColor('#aaaaaa')
                    .onClick(() => this.openApiDialog())
                }
              }
              .width('100%')

              // 曲库地区切换：仅 iTunes 显示（网易云无地区概念）
              if (!this.isNetease()) {
                Row({ space: 8 }) {
                  Text('地区：')
                    .fontSize(11)
                    .fontColor('#666666')
                  Text('中国区')
                    .fontSize(11)
                    .fontColor(this.region === 'cn' ? '#ffff52d2' : '#777777')
                    .backgroundColor(this.region === 'cn' ? '#33ffff52d2' : Color.Transparent)
                    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                    .borderRadius(10)
                    .onClick(() => this.switchRegion('cn'))
                  Text('全球')
                    .fontSize(11)
                    .fontColor(this.region === 'us' ? '#ffff52d2' : '#777777')
                    .backgroundColor(this.region === 'us' ? '#33ffff52d2' : Color.Transparent)
                    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                    .borderRadius(10)
                    .onClick(() => this.switchRegion('us'))
                }
                .width('100%')
              } else {
                // 网易云数据源说明
                Text('需电脑运行本地接口服务，手机与电脑连同一 WiFi；地址在 ⚙ 中设置')
                  .fontSize(10)
                  .fontColor('#666666')
                  .width('100%')
              }
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 4 })
            .alignItems(HorizontalAlign.Start)
          }

          if (this.onlineLoading) {
            ListItem() {
              Row({ space: 10 }) {
                LoadingProgress()
                  .width(22)
                  .height(22)
                  .color('#ffff52d2')
                Text('搜索全网中...')
                  .fontSize(12)
                  .fontColor('#888888')
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .padding({ top: 20, bottom: 20 })
            }
          } else if (this.onlineError.length > 0) {
            ListItem() {
              Column({ space: 8 }) {
                Text(this.onlineError)
                  .fontSize(12)
                  .fontColor('#888888')
                Text('点击重试')
                  .fontSize(12)
                  .fontColor('#ff5186')
                  .onClick(() => this.doOnlineSearch())
              }
              .width('100%')
              .padding({ top: 16, bottom: 16 })
              .alignItems(HorizontalAlign.Center)
            }
          } else if (this.onlineResult.length === 0) {
            ListItem() {
              Text('全网暂无相关结果，换个关键词或切换曲库试试')
                .fontSize(12)
                .fontColor('#666666')
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding({ top: 16, bottom: 16 })
            }
          } else {
            ForEach(this.onlineResult, (song: SongItemType, index: number) => {
              ListItem() {
                this.onlineResultRow(song, index)
              }
            }, (song: SongItemType) => `online_${song.id}`)
            // 版权 / 会员过滤提示
            if (this.onlineFilteredCount > 0) {
              ListItem() {
                Text(`${this.onlineFilteredCount} 首歌曲因版权或会员限制无音源，已隐藏`)
                  .fontSize(11)
                  .fontColor('#777777')
                  .width('100%')
                  .textAlign(TextAlign.Center)
                  .padding({ top: 10, bottom: 6 })
              }
            }
          }

          ListItem() {
            Column().height(20)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
  }

  // 歌单面板（每日推荐 / 推荐歌单共用）
  @Builder
  podcastPanel() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#99000000')
        .onClick(() => {
          this.showPodcastPanel = false
        })

      Column() {
        Row({ space: 12 }) {
          Column({ space: 4 }) {
            Text(this.podcastTitle)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(`${this.podcastSongs.length} 首`)
              .fontSize(12)
              .fontColor(Color.Gray)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Button(this.queueStore.favoritePodcasts.includes(this.podcastTitle) ? '已收藏' : '收藏')
            .fontSize(12)
            .height(30)
            .fontColor(Color.White)
            .backgroundColor('#33ffffff')
            .borderRadius(15)
            .onClick(() => {
              this.toggleFavPodcast()
            })

          Button('播放全部')
            .fontSize(12)
            .height(30)
            .fontColor(Color.White)
            .backgroundColor('#ff5186')
            .borderRadius(15)
            .onClick(() => {
              this.playAll()
            })

          Image($r('app.media.ic_close'))
            .width(20)
            .height(20)
            .fillColor('#a49a9a')
            .onClick(() => {
              this.showPodcastPanel = false
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 12 })

        Divider()
          .strokeWidth(0.5)
          .color('#33ffffff')

        List() {
          ForEach(this.podcastSongs, (song: SongItemType, index: number) => {
            ListItem() {
              Row({ space: 12 }) {
                Text((index + 1).toString())
                  .fontSize(13)
                  .fontColor(this.playState.url === song.url ? '#ff5186' : '#8a8a8a')
                  .width(24)

                Image(song.img)
                  .width(42)
                  .height(42)
                  .borderRadius(6)
                  .objectFit(ImageFit.Cover)

                Column({ space: 3 }) {
                  Text(song.name)
                    .fontSize(14)
                    .fontColor(this.playState.url === song.url ? '#ff5186' : Color.White)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(song.author)
                    .fontSize(12)
                    .fontColor(Color.Gray)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              .onClick(() => {
                this.showPodcastPanel = false
                this.playSong(song)
              })
            }
          }, (song: SongItemType) => `podcast_${song.id}`)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('70%')
      .backgroundColor('#ff262626')
      .borderRadius({ topLeft: 16, topRight: 16 })
      .transition(TransitionEffect.translate({ y: 600 }).animation({ duration: 300, curve: Curve.EaseOut }))
    }
    .width('100%')
    .height('100%')
    .position({ x: 0, y: 0 })
    .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
  }

  // 网易云 API 地址配置弹层
  @Builder
  apiConfigDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#99000000')
        .onClick(() => {
          this.showApiDialog = false
        })

      Column({ space: 12 }) {
        Text('网易云接口设置')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)

        Text('默认指向电脑本地接口（http://192.168.10.41:3000）。需先在电脑启动服务，且手机与电脑连同一 WiFi。换网络后请更新为电脑新的 IP。')
          .fontSize(12)
          .fontColor('#aaaaaa')
          .width('100%')
          .lineHeight(18)

        TextInput({ text: $$this.apiInput, placeholder: DEFAULT_NETEASE_API })
          .fontSize(13)
          .fontColor(Color.White)
          .placeholderColor('#666666')
          .backgroundColor('#333333')
          .borderRadius(8)
          .width('100%')
          .onChange((value: string) => {
            this.apiInput = value
            this.apiInputError = ''
          })

        if (this.apiInputError.length > 0) {
          Text(this.apiInputError)
            .fontSize(11)
            .fontColor('#ff6b6b')
            .width('100%')
        }

        Row({ space: 10 }) {
          Text('恢复默认')
            .fontSize(12)
            .fontColor('#aaaaaa')
            .onClick(() => this.resetApiBase())
          Blank()
          Text('取消')
            .fontSize(13)
            .fontColor('#aaaaaa')
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            .onClick(() => {
              this.showApiDialog = false
            })
          Text('保存')
            .fontSize(13)
            .fontColor(Color.White)
            .backgroundColor('#ff5186')
            .borderRadius(8)
            .padding({ left: 20, right: 20, top: 8, bottom: 8 })
            .onClick(() => this.saveApiBase())
        }
        .width('100%')
      }
      .padding(20)
      .width('86%')
      .backgroundColor('#ff262626')
      .borderRadius(16)
    }
    .width('100%')
    .height('100%')
    .position({ x: 0, y: 0 })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        // 搜索区域
        Row() {
          Image($r('app.media.ic_search'))
            .width(24)
            .margin({ left: 10 })
            .fillColor(Color.Gray)
          // 文本输入框：支持实时过滤 + 提交
          TextInput({ text: $$this.keyword, placeholder: '只因你太美' })
            .placeholderColor(Color.Gray)
            .fontColor(Color.White)
            .layoutWeight(1)
            .backgroundColor(Color.Transparent)
            .onChange((value: string) => {
              this.onKeywordChange(value)
            })
            .onSubmit(() => {
              this.submitSearch(this.keyword)
            })

          if (this.keyword.length > 0) {
            Image($r('app.media.ic_close'))
              .width(18)
              .height(18)
              .margin({ right: 8 })
              .fillColor(Color.Gray)
              .onClick(() => {
                this.exitSearch()
              })
          }

          Image($r('app.media.ic_code'))
            .width(23)
            .fillColor(Color.Gray)
            .margin({ right: 10 })
        }
        .margin({ top: 10 })
        .borderRadius(20)
        .backgroundColor('#2f2b28')
        .width('95%')

        if (this.searching) {
          // 搜索态：占满剩余空间
          this.searchPanel()
        } else {
          Scroll() {
            Column() {
              // 轮播图
              Swiper() {
                ForEach(swiperList, (item: string) => {
                  Image(item)
                    .width('100%')
                    .padding(10)
                    .borderRadius(15)
                    .height(200)
                })
              }
              .autoPlay(true) // 设置自动轮播
              .duration(1000) // 动画持续时长
              .interval(2000) // 轮播间隔
              .width('100%')
              // 轮播指示器(小点)样式
              .indicator(
                Indicator.dot()
                  .itemWidth(3)
                  .itemHeight(3)
                  .bottom(5)
                  .color(Color.Gray)
                  .selectedColor(Color.White)
              )


              // 每日推荐
              this.titleBuilder('每日推荐')
              //List 内容
              List({ space: 10 }) {
                ForEach(dailyRecommend, (item: recommendDailyType, index: number) => {
                  ListItem() {
                    Column() {
                      // 标题
                      Text(item.type)
                        .fontColor(Color.White)
                        .backgroundColor(item.top)
                        .width('100%')
                        .padding(5)
                        .fontSize(14)
                      // 图片
                      Image(item.img)
                        .width('100%')

                      // 简介
                      Text(item.title)
                        .backgroundColor(item.bottom)
                        .fontColor(Color.White)
                        .width('100%')
                        .padding(5)
                        .fontSize(14)
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }

                    .width('40%')
                    .borderRadius(10)
                    .clip(true)
                    // 点击卡片：打开歌单面板，可播放全部
                    .onClick(() => {
                      this.openPodcast(item.type, this.pickSongs(index * 3, 6))
                    })
                  }

                })
              }
              .padding({ left: 10, right: 10 })
              .scrollBar(BarState.Off) // 关闭滚动条
              .width('100%')
              .height(220) // List 需要设置宽高
              .listDirection(1) // 0 = 纵向滚动， 1 = 横向滚动


              // 推荐歌单
              this.titleBuilder('推荐歌单')
              // List歌单内容
              List({ space: 10 }) {
                ForEach(recommendList, (item: recommendListType, index: number) => {
                  ListItem() {
                    Column() {
                      Stack({ alignContent: Alignment.TopStart }) {
                        Image(item.img)
                          .width('100%')
                        Text(item.count)
                          .fontColor(Color.White)
                          .margin(10)
                          .fontSize(14)
                      }
                      .borderRadius(15)
                      .clip(true)

                      Text(item.title)

                        .fontColor(Color.White)
                        .width('100%')
                        .padding(5)
                        .fontSize(14)
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })

                    }
                    .width('30%')
                    // 点击卡片：打开歌单面板，可播放全部
                    .onClick(() => {
                      this.openPodcast(item.title, this.pickSongs(index * 2 + 1, 8))
                    })

                  }
                })
              }
              .listDirection(1)
              .width('100%')
              .height(150)
              .padding({ left: 10, right: 10 })
              .scrollBar(BarState.Off)

              // 底部留白，避免内容贴着 TabBar
              Column().height(80)
            }
            .width('100%')
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')

      // 歌单面板
      if (this.showPodcastPanel) {
        this.podcastPanel()
      }

      // 网易云 API 配置弹层
      if (this.showApiDialog) {
        this.apiConfigDialog()
      }
    }
    .width('100%')
    .height('100%')
  }
}
