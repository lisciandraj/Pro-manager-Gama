async function openSettings(page,section='language'){
 await page.locator('#arcSettings').click();
 await page.locator('#arcSettingsMenu [data-arc-top-section="'+section+'"]').click();
}
async function openNotifications(page,section='all'){
 await page.locator('#arcNotify').click();
 await page.locator('#arcNotifyMenu [data-arc-top-section="'+section+'"]').click();
}
module.exports={openSettings,openNotifications};
