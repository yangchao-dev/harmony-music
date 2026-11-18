import { PlayerState, getPlayerState } from "../models/PlayerState"
import { SongItemType } from "../models/music"
//import { songs } from './models/songDate'
import { playerManager } from '../utils/AvPlayerManager'
import { toast } from '../utils/Toast'
import { LyricView } from '../component/LyricView'
import { formatDuration, timeToRecordAngle } from '../utils/Formatter'
import { LikedStore, getLikedStore, preferencesService } from '../models/UserSettings'
import {
  CommentItem,
  baseCommentCount,
  baseLikeCount,
  createComments
} from '../models/SearchModels'
import { formatCount } from '../utils/Formatter'
import { shareSong } from '../utils/ShareHelper'
//import { getLyricBySongName } from './models/lyricData'

// 跳转页面入口函数
@Builder
export function PlayBuilder() {
  Play()
}

const NEEDLE_PLAY_ANGLE: number = -7
const NEEDLE_PAUSE_ANGLE: number = -30

/** 唱片角速度：每秒钟旋转的角度（度），约 12 秒一圈，接近真实黑胶 */
const DISC_DEGREE_PER_SECOND: number = 30

@ComponentV2
struct Play {
  pathStack: NavPathStack = new NavPathStack();
  // 当前播放的歌曲
  playState: PlayerState = getPlayerState()
  // 全局喜欢的歌曲（与「我的-我喜欢的音乐」共用同一份数据）
  likedStore: LikedStore = getLikedStore()
  // 播放列表面板
  @Local isPanelOpen: boolean = false
  // 是否显示歌词视图（点击唱片区域切换）
  @Local showLyric: boolean = false
  // 唱片旋转角度（由 playState.time 单一数据源驱动，不再用轮询定时器）
  @Local recordAngle: number = 0
  // 唱针角度：播放时 -30，暂停时 -55
  @Local needleAngle: number = -55

  // ===== 评论面板 =====
  @Local isCommentOpen: boolean = false
  @Local comments: CommentItem[] = []
  @Local commentInput: string = ''
  // 本地点赞过的评论 id
  @Local likedCommentIds: string[] = []
  // 当前评论面板对应的歌曲名
  @Local commentSongName: string = ''

  aboutToAppear() {
    this.needleAngle = this.playState.isPlay ? NEEDLE_PLAY_ANGLE : NEEDLE_PAUSE_ANGLE
    // 恢复播放时按当前进度立即对齐唱片角度，避免从上一首的角度跳变
    this.syncRecordAngle(this.playState.time)
  }

  /**
   * 单一数据源：监听播放时间变化驱动唱片旋转。
   * timeUpdate 才会更新 playState.time，暂停时 time 不变 → 唱片自然停转，无需额外定时器。
   */
  @Monitor('playState.time')
  onTimeChange() {
    this.syncRecordAngle(this.playState.time)
  }

  /** 监听播放状态变化驱动唱针抬起/落下 */
  @Monitor('playState.isPlay')
  onPlayStateChange() {
    this.needleAngle = this.playState.isPlay ? NEEDLE_PLAY_ANGLE : NEEDLE_PAUSE_ANGLE
  }

  /** 根据播放进度换算唱片角度（实现见 utils/Formatter.ets） */
  syncRecordAngle(timeMs: number) {
    this.recordAngle = timeToRecordAngle(timeMs, DISC_DEGREE_PER_SECOND)
  }

  /** 播放时长格式化 mm:ss（实现见 utils/Formatter.ets） */
  number2time(number: number): string {
    return formatDuration(number)
  }

  /** 当前歌曲是否已喜欢 */
  isCurrentLiked(): boolean {
    const id = this.currentSongId()
    return id.length > 0 && this.likedStore.likedSongIds.includes(id)
  }

  /** 当前歌曲 id */
  private currentSongId(): string {
    const song = this.playState.playList[this.playState.playIndex]
    return song ? song.id : ''
  }

  /** 点击红心：切换喜欢状态并落盘 */
  toggleLike() {
    const id = this.currentSongId()
    if (!id) {
      return
    }
    const liked = preferencesService.toggleLiked(id)
    toast({
      message: liked ? '已添加到我喜欢的音乐' : '已取消喜欢',
      duration: 1000
    })
  }

  /** 点赞数：基础数 + 本人点赞（替代硬编码的 10w+） */
  likeCount(): number {
    const base = baseLikeCount(this.currentSongId())
    return this.isCurrentLiked() ? base + 1 : base
  }

  /** 评论数：基础数 + 本人新增的评论 */
  commentCount(): number {
    const base = baseCommentCount(this.currentSongId())
    const extra = this.comments.filter((c: CommentItem) => c.author === '我').length
    return base + extra
  }

  /** 数字格式化：1.2w / 999 */
  formatNumber(num: number): string {
    if (num >= 10000) {
      return (num / 10000).toFixed(1) + 'w'
    }
    return num.toString()
  }

  /** 打开评论面板 */
  openCommentPanel() {
    const songId = this.currentSongId()
    if (!songId) {
      return
    }
    this.commentSongName = this.playState.name
    this.comments = createComments(songId, baseCommentCount(songId))
    this.commentInput = ''
    this.isCommentOpen = true
  }

  /** 发表评论（本地插入到顶部） */
  sendComment() {
    const text = this.commentInput.trim()
    if (text.length === 0) {
      toast({ message: '说点什么吧', duration: 1000 })
      return
    }
    const item: CommentItem = {
      id: `local_${Date.now()}`,
      author: '我',
      avatar: 'https://yjy-teach-oss.oss-cn-beijing.aliyuncs.com/HeimaCloudMusic/h0.jpg',
      content: text,
      like: 0,
      time: '刚刚'
    }
    this.comments = [item, ...this.comments]
    this.commentInput = ''
    toast({ message: '评论成功', duration: 1000 })
  }

  /** 评论点赞切换 */
  toggleCommentLike(item: CommentItem) {
    const liked = this.likedCommentIds.includes(item.id)
    if (liked) {
      this.likedCommentIds = this.likedCommentIds.filter((id: string) => id !== item.id)
      item.like = Math.max(0, item.like - 1)
    } else {
      this.likedCommentIds = [...this.likedCommentIds, item.id]
      item.like = item.like + 1
    }
    // 触发列表刷新
    this.comments = [...this.comments]
  }

  /** 分享当前歌曲：优先系统分享面板，失败退回复制 */
  doShare() {
    const song = this.playState.playList[this.playState.playIndex]
    shareSong(song)
  }

  // ========== 评论面板 ==========
  @Builder
  commentPanel() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#99000000')
        .onClick(() => {
          this.isCommentOpen = false
        })

      Column() {
        // 头部
        Row() {
          Column({ space: 2 }) {
            Text(`评论 (${this.formatNumber(this.commentCount())})`)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
            Text(this.commentSongName)
              .fontSize(11)
              .fontColor(Color.Gray)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Image($r('app.media.ic_close'))
            .width(22)
            .height(22)
            .fillColor('#a49a9a')
            .onClick(() => {
              this.isCommentOpen = false
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 12 })

        Divider()
          .strokeWidth(0.5)
          .color('#22ffffff')

        // 评论列表
        List() {
          ForEach(this.comments, (item: CommentItem) => {
            ListItem() {
              Row({ space: 10 }) {
                Image(item.avatar)
                  .width(34)
                  .height(34)
                  .borderRadius(17)
                  .objectFit(ImageFit.Cover)
                  .alignSelf(ItemAlign.Start)

                Column({ space: 6 }) {
                  Row({ space: 8 }) {
                    Text(item.author)
                      .fontSize(13)
                      .fontColor(item.author === '我' ? '#ff5186' : '#b0b0b0')
                      .fontWeight(FontWeight.Medium)
                    Text(item.time)
                      .fontSize(11)
                      .fontColor('#6a6a6a')
                  }

                  Text(item.content)
                    .fontSize(14)
                    .fontColor(Color.White)
                    .lineHeight(20)

                  // 点赞
                  Row({ space: 4 }) {
                    Image($r('app.media.ic_like'))
                      .width(14)
                      .height(14)
                      .fillColor(this.likedCommentIds.includes(item.id) ? '#ff5186' : '#6a6a6a')
                    Text(item.like > 0 ? this.formatNumber(item.like) : '赞')
                      .fontSize(11)
                      .fontColor(this.likedCommentIds.includes(item.id) ? '#ff5186' : '#6a6a6a')
                  }
                  .onClick(() => {
                    this.toggleCommentLike(item)
                  })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
            }
          }, (item: CommentItem) => item.id)

          if (this.comments.length === 0) {
            ListItem() {
              Column({ space: 8 }) {
                Text('还没有评论')
                  .fontSize(13)
                  .fontColor('#6a6a6a')
                Text('来抢第一个沙发吧')
                  .fontSize(12)
                  .fontColor('#4a4a4a')
              }
              .width('100%')
              .padding({ top: 40, bottom: 40 })
              .alignItems(HorizontalAlign.Center)
            }
          }
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)

        // 输入框
        Row({ space: 10 }) {
          TextInput({ text: $$this.commentInput, placeholder: '说点什么…' })
            .layoutWeight(1)
            .height(40)
            .fontSize(14)
            .fontColor(Color.White)
            .placeholderColor('#6a6a6a')
            .backgroundColor('#332f2f')
            .borderRadius(20)
            .onSubmit(() => {
              this.sendComment()
            })

          Button('发送')
            .fontSize(13)
            .height(36)
            .fontColor(Color.White)
            .backgroundColor(this.commentInput.trim().length > 0 ? '#ff5186' : '#4a4a4a')
            .borderRadius(18)
            .enabled(this.commentInput.trim().length > 0)
            .onClick(() => {
              this.sendComment()
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 20 })
      }
      .width('100%')
      .height('65%')
      .backgroundColor('#ff262626')
      .borderRadius({ topLeft: 20, topRight: 20 })
      .transition(TransitionEffect.translate({ y: 600 }).animation({ duration: 300, curve: Curve.EaseOut }))
    }
    .width('100%')
    .height('100%')
    .position({ x: 0, y: 0 })
    .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
  }

  @Builder
  deleteButton(index: number) {
    Button('删除')
      .backgroundColor('#ec5c87')
      .fontColor('#fff')
      .width(80)
      .height('100%')
      .type(ButtonType.Normal)
      .onClick(()=>{
        // 接收要删除的索引
        playerManager.removeSong(index)
        // 播放列表没有歌曲的时候返回上一页
        if (this.playState.playList.length === 0) {
          this.pathStack.pop()
        }

      })
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        // 主内容
        Stack() {
          // 变色背景
          Image(this.playState.img)
            .width('100%')
            .height('100%')
            .blur(1000)
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

          // 暗色遮罩，让文字更清晰
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('#44000000')
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

          // 内容
          Column() {
            // 顶部栏：返回 + 分享
            Row() {
              Image($r('app.media.ic_back'))
                .width(24)
                .fillColor(Color.White)
                .onClick(() => {
                  this.pathStack.pop()
                })

              Blank()

              Image($r('app.media.ic_share'))
                .width(24)
                .fillColor(Color.White)
                .onClick(() => {
                  this.doShare()
                })
            }
            .width('100%')
            .padding(16)


            // 唱片 / 歌词 切换区域
            Stack() {
              if (this.showLyric) {
                // 歌词视图（内部有"唱片"按钮返回）
                LyricView({
                  lyrics: this.playState.lyrics,
                  isVisible: this.showLyric,
                  onBackToDisc: () => {
                    this.showLyric = false
                  }
                })
                  .width('100%')
                  .height('100%')
              } else {
                // 唱片 + 唱针
                Stack({ alignContent: Alignment.Top }) {
                  // 黑胶唱片（使用 ic_cd 背景）
                  Row() {
                    Row() {
                      Image(this.playState.img)
                        .width('70%')
                        .borderRadius(400)
                    }
                    .backgroundImage($r('app.media.disk'))
                    .backgroundImageSize(ImageSize.Cover)
                    .justifyContent(FlexAlign.Center)
                    .width('100%')
                    .borderRadius(400)
                    .clip(true)
                    .aspectRatio(1)
                  }
                  .margin({ top: 50 })
                  .width('90%')
                  .aspectRatio(1)
                  .justifyContent(FlexAlign.Center)
                  .padding(24)
                  .rotate({ angle: this.recordAngle })
                  // 属性动画平滑跟随 time 变化，替代 25ms 定时器逐帧赋值
                  .animation({ duration: 300, curve: Curve.Linear })

                  // 唱针
                  Image($r('app.media.ic_stylus_2'))
                    .width(100)

                    .rotate({
                      angle: this.needleAngle,
                      centerX: 15,
                      centerY: 15
                    })
                    .animation({
                      duration: 500,
                      curve: Curve.EaseInOut
                    })

                    .margin({left: 70})
                }
                .width('100%')
                .height('100%')
                .onClick(() => {
                  this.showLyric = true
                })
              }
            }
            .width('100%')
            .layoutWeight(1)

            // 歌曲信息 + 点赞/评论
            Row() {
              Column({ space: 6 }) {
                // 歌名 + VIP
                Row({ space: 8 }) {
                  Text(this.playState.name)
                    .fontSize(22)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Color.White)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.MARQUEE })
                    .marqueeOptions({
                      start: true,
                      step: 3,
                      loop: -1,
                      fromStart: true
                    })
                    .constraintSize({ maxWidth: '80%' })

                  Text('VIP')
                    .fontSize(10)
                    .fontColor('#bba46b')
                    .backgroundColor('#33bba46b')
                    .padding({
                      left: 4,
                      right: 4,
                      top: 2,
                      bottom: 2
                    })
                    .borderRadius(4)
                }

                // 歌手
                Row({ space: 4 }) {
                  Text(this.playState.author)
                    .fontSize(14)
                    .fontColor('#cccccc')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })


                }
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              // 点赞/评论
              Row({ space: 26 }) {
                Stack() {
                  Image($r('app.media.ic_like_2'))
                    .width(30)
                    .fillColor(this.isCurrentLiked() ? '#ff5186' : Color.White)
                    .animation({ duration: 200 })
                  // 真实点赞数：基础值 + 本人点赞
                  Text(this.formatNumber(this.likeCount()))
                    .fontSize(11)
                    .fontWeight(500)
                    .fontColor(this.isCurrentLiked() ? '#ff5186' : Color.White)
                    .position({x:20,y:0})
                }
                .onClick(() => {
                  this.toggleLike()
                })

                Stack() {
                  Image($r('app.media.ic_comment_2'))
                    .width(30)
                    .fillColor(Color.White)
                  Text(this.formatNumber(this.commentCount()))
                    .fontSize(11)
                    .fontWeight(500)
                    .fontColor(Color.White)
                    .position({x:20,y:0})
                }
                .onClick(() => {
                  this.openCommentPanel()
                })
              }
              .margin({right:10})
            }
            .width('100%')
            .padding({
              left: 24,
              right: 24,
              top: 6,
              bottom: 6
            })
            .alignItems(VerticalAlign.Center)

            // 进度条
            Column({ space: 4 }) {
              Slider({
                value: this.playState.time,
                min: 0,
                // duration 为 0（未加载完成）时给一个默认最大值，避免 max=0 导致滑块异常
                max: this.playState.duration > 0 ? this.playState.duration : 1
              })
                .width('100%')
                .blockColor(Color.White)
                .selectedColor(Color.White)
                .trackColor('#55ffffff')
                .trackThickness(2)
                .enabled(this.playState.duration > 0)
                .onChange((value: number, mode: SliderChangeMode) => {
                  if (mode === SliderChangeMode.Moving || mode === SliderChangeMode.Click) {
                    // 拖动时实时更新时间显示
                    this.playState.time = value
                  }
                  if (mode === SliderChangeMode.End) {
                    playerManager.seekPlay(value)
                  }
                })

              Row() {
                Text(this.number2time(this.playState.time))
                  .fontSize(11)
                  .fontColor('#cccccc')

                Text('高清臻音')
                  .fontSize(10)
                  .fontColor('#cccccc')

                Text(this.number2time(this.playState.duration))
                  .fontSize(11)
                  .fontColor('#cccccc')
              }
              .width('100%')
              .justifyContent(FlexAlign.SpaceBetween)
            }
            .width('100%')
            .padding({
              left: 24,
              right: 24,
              top: 8,
              bottom: 8
            })

            // 底部控制区
            Row() {
              // 播放模式
              if (this.playState.playMode === 'auto') {
                Image($r('app.media.ic_auto'))
                  .width(26)
                  .fillColor('#ebbfc0c8')
                  .onClick(() => {
                    this.playState.playMode = 'random'
                    toast({
                      message: '随机播放',
                      duration: 500,
                      bottom: 650,
                      backgroundBlurStyle: BlurStyle.Thin,
                      textColor: Color.White
                    })
                  })
              } else if (this.playState.playMode === 'random') {
                Image($r('app.media.ic_random'))
                  .width(26)
                  .fillColor('#ebbfc0c8')
                  .onClick(() => {
                    this.playState.playMode = 'repeat'
                    toast({
                      message: '单曲循环',
                      duration: 500,
                      bottom: 650,
                      backgroundBlurStyle: BlurStyle.Thin,
                      textColor: Color.White
                    })
                  })
              } else {
                Image($r('app.media.ic_repeat'))
                  .width(26)
                  .fillColor('#ebbfc0c8')
                  .onClick(() => {
                    this.playState.playMode = 'auto'
                    toast({
                      message: '顺序播放',
                      duration: 500,
                      bottom: 650,
                      backgroundBlurStyle: BlurStyle.Thin,
                      textColor: Color.White
                    })
                  })
              }


              // 上一首
              Image($r("app.media.ic_prev_2"))
                .width(40)
                .fillColor(Color.White)
                .onClick(() => {
                  playerManager.prevPlay()
                })

              // 播放按钮
              Image(this.playState.isPlay ? $r('app.media.ic_paused_2') : $r('app.media.ic_play_2'))
                .width(56)
                .fillColor(Color.White)
                .onClick(() => {
                  playerManager.playOrPause()
                })

              // 下一首
              Image($r('app.media.ic_next_2'))
                .width(40)
                .fillColor(Color.White)
                .onClick(() => {
                  playerManager.nextPlay(false)
                })

              // 播放列表
              Image($r('app.media.ic_song_list_2'))
                .width(28)
                .fillColor(Color.White)
                .onClick(() => {
                  this.isPanelOpen = true
                })
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceAround)
            .padding({
              left: 16,
              right: 16,
              bottom: 32,
              top: 16
            })
          }
          .width('100%')
          .height('100%')
        }
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        // 播放列表面板（从底部向上展开）
        if (this.isPanelOpen) {
          Stack({ alignContent: Alignment.Bottom }) {
            // 点击遮罩收起
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor('#99000000')
              .expandSafeArea([SafeAreaType.SYSTEM],[SafeAreaEdge.TOP])
              .onClick(() => {
                this.isPanelOpen = false
              })

            // 列表面板
            Column() {
              Row() {
                Row() {
                  Image($r("app.media.ic_play"))
                    .width(20)
                    .fillColor('#ff5186')
                }
                .width(50)
                .aspectRatio(1)
                .justifyContent(FlexAlign.Center)

                Row({ space: 8 }) {
                  Text(`播放列表 (${this.playState.playList.length})`)
                    .fontColor(Color.White)
                    .fontSize(14)
                }
                .layoutWeight(1)

                Image($r('app.media.ic_close'))
                  .fillColor('#ffa49a9a')
                  .width(24)
                  .height(24)
                  .margin({ right: 16 })
                  .onClick(() => {
                    this.isPanelOpen = false
                  })
              }
              .width('100%')
              .padding(8)
              .border({
                width: { bottom: 1 },
                color: '#12ec5c87'
              })

              // 播放列表
              List() {
                ForEach(this.playState.playList, (item: SongItemType, index: number) => {
                  ListItem() {
                    Row() {
                      Row() {
                        if (this.playState.playIndex === index) {
                          Image($r('app.media.wave'))
                            .width(10)
                        }else {
                          Text((index + 1).toString())
                            .fontColor('#ffa49a9a')
                        }

                      }
                      .width(50)
                      .aspectRatio(1)
                      .justifyContent(FlexAlign.Center)

                      // 列表
                      Row({ space: 10 }) {
                        Column() {
                          Text(item.name)
                            .fontSize(14)
                            .fontColor(this.playState.playIndex === index ? '#ffe31b7b' : '#ffa49a9a')
                          Text(item.author)
                            .fontSize(12)
                            .fontColor(Color.Gray)
                        }
                        .layoutWeight(1)
                        .alignItems(HorizontalAlign.Start)
                        .justifyContent(FlexAlign.Center)
                      }
                      .layoutWeight(1)

                      Image($r('app.media.ic_more'))
                        .width(24)
                        .height(24)
                        .margin({ right: 16 })
                        .fillColor(Color.Gray)
                    }
                    .alignItems(VerticalAlign.Center)
                    // 添加播放列表点击事件 播放歌曲
                    .onClick(()=>{
                      playerManager.singPlay(item)
                    })
                  }
                  .swipeAction({
                    end: this.deleteButton(index)
                  })
                  .border({
                    width: { bottom: 1 },
                    color: '#12ec5c87'
                  })
                })
              }
              .layoutWeight(1)
              .backgroundColor('#ff353333')
              .expandSafeArea([SafeAreaType.SYSTEM],[SafeAreaEdge.BOTTOM])
            }
            .width('100%')
            .height(400)
            .backgroundColor('#ff353333')
            .borderRadius({ topLeft: 20, topRight: 20 })
            .transition(TransitionEffect.translate({ y: 400 }).animation({ duration: 300, curve: Curve.EaseOut }))
          }
          .width('100%')
          .height('100%')
          .position({ x: 0, y: 0 })
          .transition(TransitionEffect.OPACITY.animation({ duration: 300 }))
        }

        // 评论面板（从底部向上展开）
        if (this.isCommentOpen) {
          this.commentPanel()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)

    }
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack
    })
    .backgroundColor(Color.Transparent)
    .hideTitleBar(true) // 隐藏标题栏

  }
}
