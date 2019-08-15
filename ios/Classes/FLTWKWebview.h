//
//  FLTWKWebview.h
//  Pods-Runner
//
//  Created by songsong on 2019/8/15.
//

#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface FLTWKWebview : WKWebView

@property(nonatomic,strong) UIView * toolBar;

@property(nonatomic,strong) UIBarButtonItem * backButton;

@property(nonatomic,strong) UIBarButtonItem * forwardButton;

@end

NS_ASSUME_NONNULL_END
