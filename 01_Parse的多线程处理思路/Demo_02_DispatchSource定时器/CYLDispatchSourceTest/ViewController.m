//
//  ViewController.m
//  CYLDispatchSourceTest
//
//  Created by 微博@iOS程序犭袁（ http://weibo.com/luohanchenyilong/） on 15/9/1.
//  Copyright (c) 2015年 https://github.com/ChenYilong . All rights reserved.
//

#import "ViewController.h"

@interface ViewController () {
    dispatch_source_t _processingQueueSource;
}

@property (atomic, assign, getter=isRunning) BOOL running;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    //    //1.
    //    // 指定DISPATCH_SOURCE_TYPE_DATA_ADD，做成Dispatch Source(分派源)。设定Main Dispatch Queue 为追加处理的Dispatch Queue
    //    _processingQueueSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_DATA_ADD, 0, 0,
    //                                                    dispatch_get_main_queue());
    //    __block NSUInteger totalComplete = 0;
    //    dispatch_source_set_event_handler(_processingQueueSource, ^{
    //        //当处理事件被最终执行时，计算后的数据可以通过dispatch_source_get_data来获取。这个数据的值在每次响应事件执行后会被重置，所以totalComplete的值是最终累积的值。
    //        NSUInteger value = dispatch_source_get_data(_processingQueueSource);
    //        totalComplete += value;
    //        NSLog(@"进度：%@", @((CGFloat)totalComplete/100));
    //        NSLog(@"🔵线程号：%@", [NSThread currentThread]);
    //    });
    //    //分派源创建时默认处于暂停状态，在分派源分派处理程序之前必须先恢复。
    //    [self resume];
    //
    //    //2.
    //    //恢复源后，就可以通过dispatch_source_merge_data向Dispatch Source(分派源)发送事件:
    //    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    //    dispatch_async(queue, ^{
    //        for (NSUInteger index = 0; index < 100; index++) {
    //            dispatch_source_merge_data(_processingQueueSource, 1);
    //            NSLog(@"♻️线程号：%@", [NSThread currentThread]);
    //            usleep(20000);//0.02秒
    //        }
    //    });
    
    /*
     *
     *指定DISPATCH_SOURCE_TYPE_TIMER，作成Dispatch Source
     *在定时器经过指定时间时设定Main Dispatch Queue 为追加处理的 Dispatch Queue
     DISPATCH SOURCE TYPE TIMER, 0,~0, disp~atch get_main_queue( )) 1
     *
     */
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue ());
    /*
     *
     .将定时器设定为15秒后。
     .不指定为重复。
     .允许迟延1秒。
     *
     */
    dispatch_source_set_timer(timer,
                              dispatch_time(DISPATCH_TIME_NOW, 15ull * NSEC_PER_SEC) ,
                              DISPATCH_TIME_FOREVER, lull * NSEC_PER_SEC);
    /*
     *
     指定定时器指定时间内执行的处理
     *
     */
    dispatch_source_set_event_handler(timer, ^{
        NSLog ( @"wakeup");
        /*
         *
         取消 Dispatch Source
         *
         */
        dispatch_source_cancel(timer);
    });
    
    /*
     *
     指定取消Dispatch Source 时的处理
     *
     */
    dispatch_source_set_cancel_handler(timer, ^{
        NSLog (@ "canceled");
        //        dispatch_release(timer);
    });
    
    /*
     *
     分派源创建时默认处于暂停状态，在分派源分派处理程序之前必须先恢复。
     *
     */
    dispatch_resume(timer);
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

@end
