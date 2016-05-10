# Parse源码浅析系列（一）---Parse的底层多线程处理思路：GCD高级用法

【前言】从iOS7升到iOS8后，GCD 出现了一个重大的变化：在 iOS7 时，使用 GCD 的并行队列，  `dispatch_async`  最大开启的线程一直能控制在6、7条，线程数都是个位数，然而 iOS8后，最大线程数一度可以达到40条、50条。然而在文档上并没有对这一做法的目的进行介绍。

笔者推测 Apple 的目的是想借此让开发者使用 `NSOperationQueue` ：GCD 中 Apple 并没有提供控制并发数量的接口，而  `NSOperationQueue`  有。GCD 没有提供暂停、恢复、取消队列任务的接口，而  `NSOperationQueue`  有，如果想让 GCD 支持 `NSOperationQueue` 原生就支持的功能，需要使用许多GCD 的高级功能，大大提高了使用的难度。


 `Apple`  始终有一个观念：尽可能选用高层 API，只在确有必要时才求助于底层。然而开发者并不买账，在我进行的一次 [调查](http://weibo.com/1692391497/D1pKjqaiW?type=comment) 中发现了一个有趣的现象：

大概 80%的iOS 开发者会支持使用 GCD 来完成操作队列的实现，而且有 60% 的开发已经在项目中使用。

![enter image description here](http://i65.tinypic.com/2vj1md2.jpg)


更是有人这样表态：


假如不让他用 GCD：


![enter image description here](http://i66.tinypic.com/34g8qd1.jpg)

这种现象一直存在，包括 ARC 与 MRC、SB建 UI 与纯代码建 UI、SQL 与 CoreData的争论。

但是因为是源码解析的文章，而 Parse 的 SDK 没有用一句的 NSOperation 的代码，GCD 一路用到底，让我也十分震惊。只能说明，写  `Parse`  的这位开发者是艺高人胆大。而且既然  `GCD`  的支持者如此之多，那么就谈一谈如何让 GCD 能支持 `NSOperationQueue` 原生就支持的功能。


今天虽然谈了NSOperation原生功能的 GCD 版本实现，但并不代表我支持像 Parse 这样 GCD 一路用到底。 业内一般的看法是这样的：


 >  `GCD` 虽然能够实现暂停和终止，但开发还是灵活些好，那些 `NSOperation` 用起来方便的就直接用 `NSOperation` 的方式，不然苹果多包那一层不是蛋疼，包括文章里提到的 `iOS8` 后控制线程数的问题，不一定项目就一定要GCD一路到底。有时候需要支持一些高层级封装功能比如： `KVO` 时 `NSOperation` 还是有它的优势的。 `GCD` 反而是处理些比较简单的操作或者是较系统级的比如：监视进程或者监视文件夹内文件的变化之类的比较合适。



（iOS开发学习交流群：541317935）


第一篇的目的是通过解读 Parse 源码来展示GCD两个高级用法： `Dispatch Source ` （派发源）和 `Dispatch Semaphore`  （信号量）。首先通过Parse 的“离线存储对象”操作，来介绍 `Dispatch Source ` （派发源）；然后通过Parse 的单元测试中使用的技巧“强制把异步任务转换为同步任务来方便进行单元测试”来介绍`Dispatch Semaphore`  （信号量）。我已将思路浓缩为可运行的7个 Demo 中，详见仓库里的 Demo1到 Demo7。

如果对 GCD 不太熟悉，请先读下[《GCD 扫盲篇》](https://github.com/ChenYilong/ParseSourceCodeStudy/blob/master/01_Parse的多线程处理思路/GCD扫盲篇.md)。


 1.  Dispatch Source分派源
  2.  [Parse-iOS-SDK介绍](https://github.com/ChenYilong/ParseSourceCodeStudy/blob/master/01_Parse的多线程处理思路/Parse的底层多线程处理思路.md#parse-ios-sdk介绍) 

  2.  [Parse 的“离线存储对象”操作介绍](https://github.com/ChenYilong/ParseSourceCodeStudy/blob/master/01_Parse的多线程处理思路/Parse的底层多线程处理思路.md#parse-的离线存储对象操作介绍) 
  2.  [Parse 的“离线存储对象”实现介绍](https://github.com/ChenYilong/ParseSourceCodeStudy/blob/master/01_Parse的多线程处理思路/Parse的底层多线程处理思路.md#parse-的离线存储对象实现介绍) 
  2.  [Dispatch Source 的使用步骤](https://github.com/ChenYilong/ParseSourceCodeStudy/blob/master/01_Parse的多线程处理思路/Parse的底层多线程处理思路.md#dispatch-source-的使用步骤) 
     1.  [第一步：创建一个Dispatch Source](https://github.com/ChenYilong/ParseSourceCodeStudy/blob/master/01_Parse的多线程处理思路/Parse的底层多线程处理思路.md#第一步创建一个dispatch-source) 
     2.  [第二步：创建Dispatch Source的事件处理方法](https://github.com/ChenYilong/ParseSourceCodeStudy/blob/master/01_Parse的多线程处理思路/Parse的底层多线程处理思路.md#第二步创建dispatch-source的事件处理方法) 
     3.  [第三步：处理Dispatch Source的暂停与恢复操作](https://github.com/ChenYilong/ParseSourceCodeStudy/blob/master/01_Parse的多线程处理思路/Parse的底层多线程处理思路.md#第三步处理dispatch-source的暂停与恢复操作) 
     4.  [第四步：向Dispatch Source发送事件](https://github.com/ChenYilong/ParseSourceCodeStudy/blob/master/01_Parse的多线程处理思路/Parse的底层多线程处理思路.md#第四步向dispatch-source发送事件) 
  2.  [GCD真的不能像OperationQueue那样终止任务？](https://github.com/ChenYilong/ParseSourceCodeStudy/blob/master/01_Parse的多线程处理思路/Parse的底层多线程处理思路.md#gcd真的不能像operationqueue那样终止任务) 
  2.  [完整例子Demo1：让 Dispatch Source “帮” Dispatch Queue 实现暂停和恢复功能](https://github.com/ChenYilong/ParseSourceCodeStudy/blob/master/01_Parse的多线程处理思路/Parse的底层多线程处理思路.md#完整例子demo1让-dispatch-source-帮-dispatch-queue-实现暂停和恢复功能) 
  2.  [DispatchSource能通过合并事件的方式确保在高负载下正常工作](https://github.com/ChenYilong/ParseSourceCodeStudy/blob/master/01_Parse的多线程处理思路/Parse的底层多线程处理思路.md#dispatchsource能通过合并事件的方式确保在高负载下正常工作) 
  2.  [Dispatch Source 与 Dispatch Queue 两者在线程执行上的关系](https://github.com/ChenYilong/ParseSourceCodeStudy/blob/master/01_Parse的多线程处理思路/Parse的底层多线程处理思路.md#dispatch-source-与-dispatch-queue-两者在线程执行上的关系) 
  2.  [让 Dispatch Source 与 Dispatch Queue 同时实现暂停和恢复](https://github.com/ChenYilong/ParseSourceCodeStudy/blob/master/01_Parse的多线程处理思路/Parse的底层多线程处理思路.md#让-dispatch-source-与-dispatch-queue-同时实现暂停和恢复) 
  2.  [Parse “离线存储对象”操作的代码摘录](https://github.com/ChenYilong/ParseSourceCodeStudy/blob/master/01_Parse的多线程处理思路/Parse的底层多线程处理思路.md#parse-离线存储对象操作的代码摘录) 
 2.  [Dispatch Semaphore 信号量](https://github.com/ChenYilong/ParseSourceCodeStudy/blob/master/01_Parse的多线程处理思路/Parse的底层多线程处理思路.md#dispatch-semaphore-信号量) 
  1.  [在项目中的应用：强制把异步任务转换为同步任务来方便进行单元测试](https://github.com/ChenYilong/ParseSourceCodeStudy/blob/master/01_Parse的多线程处理思路/Parse的底层多线程处理思路.md#在项目中的应用强制把异步任务转换为同步任务来方便进行单元测试) 
  2.  [使用Dispatch Semaphore控制并发线程数量](https://github.com/ChenYilong/ParseSourceCodeStudy/blob/master/01_Parse的多线程处理思路/Parse的底层多线程处理思路.md#使用dispatch-semaphore控制并发线程数量) 
  3.  [为 NSURLSession 添加同步方法](https://github.com/ChenYilong/ParseSourceCodeStudy/blob/master/01_Parse的多线程处理思路/Parse的底层多线程处理思路.md#为--nsurlsession-添加同步方法)
     1.   [风险：导致Watchdog超时](https://github.com/ChenYilong/ParseSourceCodeStudy/blob/master/01_Parse的多线程处理思路/Parse的底层多线程处理思路.md#导致watchdog超时) 
     2.   [风险：失去了 cancel 的机会](https://github.com/ChenYilong/ParseSourceCodeStudy/blob/master/01_Parse的多线程处理思路/Parse的底层多线程处理思路.md#失去了-cancel-的机会) 

## Parse-iOS-SDK介绍


 [《iOS开发周报：iOS 8.4.1 发布，iOS 8 时代谢幕》](http://www.infoq.com/cn/news/2015/08/ios-weekly-ios841#rd) 对 Facebook 旗下的 Parse有这样一段介绍：

 > Parse-SDK-iOS-OSX：著名的 BaaS 公司 Parse 最近开源了它们的 iOS/OSX SDK。Parse 的服务虽然在国内可能访问速度不是很理想，但是它们在服务的稳定性和 SDK 质量上一直有非常优异的表现。此次开源的 SDK 对于日常工作是 SDK 开发的开发者来说，是一个难得的学习机会。Parse 的存取操作涉及到很多多线程的问题，从 Parse SDK 的源代码中可以看出，这个 SDK 的开发者对 iOS 开发多线程有着非常深厚的理解和功底，让人叹服。我个人推荐对此感兴趣的朋友可以尝试从阅读 internal 文件夹下的两个EventuallyQueue 文件开始着手，研究下 Parse 的底层多线程处理思路。

类似的服务：
 Apple 的 [Cloud​Kit](http://nshipster.cn/cloudkit/) 、 国内的 [LeanCloud（原名 `AVOS` ）](https://leancloud.cn/?source=T6M35E4H) 。

## Parse 的“离线存储对象”操作介绍


大多数保存功能可以立刻执行，并通知应用“保存完毕”。不过若不需要知道保存完成的时间，则可使用“离线存储对象”操作（saveEventually 或 deleteEventually） 来代替，也就是：

如果用户目前尚未接入网络，“离线存储对象”操作（saveEventually 或 deleteEventually） 会缓存设备中的数据，并在网络连接恢复后上传。如果应用在网络恢复之前就被关闭了，那么当它下一次打开时，SDK 会自动再次尝试保存操作。

所有 saveEventually（或 deleteEventually）的相关调用，将按照调用的顺序依次执行。因此，多次对某一对象使用 saveEventually 是安全的。

国内的 [LeanCloud（原名 `AVOS` ）](https://leancloud.cn/?source=T6M35E4H) 也提供了相同的功能，所以以上《Parse 的“离线存储对象”操作介绍》部分完全摘录自 LeanCloud 的文档。详见[《LeanCloud官方文档-iOS / OS X 数据存储开发指南--离线存储对象》](https://leancloud.cn/docs/ios_os_x_guide.html#离线存储对象) 

（利益相关声明：本人目前就职于 [LeanCloud（原名 `AVOS` ）](https://leancloud.cn/?source=T6M35E4H) ）


## Parse 的“离线存储对象”实现介绍

Parse 的“离线存储对象”操作（saveEventually 或 deleteEventually） 是通过 GCD 的 `Dispatch Source` （信号源）来实现的。下面对 `Dispatch Source` （信号源）进行一下介绍：



GCD中除了主要的 `Dispatch Queue` 外，还有不太引人注目的 `Dispatch Source` .它是BSD系内核惯有功能kqueue的包装。kqueue 是在 XNU 内核中发生各种事件时，在应用程序编程方执行处理的技术。其 CPU 负荷非常小，尽量不占用资源。kqueue 可以说是应用程序处理 XNU 内核中发生的各种事件的方法中最优秀的一种。

 `Dispatch Source` 也使用在了 Core Foundation 框架的用于异步网络的API  `CFSocket` 中。因为Foundation 框架的异步网络 API 是通过CFSocket实现的，所以可享受到仅使用 Foundation 框架的 `Dispatch Source` 带来的好处。

那么优势何在？使用的 `Dispatch Source` 而不使用 `dispatch_async` 的唯一原因就是利用联结的优势。

联结的大致流程：在任一线程上调用它的的一个函数 `dispatch_source_merge_data`  后，会执行 `Dispatch Source` 事先定义好的句柄（可以把句柄简单理解为一个 block ）。

这个过程叫 `Custom event` ,用户事件。是 dispatch source 支持处理的一种事件。

 > 简单地说，这种事件是由你调用 `dispatch_source_merge_data` 函数来向自己发出的信号。

下面介绍下使用步骤：

## `Dispatch Source` 的使用步骤

### 第一步：创建一个`Dispatch Source`


 ```Objective-C
    // 详见 Demo1、Demo2
    // 指定DISPATCH_SOURCE_TYPE_DATA_ADD，做成Dispatch Source(分派源)。设定Main Dispatch Queue 为追加处理的Dispatch Queue
    _processingQueueSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_DATA_ADD, 0, 0,
                                                    dispatch_get_main_queue());
 ```

下面对参数进行下解释：

其中自定义源累积事件中传递过来的值，累积的方式可以是相加的，正如上面代码中的 `DISPATCH_SOURCE_TYPE_DATA_ADD` ，也可以是逻辑或 `DISPATCH_SOURCE_TYPE_DATA_OR` 。这是最常见的两个 `Dispatch Source` 可以处理的事件。


`Dispatch Source` 可处理的所有事件。如下表所示：

|名称|内容|
-------------|-------------
 `DISPATCH_SOURCE_TYPE_DATA_ADD`  | 变量增加
 `DISPATCH_SOURCE_TYPE_DATA_OR`  | 变量OR
 `DISPATCH_SOURCE_TYPE_MACH_SEND`  | MACH端口发送
 `DISPATCH_SOURCE_TYPE_MACH_RECV`  |  MACH端口接收
 `DISPATCH_SOURCE_TYPE_PROC` | 监测到与进程相关的事件
 `DISPATCH_SOURCE_TYPE_READ`  | 可读取文件映像
 `DISPATCH_SOURCE_TYPE_SIGNAL`  | 接收信号
 `DISPATCH_SOURCE_TYPE_TIMER`  | 定时器
 `DISPATCH_SOURCE_TYPE_VNODE`  | 文件系统有变更
 `DISPATCH_SOURCE_TYPE_WRITE`  | 可写入文件映像


自定义源也需要一个队列，用来处理所有的响应句柄（block）。那么岂不是有两个队列了？没错，至于 `Dispatch Queue` 这个队列的线程执行与  `Dispatch Source`这个队列的线程执行的关系，下文会结合 Demo1和 Demo2进行详细论述。

### 第二步：创建`Dispatch Source`的事件处理方法


分派源提供了高效的方式来处理事件。首先注册事件处理程序，事件发生时会收到通知。如果在系统还没有来得及通知你之前事件就发生了多次，那么这些事件会被合并为一个事件。这对于底层的高性能代码很有用，但是OS应用开发者很少会用到这样的功能。类似地，分派源可以响应UNIX信号、文件系统的变化、其他进程的变化以及Mach Port事件。它们中很多都在Mac系统上很有用，但是iOS开发者通常不会用到。

不过，自定义源在iOS中很有用，尤其是在性能至关重要的场合进行进度反馈。如下所示，首先创建一个源:自定义源累积事件中传递过来的值。累积方式可以是相加( DISPATCH_SOURCE_TYPE_DATA_ADD ),
也可以是逻辑或( DISPATCH_SOURCE_DATA_OR )。自定义源也需要一个队列，用来处理所有的响应处理块。

创建源后，需要提供相应的处理方法。当源生效时会分派注册处理方法;当事件发生时会分派事件处理方法;当源被取消时会分派取消处理方法。自定义源通常只需要一个事件处理方法，可以像这样创建:


 ```Objective-C

 /*
  *省略部分： 
    指定DISPATCH_SOURCE_TYPE_DATA_ADD，做成Dispatch Source(分派源)。设定Main Dispatch Queue 为追加处理的Dispatch Queue
    详见Demo1、Demo2
  *
  */
    __block NSUInteger totalComplete = 0;
    dispatch_source_set_event_handler(_processingQueueSource, ^{
        //当处理事件被最终执行时，计算后的数据可以通过dispatch_source_get_data来获取。这个数据的值在每次响应事件执行后会被重置，所以totalComplete的值是最终累积的值。
        NSUInteger value = dispatch_source_get_data(_processingQueueSource);
        totalComplete += value;
        NSLog(@"进度：%@", @((CGFloat)totalComplete/100));
    });
 ```



在同一时间，只有一个处理方法块的实例被分派。如果这个处理方法还没有执行完毕，另一个事件就发生了，事件会以指定方式(ADD或者OR)进行累积。通过合并事件的方式，系统即使在高负
载情况下也能正常工作。当处理事件件被最终执行时，计算后的数据可以通过 `dispatch_source_get_data` 来获取。这个数据的值在每次响应事件执行后会被重置，所以上面例子中 `totalComplete` 的值是最终累积的值。

### 第三步：处理`Dispatch Source`的暂停与恢复操作


当追加大量处理到Dispatch Queue时，在追加处理的过程中，有时希望不执行已追加的处理。例如演算结果被Block截获时，一些处理会对这个演算结果造成影响。

在这种情况下，只要挂起Dispatch Queue即可。当可以执行时再恢复。

 ```Objective-C
dispatch_suspend(queue);
 ```

 `dispatch_resume` 函数恢复指定的 `Dispatch Queue` .
这些函数对已经执行的处理没有影响。挂起后，追加到 `Dispatch Queue` 中但尚未执行的处理在此之后停止执行。而恢复则使得这些处理能够继续执行。

分派源创建时默认处于暂停状态，在分派源分派处理程序之前必须先恢复。因为忘记恢复分派源的状态而产生bug是常见的事儿。恢复的方法是调用 `dispatch_resume` :

 ```Objective-C
dispatch_resume (source);
 ```

为了方便理解 `dispatch_suspend` 函数的作用，这里提供一个 Demo：Demo3， 看下运行效果：

思考下NSLog的打印顺序为什么会是这样？


详见 Demo3（Demo_03_对DispatchQueue实现取消恢复操作_简单版）：


 ```Objective-C
- (void)viewDidLoad {
    [super viewDidLoad];
    
    dispatch_queue_t queue1 = dispatch_queue_create("com.iOSChengXuYuan.queue1", 0);
    dispatch_queue_t queue2 = dispatch_queue_create("com.iOSChengXuYuan.queue2", 0);
    dispatch_group_t group = dispatch_group_create();
    
    dispatch_async(queue1, ^{
        NSLog(@"任务 1 ： queue 1...");
        sleep(1);
        NSLog(@"✅完成任务 1");
    });
    
    dispatch_async(queue2, ^{
        NSLog(@"任务 1 ： queue 2...");
        sleep(1);
        NSLog(@"✅完成任务 2");
    });
    
    dispatch_group_async(group, queue1, ^{
        NSLog(@"🚫正在暂停 1");
        dispatch_suspend(queue1);
    });
    dispatch_group_async(group, queue2, ^{
        NSLog(@"🚫正在暂停 2");
        dispatch_suspend(queue2);
    });
    
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    NSLog(@"＝＝＝＝＝＝＝等待两个queue完成, 再往下进行...");
    dispatch_async(queue1, ^{
        NSLog(@"任务 2 ： queue 1");
    });
    dispatch_async(queue2, ^{
        NSLog(@"任务 2 ： queue 2");
    });
    NSLog(@"🔴为什么这个NSLog会在上面两个NSLog之前打印❓❓答：dispatch_suspend的作用‼️");
    
    dispatch_resume(queue1);
    dispatch_resume(queue2);
}
 ```

打印：

 ```Objective-C
2015-09-06 02:44:59.614 CYLDispatchQueueSuspendTest[1610:116662] 任务 1 ： queue 2...
2015-09-06 02:44:59.613 CYLDispatchQueueSuspendTest[1610:116665] 任务 1 ： queue 1...
2015-09-06 02:45:00.614 CYLDispatchQueueSuspendTest[1610:116665] ✅完成任务 1
2015-09-06 02:45:00.614 CYLDispatchQueueSuspendTest[1610:116662] ✅完成任务 2
2015-09-06 02:45:00.616 CYLDispatchQueueSuspendTest[1610:116662] 🚫正在暂停 2
2015-09-06 02:45:00.615 CYLDispatchQueueSuspendTest[1610:116665] 🚫正在暂停 1
2015-09-06 02:45:00.616 CYLDispatchQueueSuspendTest[1610:116515] ＝＝＝＝＝＝＝等待两个queue完成, 再往下进行...
2015-09-06 02:45:00.616 CYLDispatchQueueSuspendTest[1610:116515] 🔴为什么这个NSLog会在上面两个NSLog之前打印❓❓答：dispatch_suspend的作用‼️
2015-09-06 02:45:00.617 CYLDispatchQueueSuspendTest[1610:116665] 任务 2 ： queue 1
2015-09-06 02:45:00.619 CYLDispatchQueueSuspendTest[1610:116665] 任务 2 ： queue 2
 ```

思考下NSLog的打印顺序为什么会是这样？答：dispatch_suspend的作用！

详见 Demo3（Demo_03_对DispatchQueue实现取消恢复操作_简单版）。


### 第四步：向`Dispatch Source`发送事件

恢复源后，就可以像下面的代码片段这样，通过 `dispatch_source_merge_data` 向分派源发送事件:

 ```Objective-C
    //2.
    //恢复源后，就可以通过dispatch_source_merge_data向Dispatch Source(分派源)发送事件:
    //详见Demo1、Demo2
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
        for (NSUInteger index = 0; index < 100; index++) {
            dispatch_async(queue, ^{
            dispatch_source_merge_data(_processingQueueSource, 1);
            usleep(20000);//0.02秒
            });
        }
 ```

上面代码在每次循环中执行加1操作。也可以传递已处理记录的数目或已写入的字节数。在任何线程中都可以调用  `dispatch_source_merge_data` 。需要注意的是，不可以传递0值(事件不会被触发)，同样也不可以传递负数。


# GCD真的不能像OperationQueue那样终止任务？

### 完整例子Demo1：让 Dispatch Source “帮” Dispatch Queue 实现暂停和恢复功能

本节配套代码在 `Demo1` 中（Demo_01_对DispatchSource实现取消恢复操作_main队列版）。

先写一段代码演示下DispatchSource的基本用法：

 ```Objective-C
//
//  .m
//  CYLDispatchSourceTest
//
//  Created by 微博@iOS程序犭袁（ http://weibo.com/luohanchenyilong/） on 15/9/1.
//  Copyright (c) 2015年 https://github.com/ChenYilong . All rights reserved.
//

- (void)viewDidLoad {
    [super viewDidLoad];
    //1.
    // 指定DISPATCH_SOURCE_TYPE_DATA_ADD，做成Dispatch Source(分派源)。设定Main Dispatch Queue 为追加处理的Dispatch Queue
    _processingQueueSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_DATA_ADD, 0, 0,
                                                    dispatch_get_main_queue());
    __block NSUInteger totalComplete = 0;
    dispatch_source_set_event_handler(_processingQueueSource, ^{
        //当处理事件被最终执行时，计算后的数据可以通过dispatch_source_get_data来获取。这个数据的值在每次响应事件执行后会被重置，所以totalComplete的值是最终累积的值。
        NSUInteger value = dispatch_source_get_data(_processingQueueSource);
        totalComplete += value;
        NSLog(@"进度：%@", @((CGFloat)totalComplete/100));
        NSLog(@"🔵线程号：%@", [NSThread currentThread]);
    });
    //分派源创建时默认处于暂停状态，在分派源分派处理程序之前必须先恢复。
    [self resume];
    
    //2.
    //恢复源后，就可以通过dispatch_source_merge_data向Dispatch Source(分派源)发送事件:
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_async(queue, ^{
        for (NSUInteger index = 0; index < 100; index++) {
            dispatch_source_merge_data(_processingQueueSource, 1);
            NSLog(@"♻️线程号：%@", [NSThread currentThread]);
            usleep(20000);//0.02秒
        }
    });
}

 ```


则输出日志：

 ```Objective-C
2015-09-03 16:50:48.346 CYLDispatchSourceTest[8331:874681] ✅恢复Dispatch Source(分派源)
2015-09-03 16:50:48.348 CYLDispatchSourceTest[8331:874889] ♻️线程号：<NSThread: 0x7ff3735abe40>{number = 2, name = (null)}
2015-09-03 16:50:48.372 CYLDispatchSourceTest[8331:874889] ♻️线程号：<NSThread: 0x7ff3735abe40>{number = 2, name = (null)}
2015-09-03 16:50:48.401 CYLDispatchSourceTest[8331:874889] ♻️线程号：<NSThread: 0x7ff3735abe40>{number = 2, name = (null)}
2015-09-03 16:50:48.424 CYLDispatchSourceTest[8331:874889] ♻️线程号：<NSThread: 0x7ff3735abe40>{number = 2, name = (null)}
2015-09-03 16:50:48.444 CYLDispatchSourceTest[8331:874889] ♻️线程号：<NSThread: 0x7ff3735abe40>{number = 2, name = (null)}
2015-09-03 16:50:48.473 CYLDispatchSourceTest[8331:874889] ♻️线程号：<NSThread: 0x7ff3735abe40>{number = 2, name = (null)}
2015-09-03 16:50:48.493 CYLDispatchSourceTest[8331:874889] ♻️线程号：<NSThread: 0x7ff3735abe40>{number = 2, name = (null)}
2015-09-03 16:50:48.515 CYLDispatchSourceTest[8331:874681] 进度：0.07000000000000001
2015-09-03 16:50:48.515 CYLDispatchSourceTest[8331:874681] 🔵线程号：<NSThread: 0x7ff373428140>{number = 1, name = main}
2015-09-03 16:50:48.516 CYLDispatchSourceTest[8331:874681] 进度：0.08
2015-09-03 16:50:48.516 CYLDispatchSourceTest[8331:874889] ♻️线程号：<NSThread: 0x7ff3735abe40>{number = 2, name = (null)}
2015-09-03 16:50:48.535 CYLDispatchSourceTest[8331:874681] 🔵线程号：<NSThread: 0x7ff373428140>{number = 1, name = main}
2015-09-03 16:50:48.556 CYLDispatchSourceTest[8331:874681] 进度：0.09
/*================省略中间====================*/
2015-09-03 16:50:50.630 CYLDispatchSourceTest[8331:874681] 🔵线程号：<NSThread: 0x7ff373428140>{number = 1, name = main}
2015-09-03 16:50:50.630 CYLDispatchSourceTest[8331:874889] ♻️线程号：<NSThread: 0x7ff3735abe40>{number = 2, name = (null)}
2015-09-03 16:50:50.654 CYLDispatchSourceTest[8331:874681] 进度：0.97
2015-09-03 16:50:50.654 CYLDispatchSourceTest[8331:874681] 🔵线程号：<NSThread: 0x7ff373428140>{number = 1, name = main}
2015-09-03 16:50:50.654 CYLDispatchSourceTest[8331:874889] ♻️线程号：<NSThread: 0x7ff3735abe40>{number = 2, name = (null)}
2015-09-03 16:50:50.676 CYLDispatchSourceTest[8331:874681] 进度：0.98
2015-09-03 16:50:50.676 CYLDispatchSourceTest[8331:874681] 🔵线程号：<NSThread: 0x7ff373428140>{number = 1, name = main}
2015-09-03 16:50:50.676 CYLDispatchSourceTest[8331:874889] ♻️线程号：<NSThread: 0x7ff3735abe40>{number = 2, name = (null)}
2015-09-03 16:50:50.699 CYLDispatchSourceTest[8331:874889] ♻️线程号：<NSThread: 0x7ff3735abe40>{number = 2, name = (null)}
2015-09-03 16:50:50.708 CYLDispatchSourceTest[8331:874681] 进度：0.99
2015-09-03 16:50:50.708 CYLDispatchSourceTest[8331:874681] 🔵线程号：<NSThread: 0x7ff373428140>{number = 1, name = main}
2015-09-03 16:50:50.722 CYLDispatchSourceTest[8331:874681] 进度：1
2015-09-03 16:50:50.722 CYLDispatchSourceTest[8331:874681] 🔵线程号：<NSThread: 0x7ff373428140>{number = 1, name = main}
2015-09-03 16:50:50.722 CYLDispatchSourceTest[8331:874889] ♻️线程号：<NSThread: 0x7ff3735abe40>{number = 2, name = (null)}
 ```


耗时：2.376

这段代码还可以进行如下优化：

将创建异步的操作放在 for 循环内部：

 ```Objective-C
- (void)viewDidLoad {
    [super viewDidLoad];
    //1.
    // 指定DISPATCH_SOURCE_TYPE_DATA_ADD，做成Dispatch Source(分派源)。设定Main Dispatch Queue 为追加处理的Dispatch Queue
    _processingQueueSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_DATA_ADD, 0, 0,
                                                      dispatch_get_main_queue());
    __block NSUInteger totalComplete = 0;
    dispatch_source_set_event_handler(_processingQueueSource, ^{
        //当处理事件被最终执行时，计算后的数据可以通过dispatch_source_get_data来获取。这个数据的值在每次响应事件执行后会被重置，所以totalComplete的值是最终累积的值。
        NSUInteger value = dispatch_source_get_data(_processingQueueSource);
        totalComplete += value;
        NSLog(@"进度：%@", @((CGFloat)totalComplete/100));
        NSLog(@"🔵线程号：%@", [NSThread currentThread]);

    });
    //分派源创建时默认处于暂停状态，在分派源分派处理程序之前必须先恢复。
    [self resume];
    
    //2.
    //恢复源后，就可以通过dispatch_source_merge_data向Dispatch Source(分派源)发送事件:
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
        for (NSUInteger index = 0; index < 100; index++) {
            dispatch_async(queue, ^{
            dispatch_source_merge_data(_processingQueueSource, 1);
            NSLog(@"♻️线程号：%@", [NSThread currentThread]);
            usleep(20000);//0.02秒
            });
        }
}
 ```

执行结果：

 ```Objective-C
2015-09-03 16:48:10.153 CYLDispatchSourceTest[8301:871133] ✅恢复Dispatch Source(分派源)
2015-09-03 16:48:10.154 CYLDispatchSourceTest[8301:871174] ♻️线程号：<NSThread: 0x7fb663616c50>{number = 2, name = (null)}
2015-09-03 16:48:10.156 CYLDispatchSourceTest[8301:871177] ♻️线程号：<NSThread: 0x7fb663417370>{number = 4, name = (null)}
2015-09-03 16:48:10.156 CYLDispatchSourceTest[8301:871176] ♻️线程号：<NSThread: 0x7fb66359ac80>{number = 3, name = (null)}
2015-09-03 16:48:10.163 CYLDispatchSourceTest[8301:871184] ♻️线程号：<NSThread: 0x7fb6635507b0>{number = 5, name = (null)}
2015-09-03 16:48:10.164 CYLDispatchSourceTest[8301:871185] ♻️线程号：<NSThread: 0x7fb663618c90>{number = 6, name = (null)}
2015-09-03 16:48:10.164 CYLDispatchSourceTest[8301:871186] ♻️线程号：<NSThread: 0x7fb663596920>{number = 7, name = (null)}
2015-09-03 16:48:10.174 CYLDispatchSourceTest[8301:871187] ♻️线程号：<NSThread: 0x7fb663465d20>{number = 8, name = (null)}
2015-09-03 16:48:10.174 CYLDispatchSourceTest[8301:871175] ♻️线程号：<NSThread: 0x7fb6634404f0>{number = 9, name = (null)}
2015-09-03 16:48:10.182 CYLDispatchSourceTest[8301:871133] 进度：0.09
2015-09-03 16:48:10.174 CYLDispatchSourceTest[8301:871174] ♻️线程号：<NSThread: 0x7fb663616c50>{number = 2, name = (null)}
2015-09-03 16:48:10.187 CYLDispatchSourceTest[8301:871133] 🔵线程号：<NSThread: 0x7fb6634077a0>{number = 1, name = main}
2015-09-03 16:48:10.184 CYLDispatchSourceTest[8301:871188] ♻️线程号：<NSThread: 0x7fb66348e850>{number = 10, name = (null)}
2015-09-03 16:48:10.184 CYLDispatchSourceTest[8301:871177] ♻️线程号：<NSThread: 0x7fb663417370>{number = 4, name = (null)}
2015-09-03 16:48:10.191 CYLDispatchSourceTest[8301:871133] 进度：0.13
2015-09-03 16:48:10.187 CYLDispatchSourceTest[8301:871192] ♻️线程号：<NSThread: 0x7fb66348db80>{number = 11, name = (null)}
2015-09-03 16:48:10.191 CYLDispatchSourceTest[8301:871189] ♻️线程号：<NSThread: 0x7fb6635121b0>{number = 12, name = (null)}
2015-09-03 16:48:10.191 CYLDispatchSourceTest[8301:871176] ♻️线程号：<NSThread: 0x7fb66359ac80>{number = 3, name = (null)}
2015-09-03 16:48:10.196 CYLDispatchSourceTest[8301:871133] 🔵线程号：<NSThread: 0x7fb6634077a0>{number = 1, name = main}
2015-09-03 16:48:10.192 CYLDispatchSourceTest[8301:871184] ♻️线程号：<NSThread: 0x7fb6635507b0>{number = 5, name = (null)}
2015-09-03 16:48:10.192 CYLDispatchSourceTest[8301:871185] ♻️线程号：<NSThread: 0x7fb663618c90>{number = 6, name = (null)}
2015-09-03 16:48:10.192 CYLDispatchSourceTest[8301:871186] ♻️线程号：<NSThread: 0x7fb663596920>{number = 7, name = (null)}
2015-09-03 16:48:10.194 CYLDispatchSourceTest[8301:871190] ♻️线程号：<NSThread: 0x7fb6635138b0>{number = 13, name = (null)}
2015-09-03 16:48:10.196 CYLDispatchSourceTest[8301:871187] ♻️线程号：<NSThread: 0x7fb663465d20>{number = 8, name = (null)}
2015-09-03 16:48:10.196 CYLDispatchSourceTest[8301:871175] ♻️线程号：<NSThread: 0x7fb6634404f0>{number = 9, name = (null)}
2015-09-03 16:48:10.206 CYLDispatchSourceTest[8301:871133] 进度：0.21
2015-09-03 16:48:10.207 CYLDispatchSourceTest[8301:871133] 🔵线程号：<NSThread: 0x7fb6634077a0>{number = 1, name = main}
2015-09-03 16:48:10.210 CYLDispatchSourceTest[8301:871133] 进度：0.23
2015-09-03 16:48:10.201 CYLDispatchSourceTest[8301:871193] ♻️线程号：<NSThread: 0x7fb663487830>{number = 14, name = (null)}
2015-09-03 16:48:10.207 CYLDispatchSourceTest[8301:871194] ♻️线程号：<NSThread: 0x7fb6634662c0>{number = 15, name = (null)}
2015-09-03 16:48:10.207 CYLDispatchSourceTest[8301:871195] ♻️线程号：<NSThread: 0x7fb663618160>{number = 16, name = (null)}
2015-09-03 16:48:10.211 CYLDispatchSourceTest[8301:871133] 🔵线程号：<NSThread: 0x7fb6634077a0>{number = 1, name = main}
2015-09-03 16:48:10.210 CYLDispatchSourceTest[8301:871196] ♻️线程号：<NSThread: 0x7fb663566720>{number = 17, name = (null)}
2015-09-03 16:48:10.211 CYLDispatchSourceTest[8301:871174] ♻️线程号：<NSThread: 0x7fb663616c50>{number = 2, name = (null)}
/*＝＝＝＝＝＝＝＝＝＝省略20行带有的 ♻️的打印内容（没有重复的线程号）＝＝＝＝＝＝＝＝*/
2015-09-03 16:48:10.239 CYLDispatchSourceTest[8301:871196] ♻️线程号：<NSThread: 0x7fb663566720>{number = 17, name = (null)}
2015-09-03 16:48:10.239 CYLDispatchSourceTest[8301:871174] ♻️线程号：<NSThread: 0x7fb663616c50>{number = 2, name = (null)}
2015-09-03 16:48:10.239 CYLDispatchSourceTest[8301:871191] ♻️线程号：<NSThread: 0x7fb663597ca0>{number = 18, name = (null)}
2015-09-03 16:48:10.245 CYLDispatchSourceTest[8301:871202] ♻️线程号：<NSThread: 0x7fb663617c00>{number = 24, name = (null)}
2015-09-03 16:48:10.247 CYLDispatchSourceTest[8301:871133] 🔵线程号：<NSThread: 0x7fb6634077a0>{number = 1, name = main}
2015-09-03 16:48:10.249 CYLDispatchSourceTest[8301:871133] 进度：0.5
2015-09-03 16:48:10.249 CYLDispatchSourceTest[8301:871133] 🔵线程号：<NSThread: 0x7fb6634077a0>{number = 1, name = main}
2015-09-03 16:48:10.248 CYLDispatchSourceTest[8301:871203] ♻️线程号：<NSThread: 0x7fb663531ab0>{number = 25, name = (null)}
2015-09-03 16:48:10.249 CYLDispatchSourceTest[8301:871133] 进度：0.51
2015-09-03 16:48:10.249 CYLDispatchSourceTest[8301:871133] 🔵线程号：<NSThread: 0x7fb6634077a0>{number = 1, name = main}
2015-09-03 16:48:10.250 CYLDispatchSourceTest[8301:871204] ♻️线程号：<NSThread: 0x7fb66344bbf0>{number = 26, name = (null)}
2015-09-03 16:48:10.250 CYLDispatchSourceTest[8301:871133] 进度：0.52
2015-09-03 16:48:10.251 CYLDispatchSourceTest[8301:871133] 🔵线程号：<NSThread: 0x7fb6634077a0>{number = 1, name = main}
2015-09-03 16:48:10.251 CYLDispatchSourceTest[8301:871133] 进度：0.53
2015-09-03 16:48:10.250 CYLDispatchSourceTest[8301:871205] ♻️线程号：<NSThread: 0x7fb663461d90>{number = 27, name = (null)}
2015-09-03 16:48:10.251 CYLDispatchSourceTest[8301:871206] ♻️线程号：<NSThread: 0x7fb66341d370>{number = 28, name = (null)}
2015-09-03 16:48:10.252 CYLDispatchSourceTest[8301:871133] 🔵线程号：<NSThread: 0x7fb6634077a0>{number = 1, name = main}
2015-09-03 16:48:10.252 CYLDispatchSourceTest[8301:871133] 进度：0.54
2015-09-03 16:48:10.251 CYLDispatchSourceTest[8301:871207] ♻️线程号：<NSThread: 0x7fb6634196e0>{number = 29, name = (null)}
2015-09-03 16:48:10.253 CYLDispatchSourceTest[8301:871133] 🔵线程号：<NSThread: 0x7fb6634077a0>{number = 1, name = main}
2015-09-03 16:48:10.254 CYLDispatchSourceTest[8301:871133] 进度：0.57
2015-09-03 16:48:10.254 CYLDispatchSourceTest[8301:871133] 🔵线程号：<NSThread: 0x7fb6634077a0>{number = 1, name = main}
2015-09-03 16:48:10.255 CYLDispatchSourceTest[8301:871133] 进度：0.58
2015-09-03 16:48:10.252 CYLDispatchSourceTest[8301:871208] ♻️线程号：<NSThread: 0x7fb66341bd50>{number = 30, name = (null)}
2015-09-03 16:48:10.253 CYLDispatchSourceTest[8301:871209] ♻️线程号：<NSThread: 0x7fb66361a070>{number = 31, name = (null)}
2015-09-03 16:48:10.253 CYLDispatchSourceTest[8301:871210] ♻️线程号：<NSThread: 0x7fb663618020>{number = 32, name = (null)}
2015-09-03 16:48:10.255 CYLDispatchSourceTest[8301:871133] 🔵线程号：<NSThread: 0x7fb6634077a0>{number = 1, name = main}
2015-09-03 16:48:10.255 CYLDispatchSourceTest[8301:871211] ♻️线程号：<NSThread: 0x7fb663612c90>{number = 33, name = (null)}
2015-09-03 16:48:10.256 CYLDispatchSourceTest[8301:871133] 进度：0.59
2015-09-03 16:48:10.257 CYLDispatchSourceTest[8301:871133] 🔵线程号：<NSThread: 0x7fb6634077a0>{number = 1, name = main}
2015-09-03 16:48:10.256 CYLDispatchSourceTest[8301:871212] ♻️线程号：<NSThread: 0x7fb6635996d0>{number = 34, name = (null)}
2015-09-03 16:48:10.259 CYLDispatchSourceTest[8301:871133] 进度：0.6
2015-09-03 16:48:10.259 CYLDispatchSourceTest[8301:871133] 🔵线程号：<NSThread: 0x7fb6634077a0>{number = 1, name = main}
2015-09-03 16:48:10.259 CYLDispatchSourceTest[8301:871213] ♻️线程号：<NSThread: 0x7fb66340bd30>{number = 35, name = (null)}
2015-09-03 16:48:10.260 CYLDispatchSourceTest[8301:871133] 进度：0.61
2015-09-03 16:48:10.264 CYLDispatchSourceTest[8301:871133] 🔵线程号：<NSThread: 0x7fb6634077a0>{number = 1, name = main}
2015-09-03 16:48:10.262 CYLDispatchSourceTest[8301:871214] ♻️线程号：<NSThread: 0x7fb66354f4b0>{number = 36, name = (null)}
2015-09-03 16:48:10.264 CYLDispatchSourceTest[8301:871133] 进度：0.62
2015-09-03 16:48:10.264 CYLDispatchSourceTest[8301:871133] 🔵线程号：<NSThread: 0x7fb6634077a0>{number = 1, name = main}
2015-09-03 16:48:10.264 CYLDispatchSourceTest[8301:871215] ♻️线程号：<NSThread: 0x7fb663531010>{number = 37, name = (null)}
2015-09-03 16:48:10.270 CYLDispatchSourceTest[8301:871133] 进度：0.63
2015-09-03 16:48:10.270 CYLDispatchSourceTest[8301:871216] ♻️线程号：<NSThread: 0x7fb66360c6e0>{number = 38, name = (null)}
2015-09-03 16:48:10.270 CYLDispatchSourceTest[8301:871133] 🔵线程号：<NSThread: 0x7fb6634077a0>{number = 1, name = main}
2015-09-03 16:48:10.270 CYLDispatchSourceTest[8301:871176] ♻️线程号：<NSThread: 0x7fb66359ac80>{number = 3, name = (null)}
2015-09-03 16:48:10.270 CYLDispatchSourceTest[8301:871133] 进度：0.64
2015-09-03 16:48:10.271 CYLDispatchSourceTest[8301:871198] ♻️线程号：<NSThread: 0x7fb663576ab0>{number = 20, name = (null)}
2015-09-03 16:48:10.271 CYLDispatchSourceTest[8301:871133] 🔵线程号：<NSThread: 0x7fb6634077a0>{number = 1, name = main}
2015-09-03 16:48:10.271 CYLDispatchSourceTest[8301:871189] ♻️线程号：<NSThread: 0x7fb6635121b0>{number = 12, name = (null)}
2015-09-03 16:48:10.271 CYLDispatchSourceTest[8301:871188] ♻️线程号：<NSThread: 0x7fb66348e850>{number = 10, name = (null)}
2015-09-03 16:48:10.271 CYLDispatchSourceTest[8301:871192] ♻️线程号：<NSThread: 0x7fb66348db80>{number = 11, name = (null)}
/*＝＝＝＝＝＝＝＝＝＝省略30行带有的 ♻️的打印内容（没有重复的线程号）＝＝＝＝＝＝＝＝*/
2015-09-03 16:48:10.277 CYLDispatchSourceTest[8301:871222] ♻️线程号：<NSThread: 0x7fb66361ca00>{number = 43, name = (null)}
2015-09-03 16:48:10.278 CYLDispatchSourceTest[8301:871223] ♻️线程号：<NSThread: 0x7fb66360c620>{number = 44, name = (null)}
2015-09-03 16:48:10.290 CYLDispatchSourceTest[8301:871133] 🔵线程号：<NSThread: 0x7fb6634077a0>{number = 1, name = main}
2015-09-03 16:48:10.293 CYLDispatchSourceTest[8301:871133] 进度：1
2015-09-03 16:48:10.293 CYLDispatchSourceTest[8301:871133] 🔵线程号：<NSThread: 0x7fb6634077a0>{number = 1, name = main}

 ```

耗时：0.14秒，与之前的2.376秒相比，时间是后者的17倍 ，性能相差很大。

###  DispatchSource能通过合并事件的方式确保在高负载下正常工作

然而上例中也因为并发执行，速度相当快，调用 `dispatch_source_merge_data` 后所触发的 `dispatch_source_set_event_handler` 的频率也大大减少，有时只会在结束时触发一次。

如果你细心观察下上例中的打印🔵（小蓝点）♻️（小绿点）个数是不一的，但 `totalComplete` 的值，或者进度条从0.0到1.0的执行是正常，但是🔵（小蓝点）为什么没有被打印？这是因为：

 > DispatchSource能通过合并事件的方式确保在高负载下正常工作

在同一时间，只有一个处理 block 的实例被分配，如果这个处理方法还没有执行完毕，另一个事件就发生了，事件会以指定方式（ADD或 OR）进行累积。DispatchSource能通过合并事件（block）的方式确保在高负载下正常工作。当处理事件被最终执行时，计算后的数据可以通过 `dispatch_source_get_data` 来获取。这个数据的值在每次响应时间执行后会被重置，所以上面的例子中进度条 `totalComplete` 的值是最终积累的值，而 block 不是每次都执行的，但打印🔵（小蓝点）♻️（小绿点）个数不一。但能确保进度条能从0.0到1.0的正常执行。



下面我们来演示下如何控制Dispatch Source(分派源)，让它随时暂停，随时恢复：

 ```Objective-C
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    [self changeStatus:self.running];
}

- (void)changeStatus:(BOOL)shouldPause {
    if (shouldPause) {
        [self pause];
    } else {
        [self resume];
    }
}

- (void)resume {
    if (self.running) {
        return;
    }
    NSLog(@"✅恢复Dispatch Source(分派源)");
    self.running = YES;
    dispatch_resume(_processingQueueSource);
}

- (void)pause {
    if (!self.running) {
        return;
    }
    NSLog(@"🚫暂停Dispatch Source(分派源)");
    self.running = NO;
    dispatch_suspend(_processingQueueSource);
}
 ```

并取消打印线程的 `NSLog` ，然后使用下图中的快捷键迅速触发 `didReceiveMemoryWarning`  以切换Dispatch Source(分派源)的状态:

![enter image description here](http://i61.tinypic.com/6thjmf.jpg)


![enter image description here](http://i59.tinypic.com/suyt0o.jpg)

详见 `Demo1` 实现（Demo_01_对DispatchSource实现取消恢复操作_main队列版）。

### Dispatch Source 与 Dispatch Queue 两者在线程执行上的关系

本节配套代码在  `Demo2` 中（Demo_02_对DispatchSource实现取消恢复操作_global队列版）。

答案是：没有关系。两者会独立运行。 Dispatch Queue 像一个生产任务的生产者，而 Dispatch Source 像处理任务的消费者。可以一边异步生产，也可一边异步消费。你可以在任意线程上调用 `dispatch_source_merge_data` 以触发 `dispatch_source_set_event_handler` 。而句柄的执行线程，取决于你创建句柄时所指定的线程，如果你像下面这样创建，那么句柄会在主线程执行：


 ```Objective-C
    // 指定DISPATCH_SOURCE_TYPE_DATA_ADD，做成Dispatch Source(分派源)。设定Main Dispatch Queue 为追加处理的 Dispatch Queue
    _processingQueueSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_DATA_ADD, 0, 0,
                                                      dispatch_get_main_queue());
 ```

如果你像下面这样创建，那么句柄会在异步线程执行：

 ```Objective-C
    // 指定DISPATCH_SOURCE_TYPE_DATA_ADD，做成Dispatch Source(分派源)。设定 global Dispatch Queue 为追加处理的Dispatch Queue
    _processingQueueSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_DATA_ADD, 0, 0,
                                                    dispatch_get_global_queue(0, 0));
 ```

详见 `Demo2` 实现（Demo_02_对DispatchSource实现取消恢复操作_global队列版）

### 让 Dispatch Source 与 Dispatch Queue 同时实现暂停和恢复

本节代码详见 Demo4（Demo_04_对DispatchQueue实现取消恢复操作_综合版）

你可能已经发现了：上面的代码是有问题的，它只是一种“假暂停”的状态。for 循环还是要执行100遍，循环的次数并没有因你暂停了派发源而暂停，这在实际开发中是不允许的，因为真正的性能瓶颈永远会是在这里，这样的暂停毫无意义。那么如何让 for 循环随时可以暂停？

实际上 `Dispatch Queue` 没有“取消”这一概念。一旦将处理追加到 `Dispatch Queue` 中，就没有方法可将该处理去除，也没有方法可在执行中取消该处理。编程人员要么在处理中导入取消这一概念。

要么放弃取消，或者使用 `NSOperationQueue` 等其他方法。

 `Dispatch Source` 与 `Dispatch Queue` 不同，是可以取消的。而且取消时必须执行的处理可指定为回调用的Block形式。

 `Dispatch Source`  是如何执行取消的？打个比方：

 `Dispatch Queue` 就好像瓜农种瓜，只要种了瓜，就走上了一条不归路：不管有没有人买，你都必须要好好施肥，好好浇水。没有放弃的余地。

 `Dispatch Source` 就好像买瓜的人，比如你在瓜农种瓜时，告诉瓜农，“你的瓜熟一个我买一个”，等瓜成熟了，你开始买，不断得买，陆续买了100个，突然你感觉吃够了，你不买了，但是瓜还是在不断得成熟着，然后只能烂在地里了。等你突然又想买的时候，地里已经有1000个瓜，你要买，必须全买。。。

回到代码里，也就是说 `Dispatch Source` 的暂停，只是暂停调用 `dispatch_source_set_event_handler` ， `Dispatch Queue` 中的for循环并没有因此暂停，它还是在一直运行着，等你恢复 `Dispatch Source` 的时候， `Dispatch Queue` 可能已经运行结束。然后你就会像上面的gif图中那样，从“进度：0.9”暂停，恢复时直接跳到“进度：1”，跳过了中间的“进度：0.91”、“进度：0.92”、“进度：0.93”等等。所以说这是一种“假暂停”。

那么如何在处理中导入取消这一概念？代码如下：

 ```Objective-C
dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
__block BOOL isCanceled = NO;
dispatch_async(queue, ^{

    if (isCanceled) {
        return;
     }

    NSData *thumbnailData = [NSURLConnection sendSynchronousRequest:request];
    ...
});
 ```

完整的代码则需要做如下修改：

 ```Objective-C
- (void)viewDidLoad {
    [super viewDidLoad];
    //1.
    // 指定DISPATCH_SOURCE_TYPE_DATA_ADD，做成Dispatch Source(分派源)。设定Main Dispatch Queue 为追加处理的Dispatch Queue
    _processingQueueSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_DATA_ADD, 0, 0,
                                                    dispatch_get_main_queue());
    __block NSUInteger totalComplete = 0;
    dispatch_source_set_event_handler(_processingQueueSource, ^{
        //当处理事件被最终执行时，计算后的数据可以通过dispatch_source_get_data来获取。这个数据的值在每次响应事件执行后会被重置，所以totalComplete的值是最终累积的值。
        NSUInteger value = dispatch_source_get_data(_processingQueueSource);
        totalComplete += value;
        NSLog(@"进度：%@", @((CGFloat)totalComplete/CYLTotalNumber));
    });
    //分派源创建时默认处于暂停状态，在分派源分派处理程序之前必须先恢复。
    [self resume];
    
    
    //2.
    //恢复源后，就可以通过dispatch_source_merge_data向Dispatch Source(分派源)发送事件:
    //为了便于观察，将_queue做成“串行队列”
    _queue = dispatch_queue_create("com.ioschengxuyuan.queue1", 0);
    NSLog(@"🔴类名与方法名：%s（在第%d行），描述：%@", __PRETTY_FUNCTION__, __LINE__, @"启动队列");
    for (NSUInteger index = 0; index < CYLTotalNumber; index++) {
        dispatch_async(_queue, ^{
            if (!self.running) {
                return;
            }
            dispatch_source_merge_data(_processingQueueSource, 1);
            usleep(200000);//0.2秒
        });
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    [self changeStatus:self.running];
}

- (void)changeStatus:(BOOL)shouldPause {
    if (shouldPause) {
        [self pause];
    } else {
        [self resume];
    }
}

- (void)resume {
    if (self.running) {
        return;
    }
    NSLog(@"✅恢复Dispatch Source(分派源)以及_queue");
    self.running = YES;
    dispatch_resume(_processingQueueSource);
    if (_queue) {
        dispatch_resume(_queue);
    }
}

- (void)pause {
    if (!self.running) {
        return;
    }
    NSLog(@"🚫暂停Dispatch Source(分派源)以及_queue");
    self.running = NO;
    dispatch_suspend(_processingQueueSource);
    dispatch_suspend(_queue);
}
 ```

![enter image description here](http://i61.tinypic.com/33m06er.jpg)


详见 Demo4（Demo_04_对DispatchQueue实现取消恢复操作_综合版）


## Parse “离线存储对象”操作的代码摘录

句柄如下：

 ```Objective-C
    dispatch_source_set_event_handler(_processingQueueSource, ^{
        [self _runCommands];
    });
 ```

何时会调用句柄？ 下面将 Parse 里涉及调用句柄的语句罗列一下， 因为摘录的代码不完整，可能并不能看出使用的完整过程。所以可以大致预览一下，详情可以查看Parse 源码，并且我已将这些逻辑浓缩为可运行的 Demo，也可搭配理解。

 ```Objective-C
- (void)start {
    dispatch_source_set_event_handler(_processingQueueSource, ^{
        [self _runCommands];
    });
    [self resume];
}
 ```




 ```Objective-C
- (void)resume {
    if (self.running) {
        return;
    }
    self.running = YES;
    dispatch_resume(_processingQueueSource);
    dispatch_source_merge_data(_processingQueueSource, 1);
}
 ```

监听网络状态，一旦网络重连上之后，设置 connected属性为 YES，并重写其 setter 方法，调用 `dispatch_source_merge_data` 进行发送消息的操作：


 ```Objective-C
/*! Manually sets the network connection status. */
- (void)setConnected:(BOOL)connected {
    BFTaskCompletionSource *barrier = [BFTaskCompletionSource taskCompletionSource];
    dispatch_async(_processingQueue, ^{
        dispatch_sync(_synchronizationQueue, ^{
            if (self.connected != connected) {
                _connected = connected;
                if (connected) {
                    dispatch_source_merge_data(_processingQueueSource, 1);
                }
            }
        });
        barrier.result = nil;
    });
    if (connected) {
        dispatch_async(_synchronizationQueue, ^{
            if (_retryingSemaphore) {
                dispatch_semaphore_signal(_retryingSemaphore);
            }
        });
    }
    [barrier.task waitForResult:nil];
}

 ```


 ```Objective-C
- (void)_didEnqueueCommand:(id<PFNetworkCommand>)command
            withIdentifier:(NSString *)identifier
      taskCompletionSource:(BFTaskCompletionSource *)taskCompletionSource {
    PFAssertIsOnDispatchQueue(_synchronizationQueue);

    _taskCompletionSources[identifier] = taskCompletionSource;
    dispatch_source_merge_data(_processingQueueSource, 1);

    if (_retryingSemaphore) {
        dispatch_semaphore_signal(_retryingSemaphore);
    }
}

 ```


##  `Dispatch Semaphore` 信号量

为了展示作用，举个反例：

 ```Objective-C
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    NSMutableArray *array = [[NSMutableArray alloc] init];
    dispatch_group_t group = dispatch_group_create();
    for(int i = 0; i< 100000; ++i) {
        dispatch_group_async(group, queue, ^{
            [array addObject:[NSNumber numberWithInt:i]];
        });
    }
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    NSLog(@"%@",  @([array count]));
 ```

运行结果绝对大跌眼镜：

我运行了三次，三次结果均不一致：


 1. 第一次：崩溃。。。

 ![enter image description here](http://i67.tinypic.com/29vxt9w.jpg)


 ```Objective-C
CYLDispatchSemaphoreTest(10384,0x112d43000) malloc: *** error for object 0x7f898487ca00: pointer being freed was not allocated
*** set a breakpoint in malloc_error_break to debug
(lldb) 
 ```

 2. 第二次：不够。。

 ```Objective-C
2015-09-07 00:42:20.145 CYLDispatchSemaphoreTest[10417:779722] 99996
 ```

 2. 第三次：还是不够。。。


 ```Objective-C
2015-09-07 00:42:52.734 CYLDispatchSemaphoreTest[10438:780505] 99949
 ```

这种资源抢夺的情况，一般的做法是使用串行队列，或者像下面一样的同步队列，得以解决：

 ```Objective-C
 dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    NSMutableArray *array = [[NSMutableArray alloc] init];
    for(int i = 0; i< 100000; ++i) {
        dispatch_sync(queue, ^{
            [array addObject:[NSNumber numberWithInt:i]];
        });

    }
    NSLog(@"%@", @([array count]));
 ```

下面展示下展示使用 `dispatch_semaphore_t` 的解决方案：



 `dispatch_semaphore_t` 的作用之一就是解决这种资源抢夺的情况，下面展示下使用 `dispatch_semaphore_t` 实现一个资源锁：

以下源码详见 Demo6（Demo_06_展示dispatch_semaphore_t基本用法）


 ```Objective-C
- (void)viewDidLoad {
    [super viewDidLoad];
    //因为用到了dispatch_barrier_async，该函数只能搭配自定义并行队列dispatch_queue_t使用。所以不能使用：dispatch_get_global_queue
    dispatch_queue_t queue = dispatch_queue_create("com.ioschengxuyuan.gcd.ForBarrier", DISPATCH_QUEUE_CONCURRENT);
    /*
     *
     *生成Dispatch Semaphore
     Dispatch Semaphore 的计数初始值设定为“1”
     (该初始值的1与下文中两个函数dispatch_semaphore_wait与dispatch_semaphore_signal进行的减1、加1里的1没有必然联系。
     
     就算初始值是100，两个函数dispatch_semaphore_wait与dispatch_semaphore_signal还是会减“1”、加“1”)。
     保证可访问 NSMutableArray 类对象的线程
     同时只能有1个
     *
     */
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(1) ;
    NSMutableArray *array = [[NSMutableArray alloc] init];
    for(int i = 0; i< 100000; ++i) {
        dispatch_async(queue, ^{
            /*
             *
             *等待Dispatch Semaphore
             *一直等待，直到Dispatch Semaphore的计数值达到大于等于1
             */
            dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER) ;
            /*
             *由于Dispatch Semaphore的计数值达到大于等于1
             *所以将Dispatch Semaphore的计数值减去1
             *dispatch_semaphore_wait 函数执行返回。
             *即执行到此时的
             *Dispatch Semaphore 的计数值恒为0
             *
             *由于可访问NSMutaleArray类对象的线程
             *只有一个
             *因此可安全地进行更新
             *
             */
            NSLog(@"🔴%@",[NSThread currentThread]);
            [array addObject:[NSNumber numberWithInt:i]];
            /*
             *
             *排他控制处理结束，
             *所以通过dispatch_semaphore_signal函数
             *将Dispatch Semaphore的计数值加1
             *如果有通过dispatch_semaphore_wait函数
             *等待Dispatch Semaphore的计数值增加的线程，
             ★就由最先等待的线程执行。
             */
            dispatch_semaphore_signal(semaphore);
        });
    }
    /*
     *
     等为数组遍历添加元素后，检查下数组的成员个数是否正确
     *
     */
    dispatch_barrier_async(queue, ^{
        NSLog(@"🔴类名与方法名：%s（在第%d行），描述：%@", __PRETTY_FUNCTION__, __LINE__, @([array count]));
    });
}
 ```




为了加深对dispatch_semaphore_t基本用法的理解，再给一个示例 Demo：

思考下为何会如何打印：
然后再分别试一下第三行和第四行：


 ```Objective-C
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
//    dispatch_semaphore_t semaphore = dispatch_semaphore_create(1);
 ```

然后观察下打印。


详见 Demo5（Demo_05_展示dispatch_semaphore_t基本用法）

 ```Objective-C
- (void)viewDidLoad {
    [super viewDidLoad];
    
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
//    dispatch_semaphore_t semaphore = dispatch_semaphore_create(1);
    
    dispatch_time_t time = dispatch_time(DISPATCH_TIME_NOW, 1ull * NSEC_PER_SEC);//等待一秒
    //dispatch_time_t time = DISPATCH_TIME_FOREVER;//永久等待
    NSLog(@"begin ==>  车库开始营业了！");
    /*
     *
     如果 semphore 的值等于0，就阻塞1秒钟，才会往下照常进行；
     如果大于等于1则往下进行并将 semphore 进行减1处理。
     *
     */
    long result = dispatch_semaphore_wait(semaphore, time);
    if (result == 0) {
        /*
         *
         *由子Dispatch Semaphore的计数值达到大于等于1
         *或者在待机中的指定时间内
         *Dispatch Semaphore的计数值达到大于等于1
         所以Dispatch Semaphore的计数值减去1
         可执行需要进行排他控制的处理.
         可以理解为：没有阻塞的线程了。
         就好比：车库有一个或一个以上的车位，只来了一辆车，所以“无需等待”
         *
         */
        NSLog(@"result = 0 ==> 有车位，无需等待！==> 在这里可安全地执行【需要排他控制的处理（比如只允许一条线程为mutableArray进行addObj操作）】");
        dispatch_semaphore_signal(semaphore);//使用signal以确保编译器release掉dispatch_semaphore_t时的值与初始值一致， 否则会EXC_BAD_INSTRUCTION ,见http://is.gd/EaJgk5
    } else {
        /*
         *
         *由于Dispatch Semaphore的计数值为0
         .因此在达到指定时间为止待机
         这个else里发生的事情，就好比：车库没车位，来了一辆车，等待了半个小时后，做出的一些事情。
         比如：忍受不了，走了。。
         *
         */
        NSLog(@"result != 0 ==> timeout，deadline，忍受不了，走了。。");
        
    }
}
 ```


### 在项目中的应用：强制把异步任务转换为同步任务来方便进行单元测试

下面是 Parse 的一段代码：

```Objective-C
 @interface PFEventuallyQueueTestHelper : NSObject {
    dispatch_semaphore_t events[PFEventuallyQueueEventCount];
}

- (void)clear;
- (void)notify:(PFEventuallyQueueTestHelperEvent)event;
- (BOOL)waitFor:(PFEventuallyQueueTestHelperEvent)event;
```

注释是这样写的：


 > PFEventuallyQueueTestHelper gets notifications of various events happening in the command cache,
// so that tests can be synchronized. See CommandTests.m for examples of how to use this.

强制把异步任务转换为同步任务来方便进行单元测试。这个用途信号量是最合适的用途。但注意并不推荐应用到除此之外的其它场景！

这种异步转同步便于单元测试的用法类似于下面的写法：


 ```Objective-C
#define WAIT_FOREVER [self waitForStatus:XCTAsyncTestCaseStatusSucceeded timeout:DBL_MAX];
#define NOTIFY [self notify:XCTAsyncTestCaseStatusSucceeded];
 ```



 ```Objective-C
- (void)testInstallationMutated {
    NSDictionary *dict = [self jsonWithFileName:@"TestInstallationSave"];
    AVInstallation *installation = [AVInstallation currentInstallation];
    [installation objectFromDictionary:dict];
    [installation setObject:@(YES) forKey:@"enableNoDisturb"];
    [installation saveInBackgroundWithBlock:^(BOOL succeeded, NSError *error) {
        XCTAssertNil(error);
        NOTIFY;
    }];
    WAIT;
} 
 ```

信号量属性底层工具，他虽然非常强大，但在多数需要使用它的场合，最好从设计角度重新考虑，看是否可以不用，应该优先考虑使用诸如操作队列这样的高级工具。通常可以通过增加一个分派队列配合  `dispatch_suspend` ，或者通过其它方式分解操作来避免使用信号量。信号量并非不好，只是它本身是锁，能不使用就不用。尽量用 cocoa 框架中的高级抽象，信号量非常接近底层。所以除了上面的例子是最佳应用场景外，不推荐应用到除此之外的其它场景！


 [《关于dispatch_semaphore的使用》](http://www.cnblogs.com/snailHL/p/3906112.html) 中有这样的描述：

关于信号量，一般可以用停车来比喻。

>　　停车场剩余4个车位，那么即使同时来了四辆车也能停的下。如果此时来了五辆车，那么就有一辆需要等待。

>　　信号量的值就相当于剩余车位的数目，dispatch_semaphore_wait函数就相当于来了一辆车，

>　　dispatch_semaphore_signal，就相当于走了一辆车。停车位的剩余数目在初始化的时候就已经指明了（dispatch_semaphore_create（long value））

>　　调用一次dispatch_semaphore_signal，剩余的车位就增加一个；调用一次dispatch_semaphore_wait剩余车位就减少一个；

>　　当剩余车位为0时，再来车（即调用dispatch_semaphore_wait）就只能等待。有可能同时有几辆车等待一个停车位。有些车主

>　　没有耐心，给自己设定了一段等待时间，这段时间内等不到停车位就走了，如果等到了就开进去停车。而有些车主就像把车停在这，

>　　所以就一直等下去。

 [《GCD dispatch_semaphore 信号量 协调线程同步》](http://m.blog.csdn.net/blog/choudang/38121827) 也有类似的比喻：


 > 以一个停车场是运作为例。为了简单起见，假设停车场只有三个车位，一开始三个车位都是空的。这时如果同时来了五辆车，看门人允许其中三辆不受阻碍的进入，然后放下车拦，剩下的车则必须在入口等待，此后来的车也都不得不在入口处等待。这时，有一辆车离开停车场，看门人得知后，打开车拦，放入一辆，如果又离开两辆，则又可以放入两辆，如此往复。
</p> 在这个停车场系统中，车位是公共资源，每辆车好比一个线程，看门人起的就是信号量的作用。
更进一步，信号量的特性如下：信号量是一个非负整数（车位数），所有通过它的线程（车辆）都会将该整数减一（通过它当然是为了使用资源），当该整数值为零时，所有试图通过它的线程都将处于等待状态。在信号量上我们定义两种操作： Wait（等待） 和 Release（释放）。 当一个线程调用Wait（等待）操作时，它要么通过然后将信号量减一，要么一直等下去，直到信号量大于一或超时。Release（释放）实际上是在信号量上执行加操作，对应于车辆离开停车场，该操作之所以叫做“释放”是因为加操作实际上是释放了由信号量守护的资源。


这个比喻里可以用一个表格来表示：

喻体 | 本体 |  代码 |
-------------|-------------|-------------
车位 | 信号量 |  `dispatch_semaphore_t`  
剩余几个车位 | 最大并发线程 |  `dispatch_semaphore_t`  
看门人起的作用 | 信号量的作用 | `dispatch_semaphore_t`  
车 | 线程 | 代码 
耐心的极限时间 | 超时时间 |  `dispatch_semaphore_wait`  
逛街结束走了，离开车位 | signal+1 |  `dispatch_semaphore_signal`  


### 使用`Dispatch Semaphore`控制并发线程数量

正如文章开头所说：从 iOS7 升到 iOS8 后，GCD 出现了一个重大的变化：在 iOS7 时，使用 GCD 的并行队列，  `dispatch_async`  最大开启的线程一直能控制在6、7条，线程数都是个位数，然而 iOS8后，最大线程数一度可以达到40条、50条。然而在文档上并没有对这一做法的目的进行介绍。

笔者推测 Apple 的目的是想借此让开发者使用 `NSOperationQueue` ：GCD 中 Apple 并没有提供控制并发数量的接口，而  `NSOperationQueue`  有，如果需要使用 GCD 实现，需要使用 GCD 的一项高级功能：`Dispatch Semaphore`信号量。


详见 Demo7（Demo_07_展示dispatch_semaphore_t控制线程并发数量的用法）


Demo7中使用了 [这篇博文](http://mp.weixin.qq.com/s?__biz=MzAxNDAzMzk0MQ==&amp;mid=203702345&amp;idx=1&amp;sn=226f6f784d37b89718f6949c9214e1e6&amp;scene=1&amp;srcid=kl2ZmcSfYHuB6bMvYPEq#rd) 中的例子。


`Dispatch Semaphore`信号量的使用在上文中已经介绍过，那么就直接上 Demo：

主要做的就是将上文中 `dispatch_semaphore_t` 的个数设置为一个可变参数：这样就达到了控制并行线程数量的目的：

 ```Objective-C
/*
 *
 简单版本：无专门控制并发等待的线程，缺点阻塞主线程，可以跑一下 demo，你会发现主屏幕上的按钮是不可点击的
 *
 */
void dispatch_async_limit(dispatch_queue_t queue,NSUInteger limitSemaphoreCount, dispatch_block_t block) {
    //控制并发数的信号量
    static dispatch_semaphore_t limitSemaphore;
    //专门控制并发等待的线程

    
    //使用 dispatch_once而非 lazy 模式，防止可能的多线程抢占问题
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        limitSemaphore = dispatch_semaphore_create(limitSemaphoreCount);
    });
    

        //可用信号量后才能继续，否则等待
        dispatch_semaphore_wait(limitSemaphore, DISPATCH_TIME_FOREVER);
        dispatch_async(queue, ^{
            !block ? : block();
            //在该工作线程执行完成后释放信号量
            dispatch_semaphore_signal(limitSemaphore);
        });

}
 ```

你可能发现，这段代码有问题阻塞了当前线程，Demo7中也给出了改良版，可以看下。

### 为  NSURLSession 添加同步方法

NSURLSession 取消了同步方法，但是可以借助信号量来实现：

 ```Objective-C
+ (NSData *)sendSynchronousRequest:(NSURLRequest *)request returningResponse:(NSURLResponse *__autoreleasing *)response error:(NSError *__autoreleasing *)error {
    __block NSData *data = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *taskData, NSURLResponse *taskResponse, NSError *taskError) {
        data = taskData;

        if (response)
            *response = taskResponse;

        if (error)
            *error = taskError;

        dispatch_semaphore_signal(semaphore);
    }] resume];

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

    return data;
}
 ```

但是也要思考下为什么 Apple 取消了同步方法：同步方法的风险远远超过受益。

要注意：

 - 除非万不得已，否则永远不要尝试在主线程上发送同步的网络请求
 - 尽量只在后台线程中独占线程发送同步的网络请求



风险如下所示：


#### 导致Watchdog超时

关于Watchdog超时：

在  [ ***QA1693：Synchronous Networking On The Main Thread*** ]( https://developer.apple.com/library/ios/qa/qa1693/_index.html ) 
文档中描述了Watchdog机制，包括生效场景和表现。如果我们的应用程序对一些特定的UI事件（比如启动、挂起、恢复、结束）响应不及时，Watchdog会把我们的应用程序干掉，并生成一份响应的crash报告。

这份crash报告的有趣之处在于异常代码：“0x8badf00d”，即“ate bad food”。
如果说特定的UI事件比较抽象，那么用代码来直接描述的话，对应的就是（创建一个工程时Xcode自动生成的）UIApplicationDelegate的几个方法：

 ```Objective-C
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application {
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application {
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}
 ```

所以当遇到Watchdog日志时，可以检查下上面几个方法是否有比较重的阻塞UI的动作。

[ ***QA1693：Synchronous Networking On The Main Thread*** ]( https://developer.apple.com/library/ios/qa/qa1693/_index.html ) 举的例子就是在主线程进行同步网络请求。如果我们是在公司的Wifi环境下使用则一切顺利，但当应用程序发布出去面向很大范围的用户，在各种网络环境下运行，则不可避免地会出现一片Watchdog超时报告。
另一种可能出现问题的场景就是数据量比较大的情况下进行的数据库版本迁移（同样是在主线程上）。


#### 失去了 cancel 的机会：

不能像异步那样进行下面的操作：

 ```Objective-C
-(IBAction)cancelUpload:(id)sender {
    if (_uploadTask.state == NSURLSessionTaskStateRunning) {
        [_uploadTask cancel];
    }
}
 ```



 [《iOS应用的crash日志的分析基础》]( http://blog.csdn.net/jasonblog/article/details/19031517 ) 

参考链接： [GitHub:Parse-SDK-iOS-OSX源码](https://github.com/ParsePlatform/Parse-SDK-iOS-OSX) 

----------


Posted by [微博@iOS程序犭袁](http://weibo.com/luohanchenyilong/)  
原创文章，版权声明：自由转载-非商用-非衍生-保持署名 | [Creative Commons BY-NC-ND 3.0](http://creativecommons.org/licenses/by-nc-nd/3.0/deed.zh)

