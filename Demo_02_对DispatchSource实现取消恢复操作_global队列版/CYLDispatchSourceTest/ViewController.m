//
//  ViewController.m
//  CYLDispatchSourceTest
//
//  Created by 微博@iOS程序犭袁（ http://weibo.com/luohanchenyilong/） on 15/9/1.
//  Copyright (c) 2015年 https://github.com/ChenYilong . All rights reserved.
//  演示效果见：http://i59.tinypic.com/suyt0o.jpg

#import "ViewController.h"

@interface ViewController () {
    dispatch_source_t _processingQueueSource;
}

@property (atomic, assign, getter=isRunning) BOOL running;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    //1.
    // 指定DISPATCH_SOURCE_TYPE_DATA_ADD，做成Dispatch Source(分派源)。设定 global Dispatch Queue 为追加处理的Dispatch Queue
    _processingQueueSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_DATA_ADD, 0, 0,
                                                    dispatch_get_global_queue(0, 0));
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
