#Facebook 出品的 Parse 其 iOS SDK 的底层多线程处理思路

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
