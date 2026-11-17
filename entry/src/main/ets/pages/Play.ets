import { GlobalMusic } from "../models/globalMusic"
import { SongItemType } from "../models/music"
//import { songs } from './models/songDate'
import { AppStorageV2, promptAction } from "@kit.ArkUI"
import { playerManager } from '../utils/AvPlayerManager'
import { LyricView } from '../component/LyricView'
//import { getLyricBySongName } from './models/lyricData'

// 跳转页面入口函数
@Builder
export function PlayBuilder() {
  Play()
}

const NEEDLE_PLAY_ANGLE: number = -7
const NEEDLE_PAUSE_ANGLE: number = -30

@ComponentV2
struct Play {
  pathStack: NavPathStack = new NavPathStack();
  // 当前播放的歌曲
  @Local
  playState: GlobalMusic = AppStorageV2.connect(GlobalMusic, 'SONG_KEY', () => new GlobalMusic())!
  // 播放列表面板
  @Local isPanelOpen: boolean = false
  // 是否显示歌词视图（点击唱片区域切换）
  @Local showLyric: boolean = false
  // 唱片旋转角度
  @Local recordAngle: number = 0
  // 唱针角度：播放时 -30，暂停时 -55
  @Local needleAngle: number = -55
  private rotateTimer: number = -1

  aboutToAppear() {
    this.needleAngle = this.playState.isPlay ? NEEDLE_PLAY_ANGLE : NEEDLE_PAUSE_ANGLE
    this.startRotate()
  }

  aboutToDisappear() {
    this.stopRotate()
  }

  startRotate() {
    this.stopRotate()
    let lastPlayState = this.playState.isPlay
    this.rotateTimer = setInterval(() => {
      if (this.playState.isPlay) {
        this.recordAngle = (this.recordAngle + 1) % 360
      }
      if (this.playState.isPlay !== lastPlayState) {
        lastPlayState = this.playState.isPlay
        this.needleAngle = this.playState.isPlay ? NEEDLE_PLAY_ANGLE : NEEDLE_PAUSE_ANGLE
      }
    }, 25)
  }

  stopRotate() {
    if (this.rotateTimer !== -1) {
      clearInterval(this.rotateTimer)
      this.rotateTimer = -1
    }
  }

  number2time(number: number) {
    // 毫秒 → 秒 → 分+秒; 先判断是否大于1分钟
    if (number > 60 * 1000) {
      const s = Math.floor(number / 1000 % 60)
      const m = Math.floor(number / 1000 / 60)
      const second = s.toString().padStart(2, '0')
      const minute = m.toString().padStart(2, '0')
      return minute + ':' + second
    } else {
      const s = Math.floor(number / 1000 % 60)
      const second = s.toString().padStart(2, '0')
      return '00:' + second
    }
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
                    .fillColor(Color.White)
                  Text('10w+')
                    .fontSize(11)
                    .fontWeight(500)
                    .fontColor(Color.White)
                    .position({x:20,y:0})
                }

                Stack() {
                  Image($r('app.media.ic_comment_2'))
                    .width(30)
                    .fillColor(Color.White)
                  Text('1w+')
                    .fontSize(11)
                    .fontWeight(500)
                    .fontColor(Color.White)
                    .position({x:20,y:0})
                }
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
                max: this.playState.duration
              })
                .width('100%')
                .blockColor(Color.White)
                .selectedColor(Color.White)
                .trackColor('#55ffffff')
                .trackThickness(2)
                .onChange((value: number, mode: SliderChangeMode) => {
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
                    promptAction.showToast({
                      message: '随机播放',
                      duration: 500,
                      bottom: 650,
                      backgroundBlurStyle: BlurStyle.Thin,
                      textColor: Color.White,

                    })
                  })
              } else if (this.playState.playMode === 'random') {
                Image($r('app.media.ic_random'))
                  .width(26)
                  .fillColor('#ebbfc0c8')
                  .onClick(() => {
                    this.playState.playMode = 'repeat'
                    promptAction.showToast({
                      message: '单曲循环',
                      duration: 500,
                      bottom: 650,
                      backgroundBlurStyle: BlurStyle.Thin,
                      textColor: Color.White,

                    })

                  })
              } else {
                Image($r('app.media.ic_repeat'))
                  .width(26)
                  .fillColor('#ebbfc0c8')
                  .onClick(() => {
                    this.playState.playMode = 'auto'
                    promptAction.showToast({
                      message: '顺序播放',
                      duration: 500,
                      bottom: 650,
                      backgroundBlurStyle: BlurStyle.Thin,
                      textColor: Color.White,

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
