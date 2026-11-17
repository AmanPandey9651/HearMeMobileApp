#import "FeelBackRingtonePlugin.h"

@implementation FeelBackRingtonePlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel* channel = [FlutterMethodChannel
      methodChannelWithName:@"feelback_ringtone"
            binaryMessenger:[registrar messenger]];
  FeelBackRingtonePlugin* instance = [[FeelBackRingtonePlugin alloc] init];
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  result(nil);
}
@end
