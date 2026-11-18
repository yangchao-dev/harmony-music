import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { playerManager } from '../utils/AvPlayerManager';
import { sessionManager } from '../utils/AvSessionManager';
import { notificationManager } from '@kit.NotificationKit';
import { preferencesService } from '../models/UserSettings';
import { setAppContext } from '../utils/ContextHelper';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    // 缓存 AbilityContext，供非组件代码（Preferences / 分享）复用，避免调用已废弃的全局 getContext
    setAppContext(this.context);
    // 初始化本地持久化（喜欢 / 播放历史 / 用户偏好 / 歌单），越早越好
    preferencesService.init(this.context);
    // 初始化AV会话，用于后台播放
    sessionManager.init(this.context);
    // 解耦绑定：播放器事件 → 会话管理器（单向依赖，打破循环依赖）
    playerManager.setObserver(sessionManager);
    // 系统媒体控制 → 播放器命令
    sessionManager.bindPlaybackControls(
      () => {
        // 播放：优先续播当前歌曲（从暂停恢复），无当前歌曲时才从头播放
        const s = playerManager.currentSong
        if (s.playList.length > 0) {
          playerManager.resumeOrPlay()
        }
      },
      () => { playerManager.pause() },
      () => { playerManager.prevPlay() },
      () => { playerManager.nextPlay(false) },
      (value: number) => { playerManager.seekPlay(value) }
    );
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
    // 应用被销毁时（如从后台划掉），释放播放器并清理通知/AVSession（destroy 幂等）
    playerManager.release()
    sessionManager.destroy()
  }

  // 请求通知权限
  private async requestNotificationPermission(): Promise<boolean> {
    try {
      // 先检查通知是否已开启
      const enabled = await notificationManager.isNotificationEnabled()
      if (enabled) {
        return true
      }
      // 未开启则向用户请求（需传入 UIAbilityContext，旧的无参重载自 API 12 起废弃）
      await notificationManager.requestEnableNotification(this.context)
      return await notificationManager.isNotificationEnabled()
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to request notification permission: %{public}s', JSON.stringify(err))
      return false
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {

    // 先缓存上下文（startBackgroundTask 依赖它），再初始化播放器与后台任务
    setAppContext(this.context);
    playerManager.init();
    // 申请后台长时任务（音频播放），失败不影响前台播放
    sessionManager.startBackgroundTask();

    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');

      // 请求通知权限，用户授权后应用才能发布通知
      this.requestNotificationPermission()
        .then((granted) => {
          hilog.info(DOMAIN, 'testTag', 'Notification permission: %{public}s', granted ? 'granted' : 'denied');
        })
        .catch((err: Error) => {
          hilog.error(DOMAIN, 'testTag', 'Failed to request notification permission: %{public}s', JSON.stringify(err));
        });

      // 设置状态栏颜色适配
      windowStage.getMainWindow().then((mainWindow: window.Window) => {
        // 设置状态栏背景色为透明，让页面背景显示
        let statusBarColor = '#00000000'; // 透明色
        // 设置状态栏内容（文字、图标）颜色为白色，适配深色背景
        let statusBarContentColor = '#FFFFFF';

        let systemBarProperties: window.SystemBarProperties = {
          statusBarColor: statusBarColor,
          statusBarContentColor: statusBarContentColor,
          navigationBarColor: '#00000000', // 导航栏也设置为透明
          navigationBarContentColor: statusBarContentColor // 导航栏内容也设置为白色
        };

        mainWindow.setWindowSystemBarProperties(systemBarProperties).then(() => {
          hilog.info(DOMAIN, 'testTag', 'Succeeded in setting status bar properties.');
        }).catch((err: Error) => {
          hilog.error(DOMAIN, 'testTag', 'Failed to set status bar properties. Cause: %{public}s', JSON.stringify(err));
        });
      }).catch((err: Error) => {
        hilog.error(DOMAIN, 'testTag', 'Failed to get main window. Cause: %{public}s', JSON.stringify(err));
      });



    });
  }

  onWindowStageDestroy(): void {
    // 仅释放播放器；AVSession 的销毁交由 onDestroy 统一处理，
    // 避免窗口重建（如多窗口/配置变更）时误销毁会话。
    playerManager.release()

    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    // 回到前台，取消后台播放通知
    sessionManager.isAppInBackground = false
    sessionManager.cancelMediaNotification()
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
    // 标记进入后台，如果正在播放则显示通知
    sessionManager.isAppInBackground = true
    if (playerManager.currentSong.isPlay && playerManager.currentSong.name) {
      sessionManager.publishMediaNotification(
        playerManager.currentSong.name,
        playerManager.currentSong.author
      )
    }
  }
}