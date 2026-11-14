import { AppStorageV2 } from '@kit.ArkUI'

@Entry // 入口组件装饰器，标记为应用主入口
@Component // 组件装饰器，声明为自定义组件
struct Index {
  // 导航路径栈实例，用于管理页面导航路径（HarmonyOS 3.1+新增API）
  // pathStack: NavPathStack = new NavPathStack()
  pathStack: NavPathStack = AppStorageV2.connect(NavPathStack,'navStack', ()=> new NavPathStack())!  // !非空断言

  build() {
    // 创建导航容器组件，绑定路径栈控制器
    Navigation(this.pathStack){
    }
    // 生命周期回调：组件显示时触发
    .onAppear(()=>{
      // 初始跳转到名为'Start'的页面
      // 参数说明：页面名 | 传递数据(null) | 是否启用动画(false)
      this.pathStack.pushPathByName('Start',null,false)
    })
    // 隐藏首页导航栏（顶部标题栏）禁止再次返回 否则会进入空白页面 建议开启
    .hideNavBar(true)
  }
}