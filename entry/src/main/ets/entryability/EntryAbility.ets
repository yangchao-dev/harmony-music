import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { playerManager } from '../utils/AvPlayerManager';
import { sessionManager } from '../utils/AvSessionManager';
import { notificationManager } from '@kit.NotificationKit';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    // 初始化AV会话，用于后台播放
    sessionManager.init(this.context);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
    // 应用被销毁时（如从后台划掉），清理通知和AVSession
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
      // 未开启则向用户请求
      await notificationManager.requestEnableNotification()
      return await notificationManager.isNotificationEnabled()
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to request notification permission: %{public}s', JSON.stringify(err))
      return false
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {

    playerManager.init();

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
    // 注销会话 释放播放器
    sessionManager.destroy()
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