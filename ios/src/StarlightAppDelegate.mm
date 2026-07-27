#import "StarlightAppDelegate.h"

#import "StarlightAudio.h"
#import "StarlightHaptics.h"
#import "StarlightInput.h"
#import "StarlightMetalView.h"
#import "StarlightPaths.h"
#import "StarlightRuntimeBridge.h"
#import "StarlightSettings.h"
#import "StarlightSettingsViewController.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface StarlightViewController
    : UIViewController <StarlightMetalViewDelegate, UIDocumentPickerDelegate>
@end

@implementation StarlightViewController
{
  StarlightMetalView* _metalView;
  StarlightTouchOverlay* _touchOverlay;
  UILabel* _status;
  UIButton* _importButton;
  UIButton* _settingsButton;
  id _settingsObserver;
}

- (void)loadView
{
  UIView* root = [[UIView alloc] initWithFrame:UIScreen.mainScreen.bounds];
  root.backgroundColor = UIColor.blackColor;
  _metalView = [[StarlightMetalView alloc] initWithFrame:root.bounds];
  _metalView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  _metalView.delegate = self;
  [root addSubview:_metalView];

  _touchOverlay = [[StarlightTouchOverlay alloc] initWithFrame:root.bounds];
  _touchOverlay.autoresizingMask =
      UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [root addSubview:_touchOverlay];

  _status = [[UILabel alloc] initWithFrame:CGRectZero];
  _status.translatesAutoresizingMaskIntoConstraints = NO;
  _status.textColor = UIColor.whiteColor;
  _status.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
  _status.textAlignment = NSTextAlignmentCenter;
  _status.numberOfLines = 0;
  [root addSubview:_status];
  [NSLayoutConstraint activateConstraints:@[
    [_status.centerXAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.centerXAnchor],
    [_status.centerYAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.centerYAnchor],
    [_status.leadingAnchor constraintGreaterThanOrEqualToAnchor:root.safeAreaLayoutGuide.leadingAnchor
                                                      constant:24],
    [_status.trailingAnchor constraintLessThanOrEqualToAnchor:root.safeAreaLayoutGuide.trailingAnchor
                                                    constant:-24],
  ]];

  _importButton = [UIButton buttonWithType:UIButtonTypeSystem];
  _importButton.translatesAutoresizingMaskIntoConstraints = NO;
  [_importButton setTitle:@"Choose ISO or WBFS" forState:UIControlStateNormal];
  _importButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
  _importButton.tintColor = UIColor.whiteColor;
  _importButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.18];
  _importButton.contentEdgeInsets = UIEdgeInsetsMake(12, 20, 12, 20);
  _importButton.layer.cornerRadius = 12.0;
  [_importButton addTarget:self
                    action:@selector(chooseGameImage)
          forControlEvents:UIControlEventTouchUpInside];
  [root addSubview:_importButton];
  [NSLayoutConstraint activateConstraints:@[
    [_importButton.topAnchor constraintEqualToAnchor:_status.bottomAnchor constant:20],
    [_importButton.centerXAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.centerXAnchor],
  ]];

  _settingsButton = [UIButton buttonWithType:UIButtonTypeSystem];
  _settingsButton.translatesAutoresizingMaskIntoConstraints = NO;
  [_settingsButton setImage:[UIImage systemImageNamed:@"gearshape.fill"] forState:UIControlStateNormal];
  _settingsButton.tintColor = UIColor.whiteColor;
  _settingsButton.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.38];
  _settingsButton.layer.cornerRadius = 20.0;
  [_settingsButton addTarget:self
                      action:@selector(showSettings)
            forControlEvents:UIControlEventTouchUpInside];
  [root addSubview:_settingsButton];
  [NSLayoutConstraint activateConstraints:@[
    [_settingsButton.topAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.topAnchor
                                              constant:8],
    [_settingsButton.trailingAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.trailingAnchor
                                                   constant:-8],
    [_settingsButton.widthAnchor constraintEqualToConstant:40],
    [_settingsButton.heightAnchor constraintEqualToConstant:40],
  ]];

  __weak StarlightViewController* weakSelf = self;
  _settingsObserver = [NSNotificationCenter.defaultCenter
      addObserverForName:StarlightSettingsDidChangeNotification
                  object:nil
                   queue:NSOperationQueue.mainQueue
              usingBlock:^(NSNotification*) {
                [weakSelf applySettings];
              }];
  self.view = root;
}

- (void)dealloc
{
  if (_settingsObserver)
    [NSNotificationCenter.defaultCenter removeObserver:_settingsObserver];
}

- (void)showSettings
{
  StarlightSettingsViewController* settings = [StarlightSettingsViewController new];
  UINavigationController* navigation =
      [[UINavigationController alloc] initWithRootViewController:settings];
  navigation.modalPresentationStyle = UIModalPresentationFormSheet;
  [self presentViewController:navigation animated:YES completion:nil];
}

- (void)applySettings
{
  UIApplication.sharedApplication.idleTimerDisabled =
      StarlightSettings.shared.preventIdleSleep;
  [_metalView configureDisplay];
  [_touchOverlay setNeedsLayout];
}

- (void)viewDidAppear:(BOOL)animated
{
  [super viewDidAppear:animated];
  [self refreshGameSource];
}

- (void)refreshGameSource
{
  NSURL* source = [StarlightPaths.shared selectedGameSource];
  _status.hidden = NO;
  _importButton.enabled = YES;
  _importButton.hidden = NO;
  [_importButton setTitle:source ? @"Change Game Image" : @"Choose ISO or WBFS"
                 forState:UIControlStateNormal];

  if (!source)
  {
    _status.text =
        @"Choose an RMGE01 ISO or WBFS image, or copy the extracted game to\n"
         "Starlight/Game/RMGE01";
    return;
  }
  if (![StarlightRuntimeBridge.shared isAvailable])
  {
    _status.text = [NSString
        stringWithFormat:@"Selected: %@\nThe iOS host does not contain the ARM64 game runtime yet.",
                         source.lastPathComponent];
    return;
  }
  if ([StarlightRuntimeBridge.shared startWithLayer:_metalView.metalLayer])
  {
    _status.hidden = YES;
    _importButton.hidden = YES;
  }
}

- (void)chooseGameImage
{
  UTType* iso = [UTType typeWithFilenameExtension:@"iso"];
  UTType* wbfs = [UTType typeWithFilenameExtension:@"wbfs"];
  NSMutableArray<UTType*>* types = [NSMutableArray array];
  if (iso)
    [types addObject:iso];
  if (wbfs)
    [types addObject:wbfs];
  if (types.count == 0)
    [types addObject:UTTypeData];

  UIDocumentPickerViewController* picker =
      [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
  picker.delegate = self;
  picker.allowsMultipleSelection = NO;
  [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController*)controller
    didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls
{
  (void)controller;
  NSURL* source = urls.firstObject;
  if (!source)
    return;

  _importButton.enabled = NO;
  _status.hidden = NO;
  _status.text = @"Validating and importing the game image…";
  __weak StarlightViewController* weakSelf = self;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    NSError* error;
    NSURL* imported = [StarlightPaths.shared importGameSource:source error:&error];
    dispatch_async(dispatch_get_main_queue(), ^{
      StarlightViewController* strongSelf = weakSelf;
      if (!strongSelf)
        return;
      if (!imported)
      {
        strongSelf->_importButton.enabled = YES;
        strongSelf->_status.text =
            error.localizedDescription ?: @"The game image could not be imported.";
        return;
      }
      [strongSelf refreshGameSource];
    });
  });
}

- (BOOL)prefersHomeIndicatorAutoHidden
{
  return YES;
}

- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures
{
  return UIRectEdgeAll;
}

- (BOOL)prefersStatusBarHidden
{
  return YES;
}

- (void)metalViewOutputSizeChanged:(CGSize)outputSize renderSize:(CGSize)renderSize
{
  [StarlightRuntimeBridge.shared resizeOutput:outputSize render:renderSize];
}

@end

@implementation StarlightAppDelegate

- (BOOL)application:(UIApplication*)application
    didFinishLaunchingWithOptions:(NSDictionary*)launchOptions
{
  (void)launchOptions;
  NSError* error;
  if (![StarlightPaths.shared prepare:&error])
    NSLog(@"Starlight storage setup failed: %@", error);

  [StarlightInput.shared start];
  [StarlightHaptics.shared start];
  if (![StarlightAudio.shared start:&error])
    NSLog(@"Starlight audio setup failed: %@", error);

  application.idleTimerDisabled = StarlightSettings.shared.preventIdleSleep;
  self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
  self.window.rootViewController = [StarlightViewController new];
  [self.window makeKeyAndVisible];
  return YES;
}

- (void)applicationWillResignActive:(UIApplication*)application
{
  (void)application;
  if (StarlightSettings.shared.suspendInBackground)
    [StarlightRuntimeBridge.shared setPaused:YES];
}

- (void)applicationDidBecomeActive:(UIApplication*)application
{
  application.idleTimerDisabled = StarlightSettings.shared.preventIdleSleep;
  if (StarlightSettings.shared.suspendInBackground)
    [StarlightRuntimeBridge.shared setPaused:NO];
}

- (void)applicationDidEnterBackground:(UIApplication*)application
{
  (void)application;
  [StarlightHaptics.shared stop];
  if (StarlightSettings.shared.suspendInBackground)
    [StarlightAudio.shared stop];
}

- (void)applicationWillEnterForeground:(UIApplication*)application
{
  (void)application;
  [StarlightHaptics.shared start];
  if (StarlightSettings.shared.suspendInBackground)
  {
    NSError* error;
    if (![StarlightAudio.shared start:&error])
      NSLog(@"Starlight audio resume failed: %@", error);
  }
}

- (void)applicationWillTerminate:(UIApplication*)application
{
  (void)application;
  [StarlightRuntimeBridge.shared stop];
  [StarlightAudio.shared stop];
  [StarlightInput.shared stop];
  [StarlightHaptics.shared stop];
}

@end
