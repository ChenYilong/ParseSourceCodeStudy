//
//  ViewController.m
//  FileCacheDemo
//
//  Created by 微博@iOS程序犭袁（ http://weibo.com/luohanchenyilong/） on 15/9/1.
//  Copyright (c) 2015年 https://github.com/ChenYilong . All rights reserved.
//

#import "ViewController.h"

typedef void (^GetDataCompletion)(NSData *data);

static NSString *const kETagImageURL = @"http://ac-g3rossf7.clouddn.com/xc8hxXBbXexA8LpZEHbPQVB.jpg";
static NSString *const kLastModifiedImageURL = @"http://image17-c.poco.cn/mypoco/myphoto/20151211/16/17338872420151211164742047.png";

@interface ViewController ()
@property (weak, nonatomic) IBOutlet UIImageView *iconView;
// 响应的 etag
@property (nonatomic, copy) NSString *etag;
@end

@implementation ViewController

-(void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event{
    [self getData:^(NSData *data) {
        self.iconView.image = [UIImage imageWithData:data];
    }];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    [self getData:^(NSData *data) {
        self.iconView.image = [UIImage imageWithData:data];
    }];
}

/*!
 @brief 如果本地缓存资源为最新，则使用使用本地缓存。如果服务器已经更新或本地无缓存则从服务器请求资源。
 
 @details
 
 步骤：
 1. 请求是可变的，缓存策略要每次都从服务器加载
 2. 每次得到响应后，需要记录住 etag
 3. 下次发送请求的同时，将etag一起发送给服务器（由服务器比较内容是否发生变化）
 
 @return 图片资源
 */
- (void)getData:(GetDataCompletion)completion {
    NSURL *url = [NSURL URLWithString:kETagImageURL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:15.0];
    
    // 发送 etag
    if (self.etag.length > 0) {
        [request setValue:self.etag forHTTPHeaderField:@"If-None-Match"];
    }
    
    [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
        
        // NSLog(@"%@ %tu", response, data.length);
        // 类型转换（如果将父类设置给子类，需要强制转换）
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSLog(@"statusCode == %@", @(httpResponse.statusCode));
        // 判断响应的状态码是否是 304 Not Modified （更多状态码含义解释： https://github.com/ChenYilong/iOSDevelopmentTips）
        if (httpResponse.statusCode == 304) {
            NSLog(@"加载本地缓存图片");
            // 如果是，使用本地缓存
            // 根据请求获取到`被缓存的响应`！
            NSCachedURLResponse *cacheResponse =  [[NSURLCache sharedURLCache] cachedResponseForRequest:request];
            // 拿到缓存的数据
            data = cacheResponse.data;
        }
        
        // 获取并且纪录 etag，区分大小写
        self.etag = httpResponse.allHeaderFields[@"Etag"];
        
        NSLog(@"etag值%@", self.etag);
        !completion ?: completion(data);
    }];
}

@end
