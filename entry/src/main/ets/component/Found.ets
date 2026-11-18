// ==================== 导入歌曲数据 ====================
import { songs } from '../models/songData'
import {SongItemType} from '../models/music'
import { AppStorageV2 } from '@kit.ArkUI'
import { playerManager } from '../utils/AvPlayerManager'
import { PlayerState, getPlayerState } from '../models/PlayerState'
import { LikedStore, getLikedStore, preferencesService } from '../models/UserSettings'
import { playNextUp, shareSong } from '../utils/ShareHelper'
import { toast } from '../utils/Toast'

// 删掉@Entry
@ComponentV2
  // 使用V2状态管理
export struct Found {
  @Local currentIndex: number = -1
  // 加入歌单面板
  @Local isPickerOpen: boolean = false
  @Local pickerPlaylistNames: string[] = []
  @Local pickerSong: SongItemType | null = null
  // 「更多」操作菜单
  @Local isMenuOpen: boolean = false
  @Local menuSong: SongItemType | null = null

  pathStack: NavPathStack = AppStorageV2.connect(NavPathStack,'navStack', ()=> new NavPathStack())!  // !非空断言

  playState: PlayerState = getPlayerState()
  // 喜欢的歌曲（与播放页红心共用）
  likedStore: LikedStore = getLikedStore()

  /** 是否已喜欢 */
  isLiked(song: SongItemType): boolean {
    return this.likedStore.likedSongIds.includes(song.id)
  }

  /** 收藏 / 取消收藏 */
  toggleFav(song: SongItemType) {
    const liked = preferencesService.toggleLiked(song.id)
    toast({ message: liked ? `已收藏《${song.name}》` : '已取消收藏', duration: 1200 })
  }

  /** 加入歌单：把歌曲写入指定歌单并落盘 */
  addToPlaylist(song: SongItemType, playlistName: string) {
    preferencesService.addSongToPlaylist(song, playlistName).then((ok: boolean) => {
      toast({
        message: ok ? `已加入「${playlistName}」` : `「${playlistName}」暂不可添加`,
        duration: 1200
      })
    })
  }

  /** 下一首播放 */
  playNext(song: SongItemType) {
    const ok = playNextUp(song)
    toast({
      message: ok ? `《${song.name}》已加入下一首播放` : '加入失败',
      duration: 1200
    })
  }

  /** 打开「加入歌单」选择面板 */
  openPlaylistPicker(song: SongItemType) {
    preferencesService.getPlaylistNames()
      .then((names: string[]) => {
        if (names.length === 0) {
          toast({ message: '还没有创建歌单，去"我的"新建一个吧', duration: 1500 })
          return
        }
        this.pickerPlaylistNames = names
        this.pickerSong = song
        this.isPickerOpen = true
      })
      .catch(() => {
        toast({ message: '读取歌单失败', duration: 1200 })
      })
  }

  /** 底部操作面板（「更多」按钮触发：收藏 / 加入歌单 / 下一首播放 / 分享） */
  @Builder
  songActionSheet() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#99000000')
        .onClick(() => {
          this.isMenuOpen = false
        })

      Column() {
        // 歌曲信息
        Row({ space: 12 }) {
          Image(this.menuSong?.img ?? '')
            .width(44)
            .height(44)
            .borderRadius(8)
            .objectFit(ImageFit.Cover)
          Column({ space: 4 }) {
            Text(this.menuSong?.name ?? '')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.menuSong?.author ?? '')
              .fontSize(12)
              .fontColor(Color.Gray)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Image($r('app.media.ic_close'))
            .width(20)
            .height(20)
            .fillColor('#a49a9a')
            .onClick(() => {
              this.isMenuOpen = false
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 12 })

        Divider()
          .strokeWidth(0.5)
          .color('#33ffffff')

        // 操作项
        this.actionRow(this.isMenuOpen && this.menuSong ? (this.isLiked(this.menuSong) ? '取消收藏' : '收藏') : '收藏', () => {
          if (this.menuSong) {
            this.toggleFav(this.menuSong)
          }
          this.isMenuOpen = false
        })
        this.actionRow('加入歌单', () => {
          const song = this.menuSong
          this.isMenuOpen = false
          if (song) {
            this.openPlaylistPicker(song)
          }
        })
        this.actionRow('下一首播放', () => {
          const song = this.menuSong
          this.isMenuOpen = false
          if (song) {
            this.playNext(song)
          }
        })
        this.actionRow('分享', () => {
          const song = this.menuSong
          this.isMenuOpen = false
          if (song) {
            shareSong(song)
          }
        })

        Column().height(20)
      }
      .width('100%')
      .backgroundColor('#ff262626')
      .borderRadius({ topLeft: 16, topRight: 16 })
      .transition(TransitionEffect.translate({ y: 400 }).animation({ duration: 300, curve: Curve.EaseOut }))
    }
    .width('100%')
    .height('100%')
    .position({ x: 0, y: 0 })
    .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
  }

  /** 单个操作行 */
  @Builder
  actionRow(label: string, action: () => void) {
    Row() {
      Text(label)
        .fontSize(15)
        .fontColor(Color.White)
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 16 })
    .onClick(() => {
      action()
    })
  }

  /** 加入歌单选择面板 */
  @Builder
  playlistPicker() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#99000000')
        .onClick(() => {
          this.isPickerOpen = false
        })

      Column() {
        Row() {
          Text('加入歌单')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .layoutWeight(1)
          Image($r('app.media.ic_close'))
            .width(20)
            .height(20)
            .fillColor('#a49a9a')
            .onClick(() => {
              this.isPickerOpen = false
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 12 })

        List() {
          ForEach(this.pickerPlaylistNames, (name: string) => {
            ListItem() {
              Row({ space: 12 }) {
                Image($r('app.media.ic_moment'))
                  .width(20)
                  .height(20)
                  .fillColor('#ff5186')
                Text(name)
                  .fontSize(15)
                  .fontColor(Color.White)
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Image($r('app.media.ic_more'))
                  .width(16)
                  .height(16)
                  .fillColor('#666666')
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 14, bottom: 14 })
              .onClick(() => {
                this.isPickerOpen = false
                if (this.pickerSong) {
                  this.addToPlaylist(this.pickerSong, name)
                }
              })
            }
          }, (name: string) => `picker_${name}`)
        }
        .width('100%')
        .height(240)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .backgroundColor('#ff262626')
      .borderRadius({ topLeft: 16, topRight: 16 })
      .transition(TransitionEffect.translate({ y: 400 }).animation({ duration: 300, curve: Curve.EaseOut }))
    }
    .width('100%')
    .height('100%')
    .position({ x: 0, y: 0 })
    .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
  }


  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      this.songList()
      // 「更多」操作面板
      if (this.isMenuOpen) {
        this.songActionSheet()
      }
      // 加入歌单选择面板
      if (this.isPickerOpen) {
        this.playlistPicker()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  songList() {
    // 根列容器：深色背景，全屏沉浸式
    Column() {
      // ============ List 可滚动列表 ============
      // space: 控制 ListItem 之间的垂直间距
      List({ space: 20 }) {
        ListItem() {
          Row() {
            Text('猜你喜欢')
              .fontColor(Color.White)
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
          }
          .padding({left:16,top:8})
          .width('100%')
        }


        // 遍历歌曲数据，渲染每个列表项
        ForEach(songs, (item: SongItemType, index: number) => {

          ListItem() {
            // 行容器：左侧封面 | 中间信息 | 右侧更多按钮
            Row({ space: 10 }) {
              // ===== 左侧：歌曲封面图片 =====
              Stack() {
                Image(item.img)
                  .width(100)          // 固定宽度
                  .borderRadius(10) // 圆角
                // 错误写法
                // Image(this.currentIndex === index ? $r('app.media.wave') : '')
                //   .width(30)
                // if (this.currentIndex === index) {
                //   Image($r('app.media.wave'))
                //     .width(30)
                // }
                // 条件渲染，是否播放资源跟当前数组里歌曲的一致， 以及是否正在播放
                if (this.playState.url === item.url && this.playState.isPlay) {
                  Image($r('app.media.wave'))
                    .width(30)
                }


              }


              // ===== 中间：歌曲信息（占据剩余空间） =====
              Column({ space: 20 }) {
                // 歌名
                Text(item.name)
                  .fontColor(Color.White)
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)

                // 标签行：VIP 标签 + 歌手名
                Row({ space: 10 }) {
                  // VIP 标签：黄色边框圆角
                  Text('VIP')
                    .padding({
                      left: 6,
                      right: 6,
                      top: 3,
                      bottom: 3
                    })
                    .fontColor(Color.Yellow)
                    .fontSize(12)
                    .border({
                      width: 1,
                      color: Color.Yellow,
                      radius: 20    // 圆角边框
                    })

                  // 歌手名
                  Text(item.author)
                    .fontColor(Color.Gray)
                    .fontSize(14)
                }

                // 占位：将内容顶到顶部
                /////////////////////////////
                // Blank()
              }
              .alignItems(HorizontalAlign.Start) // 左对齐
              .layoutWeight(1) // 占据剩余空间

              // ===== 右侧：更多操作按钮 =====
              // 行点击负责播放，图标单独绑定点击菜单（不冒泡到整行）
              Image($r('app.media.ic_more'))
                .width(20)
                .fillColor(Color.White) // 白色图标
                .padding(6)
                .onClick(() => {
                  this.menuSong = item
                  this.isMenuOpen = true
                })
            }
            .width('100%') // 占满列表宽度
            // 长按整行：打开同一个操作面板
            .gesture(
              LongPressGesture()
                .onAction(() => {
                  this.menuSong = item
                  this.isMenuOpen = true
                })
            )
          }
          .width('100%') // ListItem 占满宽度
          // 点击列表项播放（与「更多」图标的点击相互独立）
          .onClick(() => {
            if (this.currentIndex === index) {
              this.currentIndex = -1
            } else {
              this.currentIndex = index
              toast({
                message: `正在播放: ${item.name}`,
                duration: 1000,
                bottom: 680
              })
            }
            playerManager.singPlay(item)
            this.pathStack.pushPathByName('Play', null, true)
          })




        }, (item: SongItemType) => item.id)

        ListItem(){
          Text('没有更多了...')
            .fontSize(16)
            .fontWeight(600)
            .fontColor(Color.Gray)
            .margin({bottom:20})
        }
        .width('100%')
      }
      // List 滚动条配置
      .scrollBarColor(Color.Gray) // 滚动条颜色：白色
      .scrollBar(BarState.Auto) // 滚动条状态：自动显示

      // 分隔线配置（已注释，可按需启用）
      // .divider({
      //   strokeWidth: 1,       // 分隔线宽度
      //   color: Color.White,   // 分隔线颜色
      //   startMargin: 15,      // 起始边距
      //   endMargin: 15         // 结束边距
      // })


      .padding({left:10, right:10, top:10}) // 列表内边距
      .width('100%')
      .height('100%')
    }
    // ===== 沉浸式全屏配置 =====
    // expandSafeArea：内容扩展到系统安全区
    // - SafeAreaType.SYSTEM：系统状态栏、导航栏区域
    // - SafeAreaEdge.TOP / BOTTOM：顶部和底部
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

    // 深色主题背景
    .backgroundColor('#131313')
    .height('100%')
    .width('100%')
  }
}