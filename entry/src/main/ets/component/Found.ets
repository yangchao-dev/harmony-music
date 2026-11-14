// ==================== 导入歌曲数据 ====================
import { songs } from '../models/songData'
import {SongItemType} from '../models/music'
import { AppStorageV2, promptAction } from '@kit.ArkUI'
import { playerManager } from '../utils/AvPlayerManager'
import { GlobalMusic } from '../models/globalMusic'

// 删掉@Entry
@ComponentV2
  // 使用V2状态管理
export struct Found {
  @Local currentIndex: number = -1

  pathStack: NavPathStack = AppStorageV2.connect(NavPathStack,'navStack', ()=> new NavPathStack())!  // !非空断言

  playState: GlobalMusic = AppStorageV2.connect(GlobalMusic, 'SONG_KEY', () => new GlobalMusic())!


  build() {
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
              Image($r('app.media.ic_more'))
                .width(20)
                .fillColor(Color.White) // 白色图标
            }
            .onClick(() => {
              if (this.currentIndex === index) {
                this.currentIndex = -1
              } else {
                this.currentIndex = index
                promptAction.showToast({
                  message: `正在播放: ${item.name}`,
                  duration: 1000,
                  bottom: 680
                })
              }

              playerManager.singPlay(item)
              this.pathStack.pushPathByName('Play',null, true)

              // 歌曲简单切换
              // this.currentIndex = index
              // console.log('索引',this.currentIndex, index)
            })
            .width('100%') // 占满列表宽度
          }
          .width('100%') // ListItem 占满宽度




        }, (item: SongItemType, index: number) => index.toString())

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