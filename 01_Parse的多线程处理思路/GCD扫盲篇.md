#GCD 扫盲篇


GCD有四个概念：串行队列、并行队列、同步、异步四者。


如下简介：

这里不仅给出了不确定性，而且也给出了确定性。对于初学者而言，有时候因为那些不确定的东西所造成的疑问会像没有闸却在疾驰的汽车一样让人惊慌失措，而“确定性”就如同这救命的车闸一样，它能让你豁然开朗。

名称 | 功能特点 | 确定性解释 | 不确定性解释
-------------|-------------|------------- | ----------
同步 |完成需要做的任务后才会返回，进行下一任务 | “任务”，在 GCD 里指的是 Block；在 performSelector 方法中，对应 selector 方法。</p>同步方法，功能类似  `dispatch_group_wait` ，而 group 指的是所有线程，包括主线程。 | </p> 不一定是多线程
异步 | 不会等待任务完成才返回，会立即返回。 | 异步是多线程的代名词，因为必定会开启新的线程，线程的申请是由异步负责，起到开分支的作用。 | --
串行队列 | 任务依次执行 | 同一时间队列中只有一个任务在执行，每个任务只有在前一个任务执行完成后才能开始执行。| 你不知道在一个Block（任务）执行结束到下一个Block（任务）开始执行之间的这段时间时间是多长，![enter image description here](http://cdn4.raywenderlich.com/wp-content/uploads/2014/01/Serial-Queue-480x272.png)
并行队列 | 任务并发执行 | 你唯一能保证的是，这些任务会按照被添加的顺序开始执行。但是任务可以以任何顺序完成 |  你不知道在执行下一个任务是从什么时候开始，或者说任意时刻有多个Block（任务）运行，这个完全是取决于GCD。![enter image description here](http://cdn3.raywenderlich.com/wp-content/uploads/2014/01/Concurrent-Queue-480x272.png)
全局队列 | 隶属于并行队列 | 不要与 barrier 栅栏方法搭配使用， barrier 只有与自定义的并行队列一起使用，才能让 barrier 达到我们所期望的栅栏功能。与 串行队列或者 global 队列 一起使用，barrier 的表现会和 dispatch_sync 方法一样。
主队列 | 隶属于串行队列 | 不能与 sync 同步方法搭配使用，会造成死循环


串行队列、并行队列、同步、异步四者的组合：


GCD提供了dispatch queues（调度队列）来执行代码段，这些队列以FIFO（先进先出）的方式来管理你用GCD提交的任务。这保证了你先提交的任务先执行，即第一个任务添加到队列中就第一个开始执行，第二个添加的任务将第二个执行，直到队列的最后一个任务。

--- | 同步 | 异步 
-------------|-------------|-------------
串行队列 | 不会新建线程，依然在当前线程上</p>类似同步锁，是同步锁的替代方案</p>✅ 常用| 会新建线程，只开一条线程</p>一条线程就够了</p> 每次使用 createDispatch 方法就会新建一条线程，多次调用该方法，会创建多条线程，多条线程间会并行执行
并行队列 | 不会新建线程，依然在当前线程上</p> | 会新建线程，可以开多条线程</p> iOS7-SDK 时代一般是5、6条， iOS8-SDK 以后可以50、60条 </p> ✅ 常用


参考链接： [***Why can't we use a dispatch_sync on the current queue?***](http://stackoverflow.com/questions/10984732/why-cant-we-use-a-dispatch-sync-on-the-current-queue) 


## 串行队列中的同步与异步的区别

串行队列能确保顺序执行任务，他们两个的唯一区别在于`dispatch_sync`只会在 block 完全执行完之后返回，`dispatch_async` 不能确保会在 block 完全执行完之后返回，唯一能确定的是会在被添加到queue 队列后返回。


下面的代码：

    dispatch_async(_serialQueue, ^{ printf("1"); });
    printf("2");
    dispatch_async(_serialQueue, ^{ printf("3"); });
    printf("4");

可能会打印 `2413` 、 `2143` 、 `1234` ，但有一点是可以确认的： `1` 总是在 `3` 之前。

可能的打印：


 ```Objective-C
1
2
3
4

----------

2
4
1
3

1
2
3
4

----------
2
4
1
3
 ```



然而下面的代码：

    dispatch_sync(_serialQueue, ^{ printf("1"); });
    printf("2");
    dispatch_sync(_serialQueue, ^{ printf("3"); });
    printf("4");

总会打印：`1234`


参考链接： [***Difference between dispatch_async and dispatch_sync on serial queue?***](http://stackoverflow.com/questions/19822700/difference-between-dispatch-async-and-dispatch-sync-on-serial-queue/19822753?stw=2#19822753) 

