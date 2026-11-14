import { LyricItem } from '../models/LyricItem'
import { GlobalMusic } from '../models/globalMusic'
import { AppStorageV2 } from '@kit.ArkUI'
import { playerManager } from '../utils/AvPlayerManager'

/**
 * 预设颜色主题
 */
const COLOR_THEMES: LyricColorTheme[] = [
  { name: '纯白', activeColor: '#FFFFFF', inactiveColor: '#88ffffff' },
  { name: '金色', activeColor: '#FFD700', inactiveColor: '#88ffd700' },
  { name: '青色', activeColor: '#00CED1', inactiveColor: '#8800ced1' },
  { name: '粉红', activeColor: '#FF69B4', inactiveColor: '#88ff69b4' },
  { name: '橙黄', activeColor: '#FFA500', inactiveColor: '#88ffa500' },
]

/** 歌词轮询间隔（毫秒），用 50ms 高频轮询确保跟音频同步 */
const LYRIC_TICK_MS: number = 50

interface LyricColorTheme {
  name: string
  activeColor: string
  inactiveColor: string
}

@ComponentV2
export struct LyricView {
  @Param lyrics: LyricItem[] = []
  @Param isVisible: boolean = true
  @Event onBackToDisc?: () => void

  // 当前播放歌曲信息
  @Local playState: GlobalMusic = AppStorageV2.connect(GlobalMusic, 'SONG_KEY', () => new GlobalMusic())!
  // 当前高亮的歌词行索引
  @Local currentIndex: number = -1
  // 字体大小：12~24，默认 15
  @Local fontSize: number = 15
  // 当前颜色主题索引
  @Local themeIndex: number = 0
  // 是否处于用户手动拖拽模式（拖拽时暂停自动滚动）
  @Local isUserScrolling: boolean = false
  // 显示设置面板
  @Local showSettings: boolean = false

  private scroller: Scroller = new Scroller()
  /** 用户手动滚动的恢复定时器 */
  private resumeScrollTimer: number = -1
  /** 歌词轮询定时器 */
  private lyricTickTimer: number = -1
  /** 上次已滚动到的索引，避免重复滚动 */
  private lastScrolledIndex: number = -1

  // ========== 生命周期 ==========

  aboutToAppear(): void {
    this.startLyricTick()
  }

  aboutToDisappear(): void {
    this.stopLyricTick()
  }

  // ========== 歌词轮询 ==========

  /** 启动歌词轮询定时器 */
  private startLyricTick(): void {
    this.stopLyricTick()
    this.lyricTickTimer = setInterval(() => {
      this.tickLyric()
    }, LYRIC_TICK_MS)
  }

  /** 停止歌词轮询定时器 */
  private stopLyricTick(): void {
    if (this.lyricTickTimer !== -1) {
      clearInterval(this.lyricTickTimer)
      this.lyricTickTimer = -1
    }
  }

  /** 每次 tick 时检查播放时间，更新高亮行和滚动位置 */
  private tickLyric(): void {
    if (!this.isVisible) {
      return
    }
    if (!this.playState.isPlay) {
      return
    }
    if (this.isUserScrolling) {
      return
    }
    // 直接从播放器获取实时播放位置，避免 AppStorageV2.connect 在定时器闭包中无法拿到最新值
    const realTime = playerManager.player?.currentTime ?? this.playState.time
    const newIndex = this.computeCurrentIndex(realTime)
    if (newIndex !== this.currentIndex) {
      this.currentIndex = newIndex
      this.scrollToLyricIndex(newIndex)
    }
  }

  // ========== 核心逻辑 ==========

  /**
   * 根据当前播放时间计算当前歌词行索引（二分查找）
   * @param currentTime 当前播放时间，单位毫秒
   */
  computeCurrentIndex(currentTime: number): number {
    if (!this.lyrics || this.lyrics.length === 0) {
      return -1
    }
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
    return result
  }

  /**
   * 滚动 List 使 index 对应的歌词行位于可视区域中间偏上
   */
  private scrollToLyricIndex(index: number): void {
    if (index < 0 || index === this.lastScrolledIndex) {
      return
    }
    this.lastScrolledIndex = index
    // 让当前行位于可视区域上方 1/3 处（前移 4 行作为偏移）
    const targetIndex = Math.max(0, index - 4)
    this.scroller.scrollToIndex(targetIndex, true, ScrollAlign.START)
  }

  /**
   * 点击歌词行，跳转播放
   */
  onLyricLineClick(item: LyricItem) {
    playerManager.seekPlay(item.time)
    this.isUserScrolling = false
    this.lastScrolledIndex = -1 // 允许重新滚动到该位置
  }

  /**
   * 调整字体大小
   */
  adjustFontSize(delta: number) {
    const newSize = this.fontSize + delta
    if (newSize >= 12 && newSize <= 24) {
      this.fontSize = newSize
    }
  }

  /** 歌词数据变化时（切歌）重置状态 */
  @Monitor('lyrics')
  onLyricsChange() {
    this.currentIndex = -1
    this.lastScrolledIndex = -1
    this.isUserScrolling = false
    this.scroller?.scrollToIndex(0, true, ScrollAlign.START)
  }

  /**
   * 获取当前主题
   */
  getCurrentTheme(): LyricColorTheme {
    return COLOR_THEMES[this.themeIndex]
  }

  build() {
    Column() {
      if (!this.lyrics || this.lyrics.length === 0) {
        // 无歌词提示
        Column({ space: 12 }) {
          Image($r('app.media.ic_music'))
            .width(48)
            .fillColor('#88ffffff')
          Text('暂无歌词')
            .fontSize(15)
            .fontColor('#88ffffff')
          Text('纯音乐，请欣赏')
            .fontSize(12)
            .fontColor('#55ffffff')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Column() {
          // ========== 顶部工具栏 ==========
          Row() {
            // 返回唱片视图按钮
            Row({ space: 4 }) {
              Image($r('app.media.ic_back'))
                .width(16)
                .fillColor('#88ffffff')
              Text('唱片')
                .fontSize(12)
                .fontColor('#88ffffff')
            }
            .onClick(() => {
              if (this.onBackToDisc) {
                this.onBackToDisc()
              }
            })

            Blank()

            // 设置按钮
            Image($r('app.media.ic_more'))
              .width(20)
              .fillColor('#88ffffff')
              .onClick(() => {
                this.showSettings = !this.showSettings
              })
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 8, bottom: 4 })

          // ========== 设置面板 ==========
          if (this.showSettings) {
            Column({ space: 12 }) {
              // 字号调整
              Row({ space: 12 }) {
                Text('字号')
                  .fontSize(12)
                  .fontColor('#88ffffff')
                  .width(40)

                Row({ space: 8 }) {
                  Button('A-')
                    .fontSize(11)
                    .width(36)
                    .height(28)
                    .backgroundColor('#33ffffff')
                    .fontColor('#ffffff')
                    .borderRadius(14)
                    .onClick(() => this.adjustFontSize(-1))

                  Text(this.fontSize.toString())
                    .fontSize(14)
                    .fontColor(Color.White)
                    .width(30)
                    .textAlign(TextAlign.Center)

                  Button('A+')
                    .fontSize(11)
                    .width(36)
                    .height(28)
                    .backgroundColor('#33ffffff')
                    .fontColor('#ffffff')
                    .borderRadius(14)
                    .onClick(() => this.adjustFontSize(1))
                }
              }

              // 颜色主题
              Row({ space: 12 }) {
                Text('配色')
                  .fontSize(12)
                  .fontColor('#88ffffff')
                  .width(40)

                Row({ space: 8 }) {
                  ForEach(COLOR_THEMES, (theme: LyricColorTheme, idx: number) => {
                    Row() {
                      if (this.themeIndex === idx) {
                        Text('✓')
                          .fontSize(10)
                          .fontColor(theme.activeColor)
                      }
                    }
                    .width(28)
                    .height(28)
                    .borderRadius(14)
                    .backgroundColor(theme.activeColor + '33')
                    .border({
                      width: this.themeIndex === idx ? 2 : 0,
                      color: theme.activeColor,
                      radius: 14
                    })
                    .justifyContent(FlexAlign.Center)
                    .onClick(() => {
                      this.themeIndex = idx
                    })
                  })
                }
              }

              // 提示文字
              Text('点击歌词行可跳转播放')
                .fontSize(11)
                .fontColor('#55ffffff')
            }
            .width('100%')
            .padding({ left: 20, right: 20, top: 8, bottom: 12 })
            .backgroundColor('#22ffffff')
            .borderRadius(12)
            .margin({ left: 16, right: 16, bottom: 8 })
            .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
          }

          // ========== 歌词列表 ==========
          Column() {
            // 顶部占位（让第一句歌词初始时位于屏幕中部偏下）
            Blank()
              .height(80)

            List({ scroller: this.scroller }) {
              ForEach(this.lyrics, (item: LyricItem, index: number) => {
                ListItem() {
                  Text(item.text)
                    .fontSize(index === this.currentIndex ? this.fontSize + 3 : this.fontSize)
                    .fontWeight(index === this.currentIndex ? FontWeight.Bold : FontWeight.Normal)
                    .fontColor(index === this.currentIndex ?
                      this.getCurrentTheme().activeColor :
                    this.getCurrentTheme().inactiveColor)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                    .textAlign(TextAlign.Center)
                    .padding({ top: 10, bottom: 10, left: 20, right: 20 })
                    .animation({
                      duration: 300,
                      curve: Curve.EaseOut
                    })
                    .onClick(() => {
                      this.onLyricLineClick(item)
                    })
                }
                .width('100%')
              })
            }
            .width('100%')
            .layoutWeight(1)
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
            .onScrollStart(() => {
              this.isUserScrolling = true
              if (this.resumeScrollTimer !== -1) {
                clearTimeout(this.resumeScrollTimer)
              }
            })
            .onScrollStop(() => {
              if (this.resumeScrollTimer !== -1) {
                clearTimeout(this.resumeScrollTimer)
              }
              this.resumeScrollTimer = setTimeout(() => {
                this.isUserScrolling = false
                this.lastScrolledIndex = -1 // 重置，允许恢复后重新滚动
                this.resumeScrollTimer = -1
              }, 2000)
            })

            // 底部占位
            Blank()
              .height(80)
          }
          .width('100%')
          .layoutWeight(1)
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
  }
}
