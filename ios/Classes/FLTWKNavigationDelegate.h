// Copyright 2019 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import <Flutter/Flutter.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FLTWebviewLoadUrlDelagate <NSObject>

-(void)requstWithAction:(WKNavigationAction*)action;

@end

@interface FLTWKNavigationDelegate : NSObject <WKNavigationDelegate>

- (instancetype)initWithChannel:(FlutterMethodChannel*)channel;

/**
 * Whether to delegate navigation decisions over the method channel.
 */
@property(nonatomic, assign) BOOL hasDartNavigationDelegate;
@property(nonatomic, weak) id<FLTWebviewLoadUrlDelagate> delegate;
@end

NS_ASSUME_NONNULL_END
