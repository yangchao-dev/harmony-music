import { momentList } from '../models/momentData'
import { MomentListType, SongItemType } from '../models/music'
import { formatCount } from '../utils/Formatter'
import { CommentItem, createComments } from '../models/SearchModels'
import { sharePlainText } from '../utils/ShareHelper'
import { AppStorageV2 } from '@kit.ArkUI'
import { playerManager } from '../utils/AvPlayerManager'
import { toast } from '../utils/Toast'

/** 动态唯一 key（作者 + 内容） */
function momentKey(item: MomentListType): string {
  return item.author + item.content
}

@ComponentV2
export struct Moment {
  // 已点赞的动态 key
  @Local likedKeys: string[] = []
  // 已发表的动态评论：key → 评论列表
  @Local localComments: Record<string, CommentItem[]> = {}
  // 评论面板
  @Local isCommentOpen: boolean = false
  @Local commentTarget: MomentListType | null = null
  @Local commentList: CommentItem[] = []
  @Local commentInput: string = ''
  @Local likedCommentIds: string[] = []

  pathStack: NavPathStack = AppStorageV2.connect(NavPathStack, 'navStack', () => new NavPathStack())!

  // 格式化数字：超过1万显示为 x.x万（实现见 utils/Formatter.ets）
  formatNumber(num: number): string {
    return formatCount(num)
  }

  /** 是否已点赞 */
  isLiked(item: MomentListType): boolean {
    return this.likedKeys.includes(momentKey(item))
  }

  /** 展示用的点赞数（基础值 + 本人点赞） */
  likeCount(item: MomentListType): number {
    return this.isLiked(item) ? item.like + 1 : item.like
  }

  /** 展示用的评论数（基础值 + 本人评论数） */
  commentCount(item: MomentListType): number {
    const locals = this.localComments[momentKey(item)]
    return item.comment + (locals ? locals.length : 0)
  }

  /** 点赞 / 取消点赞 */
  toggleLike(item: MomentListType) {
    const key = momentKey(item)
    if (this.likedKeys.includes(key)) {
      this.likedKeys = this.likedKeys.filter((k: string) => k !== key)
    } else {
      this.likedKeys = [...this.likedKeys, key]
    }
  }

  /** 分享动态 */
  shareMoment(item: MomentListType) {
    const text = `${item.author}：${item.content}${item.song ? `  分享歌曲《${item.song.name}》` : ''}`
    sharePlainText('分享动态', text)
  }

  /** 打开评论页（底部弹层） */
  openComments(item: MomentListType) {
    const key = momentKey(item)
    const base = createComments(item.song ? item.song.id : key.length.toString(), item.comment)
    const mine = this.localComments[key] ?? []
    this.commentTarget = item
    this.commentList = [...mine, ...base]
    this.commentInput = ''
    this.isCommentOpen = true
  }

  /** 发表评论 */
  sendComment() {
    const text = this.commentInput.trim()
    const target = this.commentTarget
    if (text.length === 0 || !target) {
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
    const key = momentKey(target)
    const mine = this.localComments[key] ?? []
    this.localComments[key] = [item, ...mine]
    this.commentList = [item, ...this.commentList]
    this.commentInput = ''
    toast({ message: '评论成功', duration: 1000 })
  }

  /** 评论点赞 */
  toggleCommentLike(item: CommentItem) {
    if (this.likedCommentIds.includes(item.id)) {
      this.likedCommentIds = this.likedCommentIds.filter((id: string) => id !== item.id)
      item.like = Math.max(0, item.like - 1)
    } else {
      this.likedCommentIds = [...this.likedCommentIds, item.id]
      item.like = item.like + 1
    }
    this.commentList = [...this.commentList]
  }

  /** 点击歌曲卡片：播放并进入播放页 */
  playSong(song: SongItemType) {
    playerManager.singPlay(song)
    this.pathStack.pushPathByName('Play', null, true)
  }

  // ========== 评论面板 ==========
  @Builder
  commentPanel() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#99000000')
        .onClick(() => {
          this.isCommentOpen = false
        })

      Column() {
        Row() {
          Column({ space: 2 }) {
            Text(`评论 (${this.commentTarget ? this.formatNumber(this.commentCount(this.commentTarget)) : '0'})`)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
            Text(this.commentTarget ? this.commentTarget.content : '')
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

        List() {
          ForEach(this.commentList, (item: CommentItem) => {
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

          if (this.commentList.length === 0) {
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

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        // 标题
        Row() {
          Text('互动广场')
            .fontColor(Color.White)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
        }
        .width('100%')
        .padding(16)

        // 动态列表
        List({ space: 16 }) {
          ForEach(momentList, (item: MomentListType) => {
            ListItem() {
              Row({ space: 12 }) {
                // 头像
                Image(item.avatar)
                  .width(44)
                  .height(44)
                  .borderRadius(22)
                  .objectFit(ImageFit.Cover)
                  .alignSelf(ItemAlign.Start)

                // 右侧内容区
                Column({ space: 10 }) {
                  // 用户名
                  Text(item.author)
                    .fontColor(Color.White)
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)

                  // 动态内容
                  Text(item.content)
                    .fontColor(Color.White)
                    .fontSize(14)
                    .maxLines(3)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })

                  // 歌曲卡片（可点击播放）
                  if (item.song) {
                    Row({ space: 10 }) {
                      Image(item.song.img)
                        .width(60)
                        .height(60)
                        .borderRadius(8)
                        .objectFit(ImageFit.Cover)

                      Column({ space: 4 }) {
                        Text(item.song.name)
                          .fontColor(Color.White)
                          .fontSize(14)
                          .fontWeight(FontWeight.Medium)

                        Text(item.song.author)
                          .fontColor(Color.Gray)
                          .fontSize(12)
                      }
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)

                      Image($r('app.media.ic_play'))
                        .width(22)
                        .height(22)
                        .fillColor('#8a8a8a')
                    }
                    .width('100%')
                    .padding(10)
                    .backgroundColor('#1e1e1e')
                    .borderRadius(8)
                    .onClick(() => {
                      this.playSong(item.song)
                    })
                  }

                  // 操作栏：分享 | 评论 | 点赞
                  Row() {
                    Row({ space: 4 }) {
                      Image($r('app.media.ic_share'))
                        .width(18)
                        .height(18)
                        .fillColor(Color.Gray)
                      Text('分享')
                        .fontColor(Color.Gray)
                        .fontSize(12)
                    }
                    .layoutWeight(1)
                    .justifyContent(FlexAlign.Start)
                    .padding({ top: 4, bottom: 4 })
                    .onClick(() => {
                      this.shareMoment(item)
                    })

                    Row({ space: 4 }) {
                      Image($r('app.media.ic_comment'))
                        .width(18)
                        .height(18)
                        .fillColor(Color.Gray)
                      Text(this.formatNumber(this.commentCount(item)))
                        .fontColor(Color.Gray)
                        .fontSize(12)
                    }
                    .layoutWeight(1)
                    .justifyContent(FlexAlign.Center)
                    .padding({ top: 4, bottom: 4 })
                    .onClick(() => {
                      this.openComments(item)
                    })

                    Row({ space: 4 }) {
                      Image($r('app.media.ic_like'))
                        .width(18)
                        .height(18)
                        .fillColor(this.isLiked(item) ? '#ff5186' : Color.Gray)
                        .animation({ duration: 200 })
                      Text(this.formatNumber(this.likeCount(item)))
                        .fontColor(this.isLiked(item) ? '#ff5186' : Color.Gray)
                        .fontSize(12)
                    }
                    .layoutWeight(1)
                    .justifyContent(FlexAlign.End)
                    .padding({ top: 4, bottom: 4 })
                    .onClick(() => {
                      this.toggleLike(item)
                    })
                  }
                  .width('100%')
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .padding(16)
              .backgroundColor('#1a1a1a')
              .borderRadius(12)
            }
          }, (item: MomentListType) => momentKey(item))



          ListItem(){
            Text('没有更多了...')
              .fontSize(16)
              .fontWeight(600)
              .fontColor(Color.Gray)
              .margin({bottom:20})
          }
          .width('100%')
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16 })
        .scrollBar(BarState.Auto)
        .scrollBarColor(Color.Gray)
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#131313')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      // 评论面板
      if (this.isCommentOpen) {
        this.commentPanel()
      }
    }
    .width('100%')
    .height('100%')
  }
}
