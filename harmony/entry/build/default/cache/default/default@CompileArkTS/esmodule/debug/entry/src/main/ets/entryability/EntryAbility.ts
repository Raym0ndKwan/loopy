import type AbilityConstant from "@ohos:app.ability.AbilityConstant";
import ConfigurationConstant from "@ohos:app.ability.ConfigurationConstant";
import UIAbility from "@ohos:app.ability.UIAbility";
import type Want from "@ohos:app.ability.Want";
import hilog from "@ohos:hilog";
import type window from "@ohos:window";
const DOMAIN = 0x0000;
export default class EntryAbility extends UIAbility {
    onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
        this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
        hilog.info(DOMAIN, 'Loop', 'EntryAbility onCreate');
    }
    onDestroy(): void {
        hilog.info(DOMAIN, 'Loop', 'EntryAbility onDestroy');
    }
    onWindowStageCreate(windowStage: window.WindowStage): void {
        hilog.info(DOMAIN, 'Loop', 'EntryAbility onWindowStageCreate');
        windowStage.loadContent('pages/Index', (error) => {
            if (error.code) {
                hilog.error(DOMAIN, 'Loop', 'Failed to load content. Cause: %{public}s', JSON.stringify(error));
                return;
            }
            hilog.info(DOMAIN, 'Loop', 'Succeeded in loading content.');
        });
    }
    onWindowStageDestroy(): void {
        hilog.info(DOMAIN, 'Loop', 'EntryAbility onWindowStageDestroy');
    }
    onForeground(): void {
        hilog.info(DOMAIN, 'Loop', 'EntryAbility onForeground');
    }
    onBackground(): void {
        hilog.info(DOMAIN, 'Loop', 'EntryAbility onBackground');
    }
}
