//
//  ViewController.m
//  CYLDispatchSemaphoreTest
//
//  Created by 微博@iOS程序犭袁（ http://weibo.com/luohanchenyilong/） on 15/9/6.
//  Copyright (c) 2015年 https://github.com/ChenYilong . All rights reserved.
//

#import "ViewController.h"

@interface ViewController ()

@end

@implementation ViewController

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

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    NSLog(@"🔴类名与方法名：%s（在第%d行），描述：%@", __PRETTY_FUNCTION__, __LINE__, @"");
}

@end