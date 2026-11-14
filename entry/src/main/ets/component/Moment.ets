import { momentList } from '../models/momentData'
import { MomentListType } from '../models/music'

@ComponentV2
export struct Moment {
  // 格式化数字：超过1万显示为 x.x万
  formatNumber(num: number): string {
    if (num >= 10000) {
      return (num / 10000).toFixed(1) + '万'
    }
    return num.toString()
  }

  build() {
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

                // 歌曲卡片
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
                  }
                  .width('100%')
                  .padding(10)
                  .backgroundColor('#1e1e1e')
                  .borderRadius(8)
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

                  Row({ space: 4 }) {
                    Image($r('app.media.ic_comment'))
                      .width(18)
                      .height(18)
                      .fillColor(Color.Gray)
                    Text(this.formatNumber(item.comment))
                      .fontColor(Color.Gray)
                      .fontSize(12)
                  }
                  .layoutWeight(1)
                  .justifyContent(FlexAlign.Center)

                  Row({ space: 4 }) {
                    Image($r('app.media.ic_like'))
                      .width(18)
                      .height(18)
                      .fillColor(Color.Gray)
                    Text(this.formatNumber(item.like))
                      .fontColor(Color.Gray)
                      .fontSize(12)
                  }
                  .layoutWeight(1)
                  .justifyContent(FlexAlign.End)
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
        }, (item: MomentListType) => item.author + item.content)



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
  }
}
