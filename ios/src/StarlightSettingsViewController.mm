#import "StarlightSettingsViewController.h"

#import "StarlightSettings.h"

namespace
{
enum SettingRow
{
  SettingRowBackgroundSuspend,
  SettingRowPreventIdleSleep,
  SettingRowTouchControls,
  SettingRowGyroscope,
  SettingRowHaptics,
  SettingRowMetalFX,
  SettingRowHDR,
  SettingRowCount,
};
}

@implementation StarlightSettingsViewController

- (instancetype)init
{
  return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad
{
  [super viewDidLoad];
  self.title = @"Settings";
  self.navigationItem.rightBarButtonItem =
      [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                   target:self
                                                   action:@selector(close)];
}

- (void)close
{
  [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView
{
  (void)tableView;
  return 3;
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section
{
  (void)tableView;
  if (section == 0)
    return 2;
  if (section == 1)
    return 3;
  return 2;
}

- (NSString*)tableView:(UITableView*)tableView titleForHeaderInSection:(NSInteger)section
{
  (void)tableView;
  if (section == 0)
    return @"System";
  if (section == 1)
    return @"Controls";
  return @"Presentation";
}

- (SettingRow)settingForIndexPath:(NSIndexPath*)indexPath
{
  static const SettingRow rows[][3] = {
      {SettingRowBackgroundSuspend, SettingRowPreventIdleSleep, SettingRowCount},
      {SettingRowTouchControls, SettingRowGyroscope, SettingRowHaptics},
      {SettingRowMetalFX, SettingRowHDR, SettingRowCount},
  };
  return rows[indexPath.section][indexPath.row];
}

- (NSString*)titleForSetting:(SettingRow)setting
{
  switch (setting)
  {
  case SettingRowBackgroundSuspend: return @"Suspend in Background";
  case SettingRowPreventIdleSleep: return @"Prevent Idle Sleep";
  case SettingRowTouchControls: return @"Touch Controls";
  case SettingRowGyroscope: return @"Gyroscope";
  case SettingRowHaptics: return @"Haptics";
  case SettingRowMetalFX: return @"MetalFX Upscaling";
  case SettingRowHDR: return @"HDR Output";
  case SettingRowCount: break;
  }
  return @"";
}

- (BOOL)valueForSetting:(SettingRow)setting
{
  StarlightSettings* settings = StarlightSettings.shared;
  switch (setting)
  {
  case SettingRowBackgroundSuspend: return settings.suspendInBackground;
  case SettingRowPreventIdleSleep: return settings.preventIdleSleep;
  case SettingRowTouchControls: return settings.touchControlsEnabled;
  case SettingRowGyroscope: return settings.gyroEnabled;
  case SettingRowHaptics: return settings.hapticsEnabled;
  case SettingRowMetalFX: return settings.metalFXEnabled;
  case SettingRowHDR: return settings.hdrEnabled;
  case SettingRowCount: return NO;
  }
}

- (UITableViewCell*)tableView:(UITableView*)tableView
        cellForRowAtIndexPath:(NSIndexPath*)indexPath
{
  static NSString* identifier = @"Switch";
  UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:identifier];
  if (!cell)
    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                  reuseIdentifier:identifier];

  SettingRow setting = [self settingForIndexPath:indexPath];
  cell.textLabel.text = [self titleForSetting:setting];
  UISwitch* toggle = [UISwitch new];
  toggle.tag = setting;
  toggle.on = [self valueForSetting:setting];
  [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
  cell.accessoryView = toggle;
  cell.selectionStyle = UITableViewCellSelectionStyleNone;
  return cell;
}

- (void)toggleChanged:(UISwitch*)sender
{
  StarlightSettings* settings = StarlightSettings.shared;
  switch ((SettingRow)sender.tag)
  {
  case SettingRowBackgroundSuspend: settings.suspendInBackground = sender.on; break;
  case SettingRowPreventIdleSleep: settings.preventIdleSleep = sender.on; break;
  case SettingRowTouchControls: settings.touchControlsEnabled = sender.on; break;
  case SettingRowGyroscope: settings.gyroEnabled = sender.on; break;
  case SettingRowHaptics: settings.hapticsEnabled = sender.on; break;
  case SettingRowMetalFX: settings.metalFXEnabled = sender.on; break;
  case SettingRowHDR: settings.hdrEnabled = sender.on; break;
  case SettingRowCount: return;
  }
  [settings save];
  [NSNotificationCenter.defaultCenter postNotificationName:StarlightSettingsDidChangeNotification
                                                    object:settings];
}

@end
