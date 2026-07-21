# EarControl Agent Guide

## 项目定位

EarControl 是一个 macOS 菜单栏工具，把 Apple 有线 EarPods 三键线控映射为微信输入法语音工作流。

## 运行与验证

- 开发构建：`swift build`
- 应用包：`./build-app.sh`
- 免费测试 DMG：`./build-dmg.sh`
- 最低系统：macOS 13；需要 Xcode Command Line Tools
- 改动按键内核后，必须用真实 EarPods 验证 README 的八项步骤；编译通过不能代替硬件验证。

## 技术栈

- Swift 5.9、SwiftUI、AppKit
- IOKit HID 负责线控读取和优先独占
- CoreGraphics 负责权限检查、回退过滤和合成键盘事件
- ServiceManagement 负责登录时启动

## 目录与约定

- `Sources/EarControl/main.swift`：应用生命周期、HID 和映射状态机
- `Sources/EarControl/EarControlUI.swift`：状态模型、菜单栏面板和设置
- `Sources/EarControl/EarControlSetupView.swift`：首次设置检查
- `README.md`：现役用户合同；`docs/INSTALL.md`：安装与权限处理
- 版本号以 `Info.plist` 为准。发布说明和下载文件名必须同步。
- 不提交 `.build/`、`dist/`、诊断内容或用户输入。

## 当前状态与下一步

- 当前准备发布的免费测试版为 v1.7.5，已完成窗口层级与语音中断恢复实机验证；公开 DMG 必须使用稳定代码签名。
- 默认支持右 Option，也可切换为右 Command。
- 中键单击、双击和三击已支持快捷键与两个预设动作；长按固定执行全选并清空。
- 菜单栏图标按菜单栏自身对比外观生成黑/白像素，必须同时验证原生菜单栏与 Thaw/Ice 捕获场景。
- 设置或首次配置窗口可见时，顶栏图标必须优先恢复该窗口；重复按音量减必须能够重新建立语音触发键状态。
- 面向陌生用户稳定分发仍需 Developer ID 签名和 Apple 公证。
