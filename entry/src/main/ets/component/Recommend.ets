// 导入推荐页数据
import {
  swiperList,
  dailyRecommend,
  recommendDailyType,
  recommendList,
  recommendListType
} from '../models/RecommendData'

@Component
export struct Recommend {
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

  build() {
    Scroll() {
      Column() {
        // 搜索区域
        Row() {
          //搜索图标
          Image($r('app.media.ic_search'))
            .width(24)
            .margin({ left: 10 })
            .fillColor(Color.Gray)
          // 文本输入框
          TextInput({ placeholder: '只因你太美' })
            .placeholderColor(Color.Gray)
            .fontColor(Color.White)
            .layoutWeight(1)
            .backgroundColor(Color.Transparent)

          Image($r('app.media.ic_code'))
            .width(23)
            .fillColor(Color.Gray)
            .margin({ right: 10 })
        }
        .margin({ top: 10 })
        .borderRadius(20)
        .backgroundColor('#2f2b28')
        .width('95%')


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
          ForEach(dailyRecommend, (item: recommendDailyType) => {
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
          ForEach(recommendList, (item: recommendListType) => {
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

            }
          })
        }
        .listDirection(1)
        .width('100%')
        .height(150)
        .padding({ left: 10, right: 10 })
        .scrollBar(BarState.Off)



      }
      .width('100%')

    }
    .width('100%')

  }
}