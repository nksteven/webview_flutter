// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "FlutterWebView.h"
#import "FLTWKNavigationDelegate.h"
#import "JavaScriptChannelHandler.h"
#import "FLTWKWebview.h"


#define TOOBAR_HEIGHT 44.0

@implementation FLTWebViewFactory {
  NSObject<FlutterBinaryMessenger>* _messenger;
}

- (instancetype)initWithMessenger:(NSObject<FlutterBinaryMessenger>*)messenger {
  self = [super init];
  if (self) {
    _messenger = messenger;
  }
  return self;
}

- (NSObject<FlutterMessageCodec>*)createArgsCodec {
  return [FlutterStandardMessageCodec sharedInstance];
}

- (NSObject<FlutterPlatformView>*)createWithFrame:(CGRect)frame
                                   viewIdentifier:(int64_t)viewId
                                        arguments:(id _Nullable)args {
  FLTWebViewController* webviewController = [[FLTWebViewController alloc] initWithFrame:frame
                                                                         viewIdentifier:viewId
                                                                              arguments:args
                                                                        binaryMessenger:_messenger];
  return webviewController;
}

@end

@interface FLTWebViewController()<WKUIDelegate,FLTWebviewLoadUrlDelagate>

@property(nonatomic,strong) NSMutableArray * webviewArr;

@property(nonatomic,strong) WKWebView * currentWebview;

@property(nonatomic,assign) int currentIndex;

@property(nonatomic,strong) UIToolbar * toolbar;

@property(nonatomic,strong) UIBarButtonItem * backButtonItem;

@property(nonatomic,strong) UIBarButtonItem * forwardButtonItem;

@property(nonatomic,assign) BOOL isFirstInvoke;

@end
@implementation FLTWebViewController {
  FLTWKWebview* _webView;
  int64_t _viewId;
  FlutterMethodChannel* _channel;
  NSString* _currentUrl;
  // The set of registered JavaScript channel names.
  NSMutableSet* _javaScriptChannelNames;
  FLTWKNavigationDelegate* _navigationDelegate;
  CALayer *_progresslayer;
}

- (instancetype)initWithFrame:(CGRect)frame
               viewIdentifier:(int64_t)viewId
                    arguments:(id _Nullable)args
              binaryMessenger:(NSObject<FlutterBinaryMessenger>*)messenger {
  if ([super init]) {
    _viewId = viewId;
      self.isFirstInvoke = YES;
      
    NSString* channelName = [NSString stringWithFormat:@"plugins.flutter.io/webview_%lld", viewId];
    _channel = [FlutterMethodChannel methodChannelWithName:channelName binaryMessenger:messenger];
    _javaScriptChannelNames = [[NSMutableSet alloc] init];

    WKUserContentController* userContentController = [[WKUserContentController alloc] init];
    if ([args[@"javascriptChannelNames"] isKindOfClass:[NSArray class]]) {
      NSArray* javaScriptChannelNames = args[@"javascriptChannelNames"];
      [_javaScriptChannelNames addObjectsFromArray:javaScriptChannelNames];
      [self registerJavaScriptChannels:_javaScriptChannelNames controller:userContentController];
    }

    WKWebViewConfiguration* configuration = [[WKWebViewConfiguration alloc] init];
    configuration.userContentController = userContentController;
   
    _webView = [[FLTWKWebview alloc] initWithFrame:frame configuration:configuration];
    _navigationDelegate = [[FLTWKNavigationDelegate alloc] initWithChannel:_channel];
      _navigationDelegate.delegate = self;
    _webView.navigationDelegate = _navigationDelegate;
      _webView.UIDelegate = self;
      [self.webviewArr removeAllObjects];
      [self.webviewArr addObject:_webView];
      self.currentWebview = _webView;
      self.currentIndex = 0;
      
      [self showProgress];
      
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
          [self showToolbar];
      });
      
      [self->_webView addObserver:self forKeyPath:@"canGoBack" options:NSKeyValueObservingOptionNew context:nil];
      
      [self->_webView addObserver:self forKeyPath:@"canGoForward" options:NSKeyValueObservingOptionNew context:nil];
      [self->_webView addObserver:self forKeyPath:@"frame" options:NSKeyValueObservingOptionNew context:nil];
      
    __weak __typeof__(self) weakSelf = self;
    [_channel setMethodCallHandler:^(FlutterMethodCall* call, FlutterResult result) {
      [weakSelf onMethodCall:call result:result];
    }];
    NSDictionary<NSString*, id>* settings = args[@"settings"];
    [self applySettings:settings];

    NSString* initialUrl = args[@"initialUrl"];
    if ([initialUrl isKindOfClass:[NSString class]]) {
      [self loadUrl:initialUrl];
    }
      
      
  }
  return self;
}

-(void)showProgress{
    [self->_webView addObserver:self forKeyPath:@"estimatedProgress" options:NSKeyValueObservingOptionNew context:nil];
    UIView *progress = [[UIView alloc]initWithFrame:CGRectMake(0, 0, CGRectGetWidth(self->_webView.frame), 3)];
    progress.backgroundColor = [UIColor clearColor];
    [self->_webView addSubview:progress];
    
    CALayer *layer = [CALayer layer];
    layer.frame = CGRectMake(0, 0, 0, 3);
    layer.backgroundColor = [[UIColor orangeColor] CGColor];
    [progress.layer addSublayer:layer];
    self->_progresslayer = layer;
}


-(void)showToolbar{
    UIWindow * window = [[UIApplication sharedApplication] windows].firstObject;
    UIToolbar * toolbar = [[UIToolbar alloc]initWithFrame:CGRectMake(0, _webView.frame.size.height, window.bounds.size.width, TOOBAR_HEIGHT)];
    toolbar.translucent = NO;
    [toolbar setAutoresizingMask:UIViewAutoresizingFlexibleTopMargin];
    UIBarButtonItem * leftSpaceItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
    [leftSpaceItem setWidth:40.0];
    // back button
    UIBarButtonItem *backButton = [[UIBarButtonItem alloc]initWithImage:[[UIImage imageNamed:@"Slice-left-gray"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] style:UIBarButtonItemStylePlain target:self action:@selector(goBackClick)];
    backButton.enabled = NO;
    self.backButtonItem = backButton;
    
    UIBarButtonItem * rightSpaceItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace target:nil action:nil];
    [rightSpaceItem setWidth:90.0];
    
    
    // forward button
    UIBarButtonItem *forwardButton = [[UIBarButtonItem alloc]initWithImage:[[UIImage imageNamed:@"Slice-right-gray"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] style:UIBarButtonItemStylePlain target:self action:@selector(goForwardClick)];
    forwardButton.enabled = NO;
    self.forwardButtonItem = forwardButton;
    
    toolbar.items = @[leftSpaceItem,backButton,rightSpaceItem,forwardButton];
    [self.view addSubview:toolbar];
    _webView.toolBar = toolbar;
    self.toolbar = toolbar;
}


-(void)goBackClick{
    if([self.currentWebview canGoBack]){
        WKNavigation * navigation = [self.currentWebview goBack];
        if(navigation == nil){
            [self.currentWebview reload];
        }
    }else{
        if(self.currentWebview != _webView){
            [self.currentWebview removeFromSuperview];
            self.currentIndex--;
            if(self.currentIndex >= 0){
                self.currentWebview = self.webviewArr[self.currentIndex];
            }
            if(self.forwardButtonItem.enabled == NO){
                self.forwardButtonItem.enabled = YES;
                self.forwardButtonItem.image = [[UIImage imageNamed:@"Slice-right"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
            }
            self.backButtonItem.enabled = [self.currentWebview canGoBack];
            self.backButtonItem.image = [self.currentWebview canGoBack] ? [[UIImage imageNamed:@"Slice-left"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] : [[UIImage imageNamed:@"Slice-left-gray"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        }
        
    }
}

-(void)goForwardClick{
    if([self.currentWebview canGoForward]){
        WKNavigation * navigation = [self.currentWebview goForward];
        if(navigation == nil){
            [self.currentWebview reload];
        }
    }else{
        if(self.currentIndex+1 < self.webviewArr.count){
            self.currentIndex++;
            [self.view addSubview:self.webviewArr[self.currentIndex]];
            [self.view bringSubviewToFront:self.toolbar];
            self.currentWebview = self.webviewArr[self.currentIndex];
            if(self.backButtonItem.enabled == NO){
                self.backButtonItem.enabled = YES;
                self.backButtonItem.image = [[UIImage imageNamed:@"Slice-left"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
            }
            self.forwardButtonItem.enabled = [self.currentWebview canGoForward];
            self.forwardButtonItem.image = [self.currentWebview canGoForward] ? [[UIImage imageNamed:@"Slice-right"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] : [[UIImage imageNamed:@"Slice-right-gray"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        }
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *,id> *)change context:(void *)context{
    if ([keyPath isEqualToString:@"estimatedProgress"]) {
        _progresslayer.opacity = 1;
        //不要让进度条倒着走...有时候goback会出现这种情况
//        if ([change[@"new"] floatValue] < [change[@"old"] floatValue]) {
//            return;
//        }
        _progresslayer.frame = CGRectMake(0, 0, _webView.bounds.size.width * [change[@"new"] floatValue], 3);
        
        if ([change[@"new"] floatValue] == 1) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                self->_progresslayer.opacity = 0;
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                self->_progresslayer.frame = CGRectMake(0, 0, 0, 3);
            });
        }
    }else if([keyPath isEqualToString:@"canGoBack"]){
        BOOL isCanGoBack = [change[@"new"] boolValue];
        if (self.currentWebview != _webView) {
            isCanGoBack = YES;
        }
        self.backButtonItem.enabled = isCanGoBack;
        self.backButtonItem.image = isCanGoBack ? [[UIImage imageNamed:@"Slice-left"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] : [[UIImage imageNamed:@"Slice-left-gray"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    }else if([keyPath isEqualToString:@"canGoForward"]){
        BOOL isCanForward = [change[@"new"] boolValue];
        if (self.currentIndex < self.webviewArr.count-1) {
            isCanForward = YES;
        }
        self.forwardButtonItem.enabled = isCanForward;
        self.forwardButtonItem.image = isCanForward ? [[UIImage imageNamed:@"Slice-right"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] : [[UIImage imageNamed:@"Slice-right-gray"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    }else if([keyPath isEqualToString:@"frame"]){
        CGRect rect = [change[@"new"] CGRectValue];
        if (rect.size.height > 0 && self.isFirstInvoke == YES) {
            self.isFirstInvoke = NO;
            CGRect newRect = CGRectMake(rect.origin.x, rect.origin.y, rect.size.width, rect.size.height-TOOBAR_HEIGHT);
            _webView.frame = newRect;
        }
    }else{
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures {
    if (!navigationAction.targetFrame.isMainFrame && [navigationAction.request.URL.absoluteString hasPrefix:@"https://m.facebook"]) {
        //[webView loadRequest:navigationAction.request];
        WKWebView *popup = [[WKWebView alloc] initWithFrame:self.view.frame configuration:configuration];
        popup.UIDelegate = self;
        popup.navigationDelegate = _navigationDelegate;
        [self.view addSubview:popup];
        [self.view bringSubviewToFront:self.toolbar];
        if (self.currentIndex+1 < self.webviewArr.count) {
            [self.webviewArr removeObjectsInRange:NSMakeRange(self.currentIndex+1, self.webviewArr.count-1-self.currentIndex)];
        }
        [self.webviewArr addObject:popup];
        self.currentWebview = popup;
        self.currentIndex++;
        if (self.backButtonItem.enabled == NO) {
            self.backButtonItem.enabled = YES;
            self.backButtonItem.image = [[UIImage imageNamed:@"Slice-left"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        }
        return popup;
    }else if (navigationAction.targetFrame == nil){
        [webView loadRequest:navigationAction.request];
    }
    return nil;
}

- (void) webViewDidClose:(WKWebView *)webView {
    [webView removeFromSuperview];
}


-(void)requstWithAction:(WKNavigationAction*)action{
    if(action.targetFrame && !action.targetFrame.isMainFrame && action.sourceFrame.isMainFrame && action.navigationType != WKNavigationTypeBackForward){
        if (self.currentIndex+1 < self.webviewArr.count) {
            [self.webviewArr removeObjectsInRange:NSMakeRange(self.currentIndex+1, self.webviewArr.count-1-self.currentIndex)];
        }
    }
}

- (UIView*)view {
  return _webView;
}

-(NSMutableArray *)webviewArr
{
    if (!_webviewArr) {
        _webviewArr = [NSMutableArray arrayWithCapacity:0];
    }
    return _webviewArr;
}

- (void)onMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  if ([[call method] isEqualToString:@"updateSettings"]) {
    [self onUpdateSettings:call result:result];
  } else if ([[call method] isEqualToString:@"loadUrl"]) {
    [self onLoadUrl:call result:result];
  } else if ([[call method] isEqualToString:@"canGoBack"]) {
    [self onCanGoBack:call result:result];
  } else if ([[call method] isEqualToString:@"canGoForward"]) {
    [self onCanGoForward:call result:result];
  } else if ([[call method] isEqualToString:@"goBack"]) {
    [self onGoBack:call result:result];
  } else if ([[call method] isEqualToString:@"goForward"]) {
    [self onGoForward:call result:result];
  } else if ([[call method] isEqualToString:@"reload"]) {
    [self onReload:call result:result];
  } else if ([[call method] isEqualToString:@"currentUrl"]) {
    [self onCurrentUrl:call result:result];
  } else if ([[call method] isEqualToString:@"evaluateJavascript"]) {
    [self onEvaluateJavaScript:call result:result];
  } else if ([[call method] isEqualToString:@"addJavascriptChannels"]) {
    [self onAddJavaScriptChannels:call result:result];
  } else if ([[call method] isEqualToString:@"removeJavascriptChannels"]) {
    [self onRemoveJavaScriptChannels:call result:result];
  } else if ([[call method] isEqualToString:@"clearCache"]) {
    [self clearCache:result];
  } else {
    result(FlutterMethodNotImplemented);
  }
}

- (void)onUpdateSettings:(FlutterMethodCall*)call result:(FlutterResult)result {
  [self applySettings:[call arguments]];
  result(nil);
}

- (void)onLoadUrl:(FlutterMethodCall*)call result:(FlutterResult)result {
  
  if (![self loadRequest:[call arguments]]) {
    result([FlutterError
        errorWithCode:@"loadUrl_failed"
              message:@"Failed parsing the URL"
              details:[NSString stringWithFormat:@"Request was: '%@'", [call arguments]]]);
  } else {
    result(nil);
  }
}

- (void)onCanGoBack:(FlutterMethodCall*)call result:(FlutterResult)result {
  BOOL canGoBack = [_webView canGoBack];
  result([NSNumber numberWithBool:canGoBack]);
}

- (void)onCanGoForward:(FlutterMethodCall*)call result:(FlutterResult)result {
  BOOL canGoForward = [_webView canGoForward];
  result([NSNumber numberWithBool:canGoForward]);
}

- (void)onGoBack:(FlutterMethodCall*)call result:(FlutterResult)result {
  [_webView goBack];
  result(nil);
}

- (void)onGoForward:(FlutterMethodCall*)call result:(FlutterResult)result {
  [_webView goForward];
  result(nil);
}

- (void)onReload:(FlutterMethodCall*)call result:(FlutterResult)result {
  [_webView reload];
  result(nil);
}

- (void)onCurrentUrl:(FlutterMethodCall*)call result:(FlutterResult)result {
  _currentUrl = [[_webView URL] absoluteString];
  result(_currentUrl);
}

- (void)onEvaluateJavaScript:(FlutterMethodCall*)call result:(FlutterResult)result {
  NSString* jsString = [call arguments];
  if (!jsString) {
    result([FlutterError errorWithCode:@"evaluateJavaScript_failed"
                               message:@"JavaScript String cannot be null"
                               details:nil]);
    return;
  }
  [_webView evaluateJavaScript:jsString
             completionHandler:^(_Nullable id evaluateResult, NSError* _Nullable error) {
               if (error) {
                 result([FlutterError
                     errorWithCode:@"evaluateJavaScript_failed"
                           message:@"Failed evaluating JavaScript"
                           details:[NSString stringWithFormat:@"JavaScript string was: '%@'\n%@",
                                                              jsString, error]]);
               } else {
                 result([NSString stringWithFormat:@"%@", evaluateResult]);
               }
             }];
}

- (void)onAddJavaScriptChannels:(FlutterMethodCall*)call result:(FlutterResult)result {
  NSArray* channelNames = [call arguments];
  NSSet* channelNamesSet = [[NSSet alloc] initWithArray:channelNames];
  [_javaScriptChannelNames addObjectsFromArray:channelNames];
  [self registerJavaScriptChannels:channelNamesSet
                        controller:_webView.configuration.userContentController];
  result(nil);
}

- (void)onRemoveJavaScriptChannels:(FlutterMethodCall*)call result:(FlutterResult)result {
  // WkWebView does not support removing a single user script, so instead we remove all
  // user scripts, all message handlers. And re-register channels that shouldn't be removed.
  [_webView.configuration.userContentController removeAllUserScripts];
  for (NSString* channelName in _javaScriptChannelNames) {
    [_webView.configuration.userContentController removeScriptMessageHandlerForName:channelName];
  }

  NSArray* channelNamesToRemove = [call arguments];
  for (NSString* channelName in channelNamesToRemove) {
    [_javaScriptChannelNames removeObject:channelName];
  }

  [self registerJavaScriptChannels:_javaScriptChannelNames
                        controller:_webView.configuration.userContentController];
  result(nil);
}

- (void)clearCache:(FlutterResult)result {
  if (@available(iOS 9.0, *)) {
    NSSet* cacheDataTypes = [WKWebsiteDataStore allWebsiteDataTypes];
    WKWebsiteDataStore* dataStore = [WKWebsiteDataStore defaultDataStore];
    NSDate* dateFrom = [NSDate dateWithTimeIntervalSince1970:0];
    [dataStore removeDataOfTypes:cacheDataTypes
                   modifiedSince:dateFrom
               completionHandler:^{
                 result(nil);
               }];
  } else {
    // support for iOS8 tracked in https://github.com/flutter/flutter/issues/27624.
    NSLog(@"Clearing cache is not supported for Flutter WebViews prior to iOS 9.");
  }
}

- (void)applySettings:(NSDictionary<NSString*, id>*)settings {
  for (NSString* key in settings) {
    if ([key isEqualToString:@"jsMode"]) {
      NSNumber* mode = settings[key];
      [self updateJsMode:mode];
    } else if ([key isEqualToString:@"hasNavigationDelegate"]) {
      NSNumber* hasDartNavigationDelegate = settings[key];
      _navigationDelegate.hasDartNavigationDelegate = [hasDartNavigationDelegate boolValue];
    } else {
      NSLog(@"webview_flutter: unknown setting key: %@", key);
    }
  }
}

- (void)updateJsMode:(NSNumber*)mode {
  WKPreferences* preferences = [[_webView configuration] preferences];
  switch ([mode integerValue]) {
    case 0:  // disabled
      [preferences setJavaScriptEnabled:NO];
      break;
    case 1:  // unrestricted
      [preferences setJavaScriptEnabled:YES];
      break;
    default:
      NSLog(@"webview_flutter: unknown JavaScript mode: %@", mode);
  }
}

- (bool)loadRequest:(NSDictionary<NSString*, id>*)request {
  if (!request) {
    return false;
  }

  NSString* url = request[@"url"];
  if ([url isKindOfClass:[NSString class]]) {
    id headers = request[@"headers"];
    if ([headers isKindOfClass:[NSDictionary class]]) {
      return [self loadUrl:url withHeaders:headers];
    } else {
      return [self loadUrl:url];
    }
  }

  return false;
}

- (bool)loadUrl:(NSString*)url {
  return [self loadUrl:url withHeaders:[NSMutableDictionary dictionary]];
}

- (bool)loadUrl:(NSString*)url withHeaders:(NSDictionary<NSString*, NSString*>*)headers {
  NSURL* nsUrl = [NSURL URLWithString:url];
  if (!nsUrl) {
    return false;
  }
  NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:nsUrl];
  [request setAllHTTPHeaderFields:headers];
  [_webView loadRequest:request];
  return true;
}

- (void)registerJavaScriptChannels:(NSSet*)channelNames
                        controller:(WKUserContentController*)userContentController {
  for (NSString* channelName in channelNames) {
    FLTJavaScriptChannel* channel =
        [[FLTJavaScriptChannel alloc] initWithMethodChannel:_channel
                                      javaScriptChannelName:channelName];
    [userContentController addScriptMessageHandler:channel name:channelName];
    NSString* wrapperSource = [NSString
        stringWithFormat:@"window.%@ = webkit.messageHandlers.%@;", channelName, channelName];
    WKUserScript* wrapperScript =
        [[WKUserScript alloc] initWithSource:wrapperSource
                               injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                            forMainFrameOnly:NO];
    [userContentController addUserScript:wrapperScript];
  }
}

- (void)dealloc
{
    [self.toolbar removeFromSuperview];
    [_webView removeObserver:self forKeyPath:@"estimatedProgress"];
    [_webView removeObserver:self forKeyPath:@"canGoBack"];
    [_webView removeObserver:self forKeyPath:@"canGoForward"];
    [_webView removeObserver:self forKeyPath:@"frame"];
    [_progresslayer removeFromSuperlayer];
}

@end
