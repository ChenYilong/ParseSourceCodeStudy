
只有你真正感受到痛的时候，你才会考虑使用缓存。


由于微信、QQ、微博、这类的应用使用缓存很重，使一般的用户也对缓存也非常习惯。缓存已然成为必备。


服务器压力、客户端网络优化、用户体验、

缓存有不同的分类方法：

![enter image description here](http://image17-c.poco.cn/mypoco/myphoto/20151128/23/17338872420151128233958031.png?323x214_130)


这里所指的缓存，是一个宽泛的概念。

我们这里主要按照功能进行划分：


![enter image description here](http://image17-c.poco.cn/mypoco/myphoto/20151129/00/17338872420151129000650023.png?369x179_130
)

-| 第一种 |第二种
-------------|-------------|-------------
目的| 优化型缓存 | 功能型缓存
 具体描述 |  出于优化考虑：服务器压力、用户体验、为用户剩流量等等。同时优化型缓存也有内存缓存和磁盘缓存之分。 | App离线也能查看，出于功能考虑，属于存储范畴
常见概念 | GET网络请求缓存、WEB缓存 | 离线存储
典型应用 |  微信首页的会话列表、微信头像、朋友圈、网易新闻新闻列表、 |   微信聊天记录、
Parse对应的类 | PFCachedQueryController | PFOfflineStore
重度使用缓存的App：  微信、微博、网易新闻、携程、去哪儿等等。



## GET网络请求缓存

### 概述

首先要知道，POST请求不能被缓存，只有 GET 请求能被缓存。因为从数学的角度来讲，GET 的结果是 `幂等` 的，就好像字典里的 key 与 value 就是`幂等`的，而 POST 不 `幂等` 。缓存的思路就是将查询的参数组成的值作为 key ，对应结果作为value。从这个意义上说，一个文件的资源链接，也叫 GET 请求，下文也会这样看待。


### 80%的缓存需求：两行代码就可满足

设置缓存只需要三个步骤：

第一个步骤：请使用 GET 请求。

第二个步骤：

如果你已经使用 了 GET 请求，iOS 系统 SDK 已经帮你做好了缓存。你需要的仅仅是设置下内存缓存大小、磁盘缓存大小、以及缓存路径。甚至这两行代码不设置也是可以的，会有一个默认值。代码如下：


```objc
NSURLCache *urlCache = [[NSURLCache alloc] initWithMemoryCapacity:4 * 1024 * 1024 diskCapacity:20 * 1024 * 1024 diskPath:nil];
[NSURLCache setSharedURLCache:urlCache];
```

第三个步骤：没有第三步！


你只要设置了这两行代码，基本就可满足80%的缓存需求。AFNetworking 的作者 Mattt曾经说过：

> 无数开发者尝试自己做一个简陋而脆弱的系统来实现网络缓存的功能，殊不知 `NSURLCache` 只要两行代码就能搞定且好上 100 倍。

（AFN 是不是在暗讽 SDWebImage 复杂又蹩脚的缓存机制？？）


要注意

* iOS 5.0开始，支持磁盘缓存，但仅支持 HTTP
* iOS 6.0开始，支持 HTTPS 缓存

### 剩下20%的网络缓存需求

#### 真的有`NSURLCache` 不能满足的需求？

有人可能要问：

 > `NSURLCache` 不是帮我们做了硬盘缓存么？那我们为什么要自己用数据库做本地缓存啊。为啥不直接用`NSURLCache` 不是更方便？



系统帮我们做的缓存，好处是自动，无需我们进行复杂的设置。坏处也恰恰是这个：不够灵活，不能自定义。只能指定一个缓存的总文件夹，不能分别指定每一个文件缓存的位置，更不能为每个文件创建一个文件夹，也不能指定文件夹的名称。缓存的对象也是固定的：只能是 GET请求的返回值。


### 文件缓存：借助ETag或Last-Modified判断文件缓存是否有效


#### Last-Modified

服务器的文件存贮，大多采用资源变动后就重新生成一个链接的做法。而且如果你的文件存储采用的是第三方的服务，比如七牛、青云等服务，则一定是如此。

这种做法虽然是推荐做法，但同时也不排除不同文件使用同一个链接。那么如果服务端的file更改了，本地已经有了缓存。如何更新缓存？

这种情况下需要借助 `ETag` 或 `Last-Modified` 判断图片缓存是否有效。


 `Last-Modified` 顾名思义，是资源最后修改的时间戳，往往与缓存时间进行对比来判断缓存是否过期。

   在浏览器第一次请求某一个URL时，服务器端的返回状态会是200，内容是你请求的资源，同时有一个Last-Modified的属性标记此文件在服务期端最后被修改的时间，格式类似这样：


 ```Objective-C
        Last-Modified: Fri, 12 May 2006 18:53:33 GMT
 ```

  客户端第二次请求此URL时，根据 HTTP 协议的规定，浏览器会向服务器传送 If-Modified-Since 报头，询问该时间之后文件是否有被修改过：


 ```Objective-C
        If-Modified-Since: Fri, 12 May 2006 18:53:33 GMT
 ```

   如果服务器端的资源没有变化，则自动返回 HTTP 304 （Not Changed.）状态码，内容为空，这样就节省了传输数据量。当服务器端代码发生改变或者重启服务器时，则重新发出资源，返回和第一次请求时类似。从而保证不向客户端重复发出资源，也保证当服务器有变化时，客户端能够得到最新的资源。

判断方法：

 ```Objective-C
    BOOL isTooOld = NO;
    NSDate *lastModified = [ClassName lastModified];
    if ([[NSDate date] timeIntervalSinceDate:lastModified] > maxCacheAge) {
        isTooOld = YES;
    }
 ```



判断方法用伪代码表示：

 ```Objective-C
if ETagFromServer != ETagOnClient || LastModifiedFromServer != LastModifiedOnClient
   GetFromServer
else
   GetFromCache
 ```

之所以使用

 ```Objective-C
LastModifiedFromServer != LastModifiedOnClient
 ```
而非使用：

 ```Objective-C
LastModifiedFromServer > LastModifiedOnClient
 ```
原因是考虑到可能出现类似下面的情况：服务端可能对资源文件，废除其新版，回滚启用旧版本，此时的情况是：

 ```Objective-C
LastModifiedFromServer <= LastModifiedOnClient
 ```
但我们依然要更新本地缓存。


 参考链接：[ ***What takes precedence: the ETag or Last-Modified HTTP header?*** ](http://stackoverflow.com/a/824209/3395008) 


#### ETag

 `ETag`  是什么？是一个 hash 值，用作 Request 缓存请求头，每一个资源文件都对应一个唯一的  `ETag`  值，修改资源文件后该值会立即变更。这也决定了 `ETag`  在断点下载时非常有用。

* `If-None-Match` - 与响应头的 Etag 相对应，可以判断本地缓存数据是否发生变化


`ETag` 是首选，因为使用 `ETag ` 后，非常“省流量”：服务端不会每次都会返回文件资源。客户端每次向服务端发送上次服务器返回的 `ETag ` 值，服务器会根据客户端与服务端的  `ETag ` 值是否相等，来决定是否返回 data，同时总是返回对应的 `HTTP` 状态码。客户端通过 `HTTP` 状态码来决定是否使用缓存。比如：服务端与客户端的 `ETag` 值相等，则 `HTTP` 状态码为 304，不返回 data。服务端文件一旦修改，服务端与客户端的 `ETag` 值不等，并且状态值会变为200，同时返回 data。

七牛等第三方文件存储商现在都已经支持`ETag`，Demo8和9 中 给出的演示图片就是使用的七牛的服务，见：


 ```Objective-C
static NSString *const kETagImageURL = @"http://ac-g3rossf7.clouddn.com/xc8hxXBbXexA8LpZEHbPQVB.jpg";
 ```

虽然  `ETag`  是首选的方式，优于 `Last-Modified` 方式，但并非所有服务端都会支持，而 `Last-Modified` 则一般都会有该字段。 大多数情况下需要与服务端进行协调支持 `ETag`  ，如果协商无果就只能退而求其次。

Demo 也给出了一个不支持 `ETag` 的链接，基本随便找一张图片都行：

 ```Objective-C
static NSString *const kLastModifiedImageURL = @"http://img1.2345.com/duoteimg/qqTxImg/2013/12/ka_3/04-054658_103.jpg";
 ```

作为通用型的网络请求工具 AFNetworking 对该现状的处理方式是，判断服务端是否包含 `ETag` ，然后再进行相应处理。可见  `AFHTTPRequestOperation`  类中的用法:

 ```Objective-C
- (void)pause {
    unsigned long long offset = 0;
    if ([self.outputStream propertyForKey:NSStreamFileCurrentOffsetKey]) {
        offset = [[self.outputStream propertyForKey:NSStreamFileCurrentOffsetKey] unsignedLongLongValue];
    } else {
        offset = [[self.outputStream propertyForKey:NSStreamDataWrittenToMemoryStreamKey] length];
    }

    NSMutableURLRequest *mutableURLRequest = [self.request mutableCopy];
    if ([self.response respondsToSelector:@selector(allHeaderFields)] && [[self.response allHeaderFields] valueForKey:@"ETag"]) {
        [mutableURLRequest setValue:[[self.response allHeaderFields] valueForKey:@"ETag"] forHTTPHeaderField:@"If-Range"];
    }
    [mutableURLRequest setValue:[NSString stringWithFormat:@"bytes=%llu-", offset] forHTTPHeaderField:@"Range"];
    self.request = mutableURLRequest;

    [super pause];
}
 ```


下面使用一个 Demo 来进行演示用法，

以 `NSURLConnection` 搭配  `ETag` 为例，步骤如下：

* 请求的缓存策略使用 `NSURLRequestReloadIgnoringCacheData`，忽略本地缓存
* 服务器响应结束后，要记录 `Etag`，服务器内容和本地缓存对比是否变化的重要依据
* 在发送请求时，设置 `If-None-Match`，并且传入 `Etag`
* 连接结束后，要判断响应头的状态码，如果是 `304`，说明本地缓存内容没有发生变化

以下代码详见 Demo08 ：


 ```Objective-C
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
        
        // NSLog(@"%@ %tu", response, data.length);dd
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
 ```

相应的  `NSURLSession`  搭配 ETag 的版本见 Demo09：



 ```Objective-C
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
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        
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
        
        NSLog(@"%@", self.etag);
        dispatch_async(dispatch_get_main_queue(), ^{
            !completion ?: completion(data);
        });
    }] resume];
}
 ```


运行效果：

![enter image description here](http://image17-c.poco.cn/mypoco/myphoto/20151130/02/17338872420151130025013096.gif?454x255_110)

回顾下思路：

 - 为资源分派 hash 值，然后对比服务端与本地缓存是否一致来决定是否需要更新缓存。

这种思路，在开发中经常使用，比如：处于安全考虑，登陆操作一般不会传输账号密码，而是传输对应的 hash 值-- token ，这里的 token 就可以看做一个 file 资源，如果想让一个用户登陆超时时间是三天，只需要在服务端每隔三天更改下 token 值，客户端与服务端值不一致，然后服务端返回 token 过期的提示。


 `PFRESTUserCommand` 中使用


Query
基于查询条件、
 `PFFile` 
 `PFObjectFileCodingLogic` 上传文件


使用  `PFQueryState` 表示查询条件包含排序、缓存策略等，

## 离线存储
### 概述


SQLite、CoreData、

 什么情况下不适合缓存：搜群组、




多线程处理思路，更新：
搜：
PFThreadsafetySafeDispatchSync

用法

 ```Objective-C
- (void)_performDataAccessBlock:(dispatch_block_t)block {
    PFThreadsafetySafeDispatchSync(_synchronizationQueue, block);
}
 ```
