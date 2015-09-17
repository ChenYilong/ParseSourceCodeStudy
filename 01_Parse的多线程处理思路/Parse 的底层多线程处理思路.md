#Facebook 出品的 Parse 其 iOS SDK 的底层多线程处理思路

#《Parse源码浅析系列（一）-Parse的底层多线程处理思路》

#《Parse源码浅析系列（一）---Parse的底层多线程处理思路：GCD高级用法》
目的是通过源码来展示GCD高级用法。将思路浓缩为5个左右的Demo。


《Parse iOS SDK 源码学习系列》之底层多线程处理思路


 [《iOS开发周报：iOS 8.4.1 发布，iOS 8 时代谢幕》](http://www.infoq.com/cn/news/2015/08/ios-weekly-ios841#rd) 有这样一段介绍：

 > Parse-SDK-iOS-OSX：著名的 BaaS 公司 Parse 最近开源了它们的 iOS/OSX SDK。Parse 的服务虽然在国内可能访问速度不是很理想，但是它们在服务的稳定性和 SDK 质量上一直有非常优异的表现。此次开源的 SDK 对于日常工作是 SDK 开发的开发者来说，是一个难得的学习机会。Parse 的存取操作涉及到很多多线程的问题，从 Parse SDK 的源代码中可以看出，这个 SDK 的开发者对 iOS 开发多线程有着非常深厚的理解和功底，让人叹服。我个人推荐对此感兴趣的朋友可以尝试从阅读 internal 文件夹下的两个EventuallyQueue 文件开始着手，研究下 Parse 的底层多线程处理思路。

类似的服务：
 [《Cloud​Kit》](http://nshipster.cn/cloudkit/) 

Apple 的 CloudKit、Facebook 的 Parse、中国的 LeanCloud （原名 AVOS）


使用的dispatch source而不使用dispatch_async的唯一原因就是利用联结的优势。

调用 `dispatch_source_merge_data(_processingQueueSource, 1);`  后，会执行句柄，

这个过程叫 `Custom event` ,用户事件。是 dispatch source 支持处理的一种事件。


 > 简单地说，这种事件是由你调用dispatch_source_merge_data函数来向自己发出的信号。



句柄如下：

 ```Objective-C
    dispatch_source_set_event_handler(_processingQueueSource, ^{
        [self _runCommands];
    });
 ```
何时会调用句柄？

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
#GCD真的不能像OperationQueue那样终止任务？




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

耗时：0.14，与之前的2.376相比，时间是后者的6% 。然而也因为并发执行，速度相当快，触发 `dispatch_source_set_event_handler` 的频率也大大减少，有时只会在结束时触发一次。


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

你可能已经发现了：上面的代码是有问题的，它只是一种“假暂停”的状态。

实际上 `Dispatch Queue` 没有“取消”这一概念。一旦将处理追加到 `Dispatch Queue` 中，就没有方法可将该处理去除，也没有方法可在执行中取消该处理。编程人员要么在处理中导入取消这一概念，像下面这样：

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



要么放弃取消，或者使用 `NSOperationQueue` 等其他方法。


 `Dispatch Source` 与 `Dispatch Queue` 不同，是可以取消的。而且取消时必须执行的处理可指定为回调用的Block形式。

 `Dispatch Source`  是如何执行取消的？打个比方：

 `Dispatch Queue` 就好像瓜农种瓜，只要种了瓜，就走上了一条不归路：不管有没有人买，你都必须要好好施肥，好好浇水。没有放弃的余地。

 `Dispatch Source` 就好像买瓜的人，比如你在瓜农种瓜时，告诉瓜农，“你的瓜熟一个我买一个”，等瓜成熟了，你开始买，不断得买，陆续买了100个，突然你感觉吃够了，你不买了，但是瓜还是在不断得成熟着，然后只能烂在地里了。等你突然又想买的时候，地里已经有1000个瓜，你要买，必须全买。。。

回到代码里，也就是说 `Dispatch Source` 的暂停，只是暂停调用 `dispatch_source_set_event_handler` ， `Dispatch Queue` 中的for循环并没有因此暂停，它还是在一直运行着，等你恢复 `Dispatch Source` 的时候， `Dispatch Queue` 可能已经运行结束。然后你就会像上面的gif图中那样，从“进度：0.9”暂停，恢复时直接跳到“进度：1”，跳过了中间的“进度：0.91”、“进度：0.92”、“进度：0.93”等等。


所以说这是一种“假暂停”，所以一般开发中也不会把 `Dispatch Queue` 做成Dispatch Source(分派源)。而是其他可以手动取消的。

代码则需要做如下修改：

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


当追加大量处理到Dispatch Queue时，在追加处理的过程中，有时希望不执行已追加的处理。例如演算结果被Block截获时，一些处理会对这个演算结果造成影响。

在这种情况下，只要挂起Dispatch Queue即可。当可以执行时再恢复。

 ```Objective-C
dispatch_suspend(queue);
 ```

 `dispatch_resume` 函数恢复指定的 `Dispatch Queue` .
这些函数对已经执行的处理没有影响。挂起后，追加到 `Dispatch Queue` 中但尚未执行的处理在此之后停止执行。而恢复则使得这些处理能够继续执行。


分派源提供了高效的方式来处理事件。首先注册事件处理程序，事件发生时会收到通知。如果在系统还没有来得及通知你之前事件就发生了多次，那么这些事件会被合并为一个事件。这对于底层的高性能代码很有用，但是OS应用开发者很少会用到这样的功能。类似地，分派源可以响应UNIX信号、文件系统的变化、其他进程的变化以及Mach Port事件。它们中很多都在Mac系统上很有用，但是OS开发者通常不会用到。

不过，自定义源在iOS中很有用，尤其是在性能至关重要的场合进行进度反馈。如下所示，首先创建一个源:自定义源累积事件中传递过来的值。累积方式可以是相加( DISPATCH_SOURCE_TYPE_DATA_ADD ),
也可以是逻辑或( DISPATCH_SOURCE_DATA_OR )。自定义源也需要一个队列，用来处理所有的响应处理块。

创建源后，需要提供相应的处理方法。当源生效时会分派注册处理方法;当事件发生时会分派事件处理方法;当源被取消时会分派取消处理方法。自定义源通常只需要一个事件处理方法，可以像这样创建:


在同一时间，只有一个处理方法块的实例被分派。如果这个处理方法还没有执行完毕，另一个事件就发生了，事件会以指定方式(ADD或者OR)进行累积。通过合并事件的方式，系统即使在高负
载情况下也能正常工作。当处理事件件被最终执行时，计算后的数据可以通过 `dispatch_source_get_data` 来获取。这个数据的值在每次响应事件执行后会被重置，所以上面例子中 `totalComplete` 的值是最终累积的值。

分派源创建时默认处于暂停状态，在分派源分派处理程序之前必须先恢复。因为忘记恢复分派源的状态而产生bug是常见的事儿。恢复的方法是调用 `dispatch_resume` :

 ```Objective-C
dispatch_resume (source);
 ```

恢复源后，就可以像下面的代码片段这样，通过 `dispatch_source_merge_data` 向分派源发送事件:

上面代码在每次循环中执行加1操作。也可以传递已处理记录的数目或已写入的字节数。在任何线程中都可以调用  `dispatch_source_merge_data` 。需要注意的是，不可以传递0值(事件不会被触发)，同样也不可以传递负数。



GCD中除了主要的 `Dispatch Queue` 外，还有不太引人注目的Dispatch Sowce `Dispatch Sowce` .它是BSD系内核惯有功能kqueue的包装。
kqueue是在XNU内核中发生各种事件时，在应用程序编程方执行处理的技术。其CPU负荷非常小，尽量不占用资源。kqueue可以说是应用程序处理XNU内核中发生的各种事件的方法中最优秀的一种。
 `Dispatch Source` 可处理以下事件。如下表所示：

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


上面源代码非常相似的代码，使用在了Core Foundation框架的用于异步网络的API  `CFSocket` 中。因为Foundation框架的异步网络API是通过CFSocket实现的，所以可享受到仅使用Foundation框架的 `Dispatch Source`  (即GCD)带来的好处。


展示作用


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
 ![enter image description here](http://image17-c.poco.cn/mypoco/myphoto/20150907/00/17338872420150907004449062.png?877x116_130
)


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



 ```Objective-C
 dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(1) ;
    NSMutableArray *array = [[NSMutableArray alloc] init];
    for(int i = 0; i< 100000; ++i) {
        dispatch_sync(queue, ^{
            [array addObject:[NSNumber numberWithInt:i]];
        });

    }
    NSLog(@"%@", @([array count]));
 ```


##在项目中的应用：强制让单元测试能同步进行

```Objective-C
 @interface PFEventuallyQueueTestHelper : NSObject {
    dispatch_semaphore_t events[PFEventuallyQueueEventCount];
}

- (void)clear;
- (void)notify:(PFEventuallyQueueTestHelperEvent)event;
- (BOOL)waitFor:(PFEventuallyQueueTestHelperEvent)event;
```



 > PFEventuallyQueueTestHelper gets notifications of various events happening in the command cache,
// so that tests can be synchronized. See CommandTests.m for examples of how to use this.

#Command处理思路


 ```Objective-C
//PFURLSessionCommandRunner.m
 - (BFTask *)runCommandAsync:(PFRESTCommand *)command withOptions:(PFCommandRunningOptions)options {
    return [self runCommandAsync:command withOptions:options cancellationToken:nil];
}

- (BFTask *)runCommandAsync:(PFRESTCommand *)command
                withOptions:(PFCommandRunningOptions)options
          cancellationToken:(BFCancellationToken *)cancellationToken {
    return [self _performCommandRunningBlock:^id{
        [command resolveLocalIds];
        NSURLRequest *request = [self.requestConstructor dataURLRequestForCommand:command];
        return [_session performDataURLRequestAsync:request forCommand:command cancellationToken:cancellationToken];
    } withOptions:options cancellationToken:cancellationToken];
}
 ```
semaphore的做法就好像做出租车

你进去后，空车标志落下，别人不能上车，等你下车后，司机把空车标志竖起来，别人才可以上车。要不然即使你坐上了车也会有人跟你抢座位。

 [《关于dispatch_semaphore的使用》](http://www.cnblogs.com/snailHL/p/3906112.html) 中有这样的描述：

关于信号量，一般可以用停车来比喻。

>　　停车场剩余4个车位，那么即使同时来了四辆车也能停的下。如果此时来了五辆车，那么就有一辆需要等待。

>　　信号量的值就相当于剩余车位的数目，dispatch_semaphore_wait函数就相当于来了一辆车，dispatch_semaphore_signal

>　　就相当于走了一辆车。停车位的剩余数目在初始化的时候就已经指明了（dispatch_semaphore_create（long value）），

>　　调用一次dispatch_semaphore_signal，剩余的车位就增加一个；调用一次dispatch_semaphore_wait剩余车位就减少一个；

>　　当剩余车位为0时，再来车（即调用dispatch_semaphore_wait）就只能等待。有可能同时有几辆车等待一个停车位。有些车主

>　　没有耐心，给自己设定了一段等待时间，这段时间内等不到停车位就走了，如果等到了就开进去停车。而有些车主就像把车停在这，

>　　所以就一直等下去。

 [《GCD dispatch_semaphore 信号量 协调线程同步》](http://m.blog.csdn.net/blog/choudang/38121827) 也有类似的比喻：


 > 以一个停车场是运作为例。为了简单起见，假设停车场只有三个车位，一开始三个车位都是空的。这时如果同时来了五辆车，看门人允许其中三辆不受阻碍的进入，然后放下车拦，剩下的车则必须在入口等待，此后来的车也都不得不在入口处等待。这时，有一辆车离开停车场，看门人得知后，打开车拦，放入一辆，如果又离开两辆，则又可以放入两辆，如此往复。
</p> 在这个停车场系统中，车位是公共资源，每辆车好比一个线程，看门人起的就是信号量的作用。
更进一步，信号量的特性如下：信号量是一个非负整数（车位数），所有通过它的线程（车辆）都会将该整数减一（通过它当然是为了使用资源），当该整数值为零时，所有试图通过它的线程都将处于等待状态。在信号量上我们定义两种操作： Wait（等待） 和 Release（释放）。 当一个线程调用Wait（等待）操作时，它要么通过然后将信号量减一，要么一直等下去，直到信号量大于一或超时。Release（释放）实际上是在信号量上执行加操作，对应于车辆离开停车场，该操作之所以叫做“释放”是因为加操作实际上是释放了由信号量守护的资源。


这个比喻里可以用一个表格来表示：

喻体 | 本体 |  代码 | 解释
-------------|-------------|-------------|-------------
车位 | 信号量 |  `dispatch_semaphore_t`  |
剩余几个车位 | 最大并发线程 |  `dispatch_semaphore_t`  |
看门人起的作用 | 信号量的作用 | `dispatch_semaphore_t`  |
车 | 线程 | 代码 |
耐心的极限时间 | 超时时间 |  `dispatch_semaphore_wait`  |
逛街结束走了，离开车位 | signal+1 |  `dispatch_semaphore_signal`  |


 