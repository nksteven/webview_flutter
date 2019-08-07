// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.webviewflutter;

import android.annotation.TargetApi;
import android.app.Activity;
import android.app.AlertDialog;
import android.content.Context;
import android.content.DialogInterface;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Message;
import android.util.Log;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;

import android.view.WindowManager;
import android.webkit.CookieManager;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebStorage;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ProgressBar;

import io.flutter.app.FlutterApplication;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.platform.PlatformView;

import java.util.Collections;
import java.util.List;
import java.util.Map;

import static android.view.View.GONE;
import static android.view.View.VISIBLE;

public class FlutterWebView implements PlatformView, MethodCallHandler {

    private static final String JS_CHANNEL_NAMES_FIELD = "javascriptChannelNames";
    private final WebView webView;
    private WebView mWebviewPop;
    private final MethodChannel methodChannel;
    private final FlutterWebViewClient flutterWebViewClient;
    private final Handler platformThreadHandler;
    private Context mContext;
    private HorizontalProgressView popProgressBar;
    private HorizontalProgressView progressBar;
    private String TAG = "TAG";

    @SuppressWarnings("unchecked")
    FlutterWebView(Context context, BinaryMessenger messenger, int id, Map<String, Object> params) {
        Log.d("TAG", "FlutterWebView");
        Context activityContext = context;
        Context appContext = context.getApplicationContext();
        if (appContext instanceof FlutterApplication) {
            Activity currentActivity = ((FlutterApplication) appContext).getCurrentActivity();
            if (currentActivity != null) {
                activityContext = currentActivity;
            }
        }
        mContext = activityContext;
        webView = new WebView(activityContext);
        platformThreadHandler = new Handler(activityContext.getMainLooper());
        // Allow local storage.
        WebSettings settings = webView.getSettings();
        settings.setDomStorageEnabled(true);
        settings.setJavaScriptEnabled(true);
        settings.setSupportMultipleWindows(true);
        settings.setJavaScriptCanOpenWindowsAutomatically(true);

        webView.requestFocus(View.FOCUS_DOWN);

        methodChannel = new MethodChannel(messenger, "plugins.flutter.io/webview_" + id);
        methodChannel.setMethodCallHandler(this);

        flutterWebViewClient = new FlutterWebViewClient(methodChannel);

        webView.setWebChromeClient(new FacebookChromeClient());
        initProgressBar();

        applySettings((Map<String, Object>) params.get("settings"));
        if (params.containsKey(JS_CHANNEL_NAMES_FIELD)) {
            registerJavaScriptChannelNames((List<String>) params.get(JS_CHANNEL_NAMES_FIELD));
        }
        if (params.containsKey("initialUrl")) {
            String url = (String) params.get("initialUrl");
            webView.loadUrl(url);
        }
    }

    private void initProgressBar() {
        progressBar = new HorizontalProgressView(mContext, null);
        progressBar.setTextVisible(false);
        progressBar.setNormalBarSize(10);
        progressBar.setReachBarColor(Color.parseColor("#E06F01"));
        progressBar.setNormalBarColor(Color.TRANSPARENT);
        progressBar.setLayoutParams(new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,10));
        webView.addView(progressBar);
    }

    @Override
    public View getView() {
        return webView;
    }

    @Override
    public void onMethodCall(MethodCall methodCall, Result result) {
        switch (methodCall.method) {
            case "loadUrl":
                loadUrl(methodCall, result);
                break;
            case "updateSettings":
                updateSettings(methodCall, result);
                break;
            case "canGoBack":
                canGoBack(result);
                break;
            case "canGoForward":
                canGoForward(result);
                break;
            case "goBack":
                goBack(result);
                break;
            case "goForward":
                goForward(result);
                break;
            case "reload":
                reload(result);
                break;
            case "currentUrl":
                currentUrl(result);
                break;
            case "evaluateJavascript":
                evaluateJavaScript(methodCall, result);
                break;
            case "addJavascriptChannels":
                addJavaScriptChannels(methodCall, result);
                break;
            case "removeJavascriptChannels":
                removeJavaScriptChannels(methodCall, result);
                break;
            case "clearCache":
                clearCache(result);
                break;
            default:
                result.notImplemented();
        }
    }

    @SuppressWarnings("unchecked")
    private void loadUrl(MethodCall methodCall, Result result) {
        Map<String, Object> request = (Map<String, Object>) methodCall.arguments;
        String url = (String) request.get("url");
        Map<String, String> headers = (Map<String, String>) request.get("headers");
        if (headers == null) {
            headers = Collections.emptyMap();
        }
        webView.loadUrl(url, headers);
        result.success(null);
    }

    private void canGoBack(Result result) {
        result.success(webView.canGoBack());
    }

    private void canGoForward(Result result) {
        result.success(webView.canGoForward());
    }

    private void goBack(Result result) {
        if (webView.canGoBack()) {
            webView.goBack();
        }
        result.success(null);
    }

    private void goForward(Result result) {
        if (webView.canGoForward()) {
            webView.goForward();
        }
        result.success(null);
    }

    private void reload(Result result) {
        webView.reload();
        result.success(null);
    }

    private void currentUrl(Result result) {
        result.success(webView.getUrl());
    }

    @SuppressWarnings("unchecked")
    private void updateSettings(MethodCall methodCall, Result result) {
        applySettings((Map<String, Object>) methodCall.arguments);
        result.success(null);
    }

    @TargetApi(Build.VERSION_CODES.KITKAT)
    private void evaluateJavaScript(MethodCall methodCall, final Result result) {
        String jsString = (String) methodCall.arguments;
        if (jsString == null) {
            throw new UnsupportedOperationException("JavaScript string cannot be null");
        }
        webView.evaluateJavascript(
                jsString,
                new android.webkit.ValueCallback<String>() {
                    @Override
                    public void onReceiveValue(String value) {
                        result.success(value);
                    }
                });
    }

    @SuppressWarnings("unchecked")
    private void addJavaScriptChannels(MethodCall methodCall, Result result) {
        Log.d(TAG, "addJavaScriptChannels");
        List<String> channelNames = (List<String>) methodCall.arguments;
        registerJavaScriptChannelNames(channelNames);
        result.success(null);
    }

    @SuppressWarnings("unchecked")
    private void removeJavaScriptChannels(MethodCall methodCall, Result result) {
        List<String> channelNames = (List<String>) methodCall.arguments;
        for (String channelName : channelNames) {
            webView.removeJavascriptInterface(channelName);
        }
        result.success(null);
    }

    private void clearCache(Result result) {
        webView.clearCache(true);
        WebStorage.getInstance().deleteAllData();
        result.success(null);
    }

    private void applySettings(Map<String, Object> settings) {
        for (String key : settings.keySet()) {
            switch (key) {
                case "jsMode":
                    updateJsMode((Integer) settings.get(key));
                    break;
                case "hasNavigationDelegate":
                    final boolean hasNavigationDelegate = (boolean) settings.get(key);

                    final WebViewClient webViewClient =
                            flutterWebViewClient.createWebViewClient(hasNavigationDelegate);

                    webView.setWebViewClient(webViewClient);
                    break;
                case "debuggingEnabled":
                    final boolean debuggingEnabled = (boolean) settings.get(key);

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                        webView.setWebContentsDebuggingEnabled(debuggingEnabled);
                    }
                    break;
                default:
                    throw new IllegalArgumentException("Unknown WebView setting: " + key);
            }
        }
    }

    private void updateJsMode(int mode) {
        switch (mode) {
            case 0: // disabled
                webView.getSettings().setJavaScriptEnabled(false);
                break;
            case 1: // unrestricted
                webView.getSettings().setJavaScriptEnabled(true);
                break;
            default:
                throw new IllegalArgumentException("Trying to set unknown JavaScript mode: " + mode);
        }
    }

    private void registerJavaScriptChannelNames(List<String> channelNames) {
        for (String channelName : channelNames) {
            webView.addJavascriptInterface(
                    new JavaScriptChannel(methodChannel, channelName, platformThreadHandler), channelName);
        }
    }

    @Override
    public void dispose() {
        Log.d(TAG, "webView---dispose");
        if (mWebviewPop != null) {
            mWebviewPop.clearCache(true);
            mWebviewPop.destroy();
        }
        if (webView != null) {
            webView.clearFocus();
            webView.clearCache(true);
            webView.removeAllViews();
            webView.destroy();
        }
        methodChannel.setMethodCallHandler(null);
    }

    AlertDialog builder;

    void showDialog(){
        builder = new AlertDialog.Builder(mContext, AlertDialog.THEME_DEVICE_DEFAULT_DARK).create();

        popProgressBar = new HorizontalProgressView(mContext, null);
        popProgressBar.setNormalBarSize(15);
        popProgressBar.setReachBarSize(15);
        popProgressBar.setLayoutParams(new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,ViewGroup.LayoutParams.WRAP_CONTENT));
        builder.setCustomTitle(popProgressBar);
        builder.setView(mWebviewPop);
        builder.setCancelable(false);
        builder.setButton("Close", new DialogInterface.OnClickListener() {
            @Override
            public void onClick(DialogInterface dialog, int id) {
                if(mWebviewPop!=null){
                    mWebviewPop.destroy();
                    mWebviewPop=null;
                }
                dialog.dismiss();
            }
        });
        builder.show();
        builder.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE | WindowManager.LayoutParams.FLAG_ALT_FOCUSABLE_IM);
    }


    class FacebookChromeClient extends WebChromeClient {

        @Override
        public boolean onCreateWindow(WebView view, boolean isDialog,
                                      boolean isUserGesture, Message resultMsg) {
            Log.d(TAG,"onCreatWindow  url="+view.getUrl());
            mWebviewPop = new WebView(mContext);
            mWebviewPop.setVerticalScrollBarEnabled(false);
            mWebviewPop.setWebChromeClient(this);
            mWebviewPop.setWebViewClient(new FacebookWebviewClient());

            WebSettings settings = mWebviewPop.getSettings();
            settings.setDomStorageEnabled(true);
            settings.setJavaScriptEnabled(true);
            settings.setSupportMultipleWindows(true);
            settings.setJavaScriptCanOpenWindowsAutomatically(true);

            mWebviewPop.setFocusable(true);
            mWebviewPop.requestFocus(View.FOCUS_DOWN);
            mWebviewPop.requestFocusFromTouch();
            CookieManager cookieManager = CookieManager.getInstance();
            cookieManager.setAcceptCookie(true);
            WebView.WebViewTransport transport = (WebView.WebViewTransport) resultMsg.obj;
            transport.setWebView(mWebviewPop);
            resultMsg.sendToTarget();
            return true;
        }

        @Override
        public void onCloseWindow(WebView window) {
            try {
                if (mWebviewPop != null) {
                    mWebviewPop.destroy();
                    mWebviewPop = null;
                }
            } catch (Exception e) {
            }
            try {
                if (builder != null && builder.isShowing()) {
                    popProgressBar =null;
                    builder.dismiss();
                    builder = null;
                }
            } catch (Exception e) {

            }
            super.onCloseWindow(window);
            Log.d(TAG, "--------------onCloseWindow");
        }

        @Override
        public void onProgressChanged(WebView view, int newProgress) {
            Log.d(TAG, "onProgressChanged--------------newProgress-" + newProgress);
            if (popProgressBar != null) {
                if (newProgress == 100) {
                    popProgressBar.setVisibility(GONE);
                } else {
                    if (popProgressBar.getVisibility() == GONE) {
                        popProgressBar.setVisibility(VISIBLE);
                    }
                    popProgressBar.setProgress(newProgress);
                }
            }else{
                if (progressBar!=null){
                    if (newProgress == 100) {
                        progressBar.setVisibility(GONE);
                    } else {
                        if (progressBar.getVisibility() == GONE) {
                            progressBar.setVisibility(VISIBLE);
                        }
                        progressBar.setProgress(newProgress);
                    }
                }
            }
            super.onProgressChanged(view, newProgress);
        }
    }

    class FacebookWebviewClient extends WebViewClient {

        @Override
        public boolean shouldOverrideUrlLoading(WebView view, String url) {
            Log.d(TAG, "FacebookWebviewClient--------------shouldOverrideUrlLoading--url=" + url);
            String host=Uri.parse(url).getHost();
            if (host.equals("m.facebook.com")){
                if (builder!=null&&builder.isShowing()){
                    view.loadUrl(url);
                }else{
                    showDialog();
                    view.loadUrl(url);
                }
            }else{
                webView.loadUrl(url);
            }
            return true;
        }

        @Override
        public void onPageFinished(WebView view, String url) {
            Log.d(TAG, "FacebookWebviewClient--------------onPageFinished--url=" + url);
            super.onPageFinished(view, url);
        }

    }


}
