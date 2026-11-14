// 使用@Builder装饰器创建可复用的UI构建函数
@Builder
export function StartBuilder() {
  // 返回Start组件实例
  Start()
}

// 自定义组件装饰器
@Component
struct Start {
  // 导航路径栈实例，用于管理页面导航
  pathStack: NavPathStack = new NavPathStack()

  // 状态变量存储定时器id
  timeId: number = -1

  // 生命周期回调：组件即将显示时触发
  aboutToAppear(): void {
    // 3秒后自动跳转到布局页（替换当前页面，返回时跳过广告页）
    // 把定时器id赋给timeId
     this.timeId = setTimeout(() => {
      this.pathStack.replacePathByName('Layout', null, false)
    }, 3000)

  }

  // 组件销毁时触发
  aboutToDisappear(): void {
    // 清除定时器
    clearTimeout(this.timeId)
  }


  build() {
    // 创建导航目的地组件（页面容器）
    NavDestination() {
      Stack() {
        // 广告图片
        Image($r('app.media.ad'))
          .width('100%')
          .height('100%')
        // 跳过按钮
        Button('跳过')
          .backgroundColor('#818181')
          .position({ right: 10, top: 10 })
          .onClick(() => {
            // 点击跳过，直接替换到布局页
            this.pathStack.replacePathByName('Layout', null, false)

          })
      }
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .backgroundColor('#121212')
      .width('100%')
      .height('100%')
    }
    // 页面就绪回调（组件挂载完成时触发）
    .onReady((context: NavDestinationContext) => {
      // 从上下文中获取导航路径栈实例
      // 实现当前组件与导航栈的关联
      this.pathStack = context.pathStack
    })
    .hideTitleBar(true)
  }
}