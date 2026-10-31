async function openSettings(page,section='language'){
 await page.locator('#arcSettings').click();
 await page.locator('#arcSettingsMenu [data-arc-top-section="'+section+'"]').click();
}
async function openNotifications(page,section='all'){
 await page.locator('#arcNotify').click();
 await page.locator('#arcNotifyMenu [data-arc-top-section="'+section+'"]').click();
}
async function openAppNavigation(page){
 const button=page.locator('.arcBurger');
 if(await button.isVisible())await button.click();
 await page.locator('.arcSidebar').waitFor({state:'visible'});
 await page.waitForFunction(()=>document.querySelector('.arcSidebar')?.inert===false);
}
module.exports={openSettings,openNotifications,openAppNavigation};
