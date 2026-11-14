// 导入推荐页子组件
import { Found } from '../component/Found'
import { Mine } from '../component/Mine'
import { Moment } from '../component/Moment'
import { Recommend } from '../component/Recommend'


interface TabClass {
  text: string
  icon: ResourceStr
}

// 使用@Builder装饰器创建可复用的UI构建函数
@Builder
export function LayoutBuilder() {
  // 返回Layout组件实例
  Layout()
}

// 自定义组件装饰器
@ComponentV2
struct Layout {
  // 存储当前页面下标
  @Local currentIndex: number = 0
  // 导航路径栈实例，用于管理页面导航
  pathStack: NavPathStack = new NavPathStack()
  // 导航数据
  tabData: TabClass[] = [
    { text: '推荐', icon: $r('app.media.ic_recommend') },
    { text: '发现', icon: $r('app.media.ic_find') },
    { text: '动态', icon: $r('app.media.ic_moment') },
    { text: '我的', icon: $r('app.media.ic_mine') }
  ]

  @Builder
  tabBuilder(item: TabClass, index: number) {
    Column({ space: 5 }) {
      Image(item.icon)
        .width(25)
        .fillColor(this.currentIndex === index ? '#ffff52d2' : '#698895')
      Text(item.text)
        .fontSize(13)
        .fontColor(this.currentIndex === index ? '#ffff52d2' : '#698895')
        // .decoration({ type: this.currentIndex === index ? TextDecorationType.Underline : TextDecorationType.None , color: this.currentIndex === index ? '#ffff52d2' : ''})
        .padding({
          left: 8,
          right: 8,
          top: 2,
          bottom: 2
        })
        .borderRadius(20)
        .backgroundColor(this.currentIndex === index ? '#4ffface5' : '')

    }
    .margin({ top: 7 })

  }

  build() {
    // 创建导航目的地组件（页面容器）
    NavDestination() {
      // 此处可添加页面内容组件
      Tabs({ barPosition: BarPosition.End }) {
        /* 方法1*/
        // 使用ForEach 循环渲染TabContent
        // ForEach(this.tabData, (item: TabClass, index: number) => {
        //   TabContent() {
        //     if (index === 0) {
        //       Recommend()
        //     } else if (index === 1) {
        //       Found()
        //     } else if (index === 2){
        //       Moment()
        //     } else {
        //       Mine()
        //     }
        //
        //   }
        //   .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        //   .backgroundColor('#131217')
        //   .tabBar(this.tabBuilder(item, index))
        // })

        //
        // /* 方法2 */
        TabContent() {
          // 推荐页内容
          Recommend()
        }.tabBar(this.tabBuilder(this.tabData[0], 0))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .backgroundColor('#131217')

        TabContent() {
          Found()
        }.tabBar(this.tabBuilder(this.tabData[1], 1))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .backgroundColor('#131217')

        TabContent() {
          Moment()
        }.tabBar(this.tabBuilder(this.tabData[2], 2))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .backgroundColor('#131217')

        TabContent() {
          Mine()
        }.tabBar(this.tabBuilder(this.tabData[3], 3))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .backgroundColor('#131217')

      }
      // .scrollable(false)
      .edgeEffect(EdgeEffect.None)
      .onSelected((index) => { // 获取当前页面的下标
        // 把当前页面的下标赋值给状态变量
        this.currentIndex = index
        // console.log(this.currentIndex.toString())
      })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      .backgroundColor('#3a3e41')
    }
    // 设置导航栏标题
    // .title('布局页')
    // 页面就绪回调（组件挂载完成时触发）
    .onReady((context: NavDestinationContext) => {
      // 从上下文中获取导航路径栈实例
      // 实现当前组件与导航栈的关联
      this.pathStack = context.pathStack
    })
  }
}