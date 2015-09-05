//
//  ViewController.m
//  CYLDispatchQueueSuspendTest
//
//  Created by 微博@iOS程序犭袁（ http://weibo.com/luohanchenyilong/） ： 15/9/5.
//  Copyright (c) 2015年 https://github.com/ChenYilong All rights reserved.
//

#import "ViewController.h"

@interface ViewController ()

@end

@implementation ViewController

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

@end
