# 第五章 Linux网络编程基础API

## 1. 大小端字节序、主机字节序和网络字节序

1. 大端字节序：指一个整数的高位字节（23～31 bit）存储在内存的低地址处，低位字节（0～7 bit）存储在内存的高地址处。
2. 小端字节序：指一个整数的高位字节（23～31 bit）存储在内存的低地址处，低位字节（0～7 bit）存储在内存的高地址处。

如何用程序判断计算机采用的是大端还是小端：

```C++
#include<stdio.h>
void byteorder()
{
  union
  {
    short value;
    char union_bytes[sizeof(short)];
  }test;
  test.value=0x0102;
  if((test.union_bytes[0]==1)&&(test.union_bytes[1]==2))
  {
    printf("big endian\n");
  }
  else if((test.union_bytes[0]==2)&&(test.union_bytes[1]==1))
  {
    printf("little endian\n");
  }
  else
  {
    printf("unknown...\n");
  }
}
```

现代PC大多采用小端字节序，因此小端字节序又被称为主机字节序。

如果主机之间或者主机与网络之间采用了不同的大小端字节序，则进行数据传输的时候必定出错，因此规定：
		发送端总是把要发送的数据转化成大端字节序数据后再发送，而接收端知道对方传送过来的数据总是采用大端字节序，所以接收端可以根据自身采用的字节序决定是否对接收到的数据进行转换（小端机转换，大端机不转换）。

因此，大端字节序也称为网络字节序。

## 2. close和shutdown的区别

close是将进程的socket的引用计数-1，只有当socket的引用计数为0的时候，才真正关闭该socket。

其中，我们用fork创建一个子进程时，默认将父进程中的socket引用计数+1，因此想要关闭父进程中的socket，需要在子进程和父进程中都进行close操作，才能够完成。

shutdown：如果我们无论如何都要关闭这个socket而不是只对引用计数进行-1操作，应该执行shutdown操作。

```C++
#include<sys/socket.h>
int shutdown(int sockfd, int howto);
```

其中，howto参数指的是shutdown的具体操作：

1. SHUT_RD：关掉读的那一部分
2. SHUT_WR：关掉写的那一部分
3. SHUT_RDWR：都关

## 3. 带外数据（Out Of Band, OOB）

有些传输层协议具有OOB，用于迅速通告对方本端发生的重要事件。其拥有更高的优先级，总是立即被发送。

OOB运用的比较少，现已知仅有的是telnet、ftp等远程非活跃程序。

UDP没有OOB机制，TCP实际上也没有，但是其通过头部中的紧急指针标志和紧急指针两个字段，给应用程序提供了一种紧急方式。

**TCP发送OOB的过程**：

对于发送端：

1. 已经向缓冲区加入了N个字节的普通数据
2. 随后加入"abc"三个OOB，此时，待发送的TCP报文段的头部将被设置为URG标志，然后使紧急指针置为最后一个OOB的下一个字节：
   ![image-20201027081730993](C:\Users\20931\AppData\Roaming\Typora\typora-user-images\image-20201027081730993.png)
3. 发送端一次发送的多字节的带外数据中只有最后一字节被当作带外数据（字母c），而其他数据（字母a和b）被当成了普通数据。

对于接收端：

TCP只有在接收到紧急指针标志时才检查紧急指针，然后根据紧急指针所指的位置确定OOB的位置，并读入特殊缓存（带外缓存）。如果上层应用程序没有及时将带外数据从带外缓存中读出，则后续的带外数据（如果有的话）将覆盖它。

上述为默认接收模式，对于设置了SO_OOBINLINE选项的TCP连接，则带外数据将和普通数据一样被TCP模块存放在TCP接收缓冲区中。紧急指针可以用来指出带外数据的位置，**socket编程接口**（send和recv中将flag设置为MSG_OOB，Linux中常用int socketmark(int sockfd)来判断是否有OOB数据需要读取）也提供了系统调用来识别带外数据。

## 4. 如何用sendto/recvfrom进行面向连接（STREAM）的socket的数据读写

首先看sendto/recvfrom的系统调用接口：

```C++
#include<sys/types.h>
#include<sys/socket.h>
ssize_t recvfrom(int sockfd,void*buf,size_t len,int flags,struct sockaddr*src_addr,socklen_t*addrlen);
ssize_t sendto(int sockfd,const void*buf,size_t len,int flags,const struct sockaddr*dest_addr,socklen_t addrlen);
```

其中src_addr/dest_addr和addrlen分别表示发送端/接收端的地址和地址长度，如果将这两个系统调用用于面向连接的socket，只需要将上述两个参数设置为NULL来忽略发送端/接收端的socket地址。

## 5. 集中写和分散读

这两个被定义在通用数据读写函数中（既可以用于TCP，又可以用于UDP），有以下两个系统调用：

```C++
#include<sys/socket.h>
ssize_t recvmsg(int sockfd,struct msghdr*msg,int flags);
ssize_t sendmsg(int sockfd,struct msghdr*msg,int flags);
```

msg参数是msghdr结构体类型的指针，msghdr结构体的定义如下：

```C++
struct msghdr
{
  void*msg_name;/*socket地址*/
  socklen_t msg_namelen;/*socket地址的长度*/
  struct iovec*msg_iov;/*分散的内存块, 见后文*/
  int msg_iovlen;/*分散内存块的数量*/
  void*msg_control;/*指向辅助数据的起始位置*/
  socklen_t msg_controllen;/*辅助数据的大小*/
  int msg_flags;/*复制函数中的flags参数, 并在调用过程中更新*/
};
```

对于TCP，msg_name和msg_namelen设为NULL（因为TCP的socket本身就已经知道发送方/接收方的socket地址）；msg_iov结构体定义如下：

```C++
struct iovec
{
  void*iov_base;/*内存起始地址*/
  size_t iov_len;/*这块内存的长度*/
};
```

对于recvmsg而言，数据将被读取并存放在msg_iovlen块分散的内存中，这些内存的位置和长度则由msg_iov指向的数组指定，这称为分散读（scatter read）；对于sendmsg而言，msg_iovlen块分散内存中的数据将被一并发送，这称为集中写（gather write）。

## 6. 低水位标记

在socket选项中，SO_RCVLOWAT和SO_SNDLOWAT表示TCP发送端和接收端的低水位标记。它们一般被I/O复用系统调用（见第9章）用来判断socket是否可读或可写。

1. 当TCP接收缓冲区中可读数据的总数大于其低水位标记时，I/O复用系统调用将通知应用程序可以从对应的socket上读取数据；
2. 当TCP发送缓冲区中的空闲空间（可以写入数据的空间）大于其低水位标记时，I/O复用系统调用将通知应用程序可以往对应的socke上写入数据。
3. 默认情况下，TCP接收缓冲区的低水位标记和TCP发送缓冲区的低水位标记均为1字节。

# 第八章 高性能服务器程序框架

## 1. 服务器模型

1. C/S模型：就是典型的客户端/服务器模型，通过TCP协议的三次握手来建立两端之间的连接，达到通信的目的。不过在设计服务器时，需要创建多线程/多进程去处理多个客户端的connect请求，不然这个服务器就变成了非常低效的串行服务器了。
   ![image-20201101104446771](C:\Users\20931\AppData\Roaming\Typora\typora-user-images\image-20201101104446771.png)
2. p2p模型：摒弃了服务器和客户端的概念，使得每台机器在消耗服务的同时，也要给别人提供服务，这样资源就能够充分自由地共享。其中，云计算机群就可以看作P2P的典范。缺点：当用户之间传输的请求过多时，网络负载严重。

## 2. 服务器编程框架

主要由I/O处理单元、逻辑单元、网络存储单元和请求队列组成。

1. I/O处理单元：主要管理服务器与客户连接的模块，例如等待并接受新的客户的连接、接受客户数据、将服务器响应数据返回给客户端；其中收发数据可能在逻辑单元中进行处理；需要实现负载均衡
2. 逻辑单元：一个逻辑单元通常是一个进程或者线程，它用来分析和处理客户的数据，然后将结果传递给I/O处理单元或者直接发送给客户端
3. 网络存储单元：可以是数据库、缓存和文件，甚至是一台独立的服务器
4. 请求队列：请求队列是各个单元之间的通信方式的抽象

## 3. I/O模型

主要分为阻塞I/O和非阻塞I/O：

1. 阻塞I/O：可能因为无法立即完成的操作而被操作系统挂起，直到等待事件的发生。在socket基础API中，可能被阻塞的系统调用：connect、send、recv和accept
2. 非阻塞I/O：这种类型的系统调用总是立即返回，如果事件没有立即发生，则系统调用将返回-1，此时会有一个errno参数，我们可以根据这个errno参数来采用更进一步的操作，其中EAGAIN和EWOULDBLOCK是对于accpet、send和recv而言，EINPROGRESS是针对connect来说的：
   1. EAGAIN：再来一次
   2. EWOULDBLOCK：期望阻塞
   3. EINPROGRESS：在处理中

## 4. 两种高效的事件处理模式

这里介绍两种事件处理模式，同步I/O模型通常用于实现Reactor模式，异步I/O模型则用于实现Proactor模式。但是也可以使用同步I/O方式模拟出Proactor模式。

### 4.1 Reactor

Reactor模式是指他要求主线程（I/O处理单元）只负责监听文件描述上是否有事件发生，有的话就立即将该事件通知工作线程（逻辑单元，下同）。除此之外，主线程不做任何其他实质性的工作。读写数据，接受新的连接，以及处理客户请求均在工作线程中完成。

![image-20201101122115714](C:\Users\20931\AppData\Roaming\Typora\typora-user-images\image-20201101122115714.png)

### 4.2 Proactor

Proactor模式将所有I/O操作都交给主线程和内核来处理，工作线程仅仅负责业务逻辑。

![image-20201101122207491](C:\Users\20931\AppData\Roaming\Typora\typora-user-images\image-20201101122207491.png)



# 第九章 I/O复用

## 1. EPOLL系列系统调用

select和poll都是采用一个系统调用来解决fd监听，但是epoll使用了一组函数来完成任务；其次，epoll把用户关心的文件描述符上的事件放在内核里的一个事件表中，因此节省了每次调用从用户态向内核态传入fd数组的不必要的消耗，提升了性能。不过，epoll需要使用一个额外的文件描述符，来唯一标识内核中的这个事件表，由epoll_create函数实现：

```C++
#include<sys/epoll.h>
int epoll_create(int size)
```

该函数返回的文件描述符将用作其他所有epoll系统调用的第一个参数，以指定要访问的内核事件表。

下面的函数用来操作epoll的内核事件表：

```C++
#include<sys/epoll.h>
int epoll_ctl(int epfd, int op, int fd, struct epoll_event* event)
```

fd参数是要操作的文件描述符，op参数则指定操作类型：

1. EPOLL_CTL_ADD，往事件表中注册fd上的事件
2. EPOLL_CTL_MOD，修改fd上的注册事件
3. EPOLL_CTL_DEL，删除fd上的注册事件

event参数指定事件，它是epoll_event结构指针类型。epoll_event的定义如下：

```C++
struct epoll_event
{
  __uint32_t events;/*epoll事件，即事件类型，种类基本上与POLL上的相同，只需要在相应的宏上加上E，如epoll的可读事件EPOLLIN*/
  epoll_data_t data;/*用户数据，*/
};
```

epoll有两个额外的事件类型--EPOLLET和EPOLLONESHOT，data用于存储用户数据，类型epoll_data_t定义如下：

```C++
typedef union epoll_data
{
  void*ptr;	//指定与fd相关的用户数据
  int fd;	//指定事件所从属的目标文件描述符
  uint32_t u32;
  uint64_t u64;
}epoll_data_t;
```

由于epoll_data时联合类型，因此不能够同时使用ptr和fd两个数据成员，如果要将文件描述符和用户数据关联起来，只能使用其他手段，比如放弃使用epoll_data_t的fd成员，而在ptr指向的用户数据中包含fd。

epoll_ctl成功时返回0，失败则返回-1并设置errno。

最后是epoll_wait函数，原型如下：

```C++
#include<sys/epoll.h>
int epoll_wait(int epfd,struct epoll_event*events,int maxevents,int timeout);
```

epdf就是epoll_create返回的内核事件表，如果epoll_wait检测到事件，就将所有就绪的事件从内核事件表中复制到它的第二个参数events中，这个数组只用于输出epoll_wait检测到的就绪事件，而不像select和poll的数组参数那样既用于传入用户注册的事件，又用于输出内核检测到的就绪事件，极大提高了应用程序索引就绪文件描述符的效率。

## 2. ET模式和LT模式



# 实战笔记

## 网络编程相关API：

```c++
//关于字节序（网络和本地字节序不同）
unsigned long int htonl(unsigned long int hostlong);	//host Ip转换为network long
unsigned short int htons(unsigned short int hostshort);	//host port转换为network short
unsigned long int ntohl(unsigned long int netlong);		//networt Ip转换为host long
unsigned short int ntosl(unsigned short int netshort);	//network port转换为host short

struct sockaddr_un;	//专用socket地址：Unix本地域协议族  PF_UNIX
struct sockaddr_in;
struct sockaddr_in6;	//TCP/IP协议族的两个专用socket地址，分别对应v4和v6

struct sockaddr_in{
    sa_family_t sa_family;	//AF地址族
    u_int16_t sin_port;		//端口号，用网络字节序，有时需要转换
    struct in_addr sin_addr;	//IPv4地址结构
};
struct in_addr{
  	u_int32_t s_addr;		//网络字节序表示  
};
//所有专用socket地址在实际使用的时候都需要转换成sockaddr通用类型（直接强制转换）

int listenfd = socket(PF_INET, SOCK_STREAM, 0);
struct sockaddr_in address;	//一般用结构体sockaddr来表示socket地址

int ret = bind(listenfd, (struct sockaddr*)&address, sizeof(address));	//绑定socket和它的地址
ret = listen(listenfd, 5);	//创建监听队列，设置最大监听数

//设置socket三步走，socket、bind、listen

int accept(int sockfd, struct sockaddr* addr, socklen_t* addrlen);
//sockfd是经过listen监听的socket，addr用来接收客户端远端的socket地址，addrlen则是地址长度

//作为客户端如何发起连接
int connect(int sockfd, struct sockaddr* serv_addr, socklen_t* addrlen);

//关闭连接
int close(int fd);	//采用引用计数，此操作将fd引用计数-1，而fork创建子进程时默认将fd引用计数+1
int shutdown(int sockfd, int howto);	//howto可以指定关闭读/写/读写

//向socket上读写数据 -- TCP数据流
ssize_t recv(int sockfd, void* buf, size_t len, int flags);
ssize_t send(int sockfd, const void* buf, size_t len, int flags);
//两个函数非常相似，sockfd是操作对象，buf是读取/写入的数据地址，len是长度，flags一般设置为0
//recv和send都返回实际读取/写入的数据大小，recv可能返回0，表示通信对方已经关闭了连接，两者返回-1都表示操作失败
//-- UDP数据报读写	面向无连接的，所以要指定对方的socket地址信息src_addr或dest_addr
ssize_t recvfrom(int sockfd, void* buf, size_t len, int flags, struct sockaddr* src_addr, socklen_t* addrlen);
sszie_t sendto(int sockfd, const void* buf, size_t len, int flags, strcht sockaddr* dest_addr, socklen_t* addrlen);
//当最后两个参数设置成NULL时，就相当于recv()和send()，可以用于TCP数据读写

//获取本端和远端socket
int getsockname(int sockfd, struct sockaddr* address, socklen_t* len);
int getpeername(int sockfd, struct sockaddr* address, socklen_t* len);
```

## Linux高级I/O函数：

```C++
//创建文件描述符
int pipe(int fd[2]);	//创建管道，用于进程间的通信，fd[0]只能从管道中读，fd[1]只能向管道中写，若要实现双向传输，则需要建立两个管道
int socketpair(int domain, int type, int portocol, int fd[2]);	//直接创建双向管道

int dup(int file_descriptor);	//文件重定向
int dup2(int file_descriptor_one, int file_descriptor_two);
//通过dup和dup2可以实现简单的CGI服务器，CGI服务器就是让printf输出的内容直接发送给客户端

//实现零拷贝
ssize_t sendfile(int out_fd, int in_fd, off_t* offset, size_t count);
//in_fd必须是真实文件，不能是socket或管道，out_fd必须是socket
//还有一些零拷贝操作函数有：mmap和splice

//文件描述符操作函数
int fcntl(int fd, int cmd, ...);	//在网络编程中通常用来设置描述符非阻塞
	int old_operation = fcntl(fd, F_GETFL);
	int new_operation = old_operation | O_NONBLOCK;
	fcntl(fd, F_SETFL, new_operation);


```

## 服务器程序编程规范：

1. Linux服务器程序一般以后台进程的形式运行，即守护进程，守护进程的父进程通常是init进程
2. Linux服务器通常有一套日志系统
3. Linux服务器一般以某个专门的非root身份运行
4. Linux服务器程序通常是可配置的，有时配置过多时，

## 服务器模型：

C/S模型、p2p模型、

## Linux服务器技术概览

**采用的服务器模型**：C/S模型

**服务器编程框架**：I/O处理单元-->请求队列-->逻辑单元-->请求队列-->网络存储单元

**I/O模型**：I/O多路复用中的epoll方法，同时提供LT和ET的触发模式供用户选择

**高效的事件处理模式**：同步I/O（epoll方法）模拟的Proactor模式

​		主线程执行数据读写工作，读写完成之后，主线程向工作线程通知这一个“完成事件”，因此工作线程就直接获得了数据读写的结果，接下来只需要对读写的结果进行逻辑处理。

**高效的并发模式**：半同步/半反应堆模型 --> 半同步半异步的变形，当有任务在请求队列中时，由空闲工作线程通过竞争互斥锁的方式来获得任务管辖权；半反应堆表现在工作线程需要从socket上读取客户请求和往socket上写入服务器应答（Reactor模式）

​		此模型的缺点：需要对请求队列加锁，浪费CPU时间；每个工作线程同一时间只能够处理一个客户请求

## 1.线程同步机制封装类（lock/locker.h）

### 1.1 互斥锁（pthread_mutex）

用于创建互斥锁的接口：

```C++
int pthread_mutex_init(pthread_mutex_t *restrict mutex,const pthread_mutexattr_t *restrict attr);
```

其中，pthread_mutex_t是自定义的一种锁的数据结构，pthread_mutexattr_t则是锁的属性，主要有以下几种：

1. PTHREAD_MUTEX_TIMED_NP：普通锁，后续请求锁的线程将进入等待队列，按时间顺序依次互斥获得
2. PTHREAD_MUTEX_RECURSIVE_NP：嵌套锁，允许一个线程多次获得该锁，然后进行多次unlock来释放锁。不同线程的请求，在加锁线程解锁的过程中重新竞争
3. PTHREAD_MUTEX_ERPORCHECK_NP：检错锁，同一个线程请求同一个锁，返回EDEADLK，其他情况同普通锁，保证当不允许多次加锁时不出现最简单情况下的死锁。
4. PTHREAD_MUTEX_ADAPTIVE_NP：适应锁，仅等待解锁后重新竞争

在使用mutex时，可能会出现死锁操作，几个不成文基本原则来避免死锁：

1. 对共享资源操作前一定要获得锁
2. 完成相应操作之后一定要释放锁
3. 尽量短时间地占用锁
4. ABC连环获得锁，则也需要ABC连环释放
5. 线程错误时一定要记得释放锁！！

## 2. 半同步半反应堆线程池（threadpool/threadpool.h）

### 2.1 五种I/O模型

1. 阻塞IO：调用者在调用某个函数过程中无法处理其他业务。
2. 非阻塞IO：调用者在调用某个函数过程中，可以处理其他业务，只需要定时去检测IO事件是否就绪。
3. 信号驱动IO：linux用套接口进行信号驱动IO，安装一个信号处理函数，进程继续运行**并不阻塞**，当IO事件就绪，进程收到SIGIO信号，然后再去处理IO事件；实际上也是一种非阻塞IO。
4. IO复用：
5. 异步IO：调用aio_read告诉内核描述字缓冲区指针、缓冲区大小、文件偏移及通知方式后立即返回，待到内核将数据拷贝到缓冲区之后，再通知应用程序。

前面四种都是同步IO，同步IO指内核向应用程序通知的是就绪事件，要求用户代码自行执行IO操作；但是异步IO是指内核向应用程序通知的是完成事件，由内核完成IO操作。

### 2.2 事件处理模式

1. reactor模式：I/O处理单元只负责监听文件描述符上是否有事件发生，有则立即通知逻辑处理单元，其他所有的读写数据、接受新连接、处理客户请求等都在逻辑处理单元完成；通常由同步IO实现。
2. proactor模式：I/O处理单元（主线程和内核）完成读写数据、接受新连接等IO操作，逻辑单元（工作线程）则负责完成具体的业务逻辑，如客户请求；通常由异步IO实现。

### 2.3 用同步IO方式模拟proactor模式

用epoll实现

### 2.4 半同步/半反应堆并发模式

并发编程主要分为多进程和多线程两种，这里涉及的并发模式是指I/O处理单元与逻辑单元的协同完成任务的方法。

主要类别有：半同步/半异步模式，领导者/追随者模式。

其中，此同步/异步非上面所说到的同步IO和异步IO，两者完全不一样：

1. 同步：程序完全按照代码序列的顺序执行
2. 异步：程序的执行需要由系统事件来进行驱动；常见系统事件：中断、信号。

而半同步/半反应堆并发模式是半同步/半异步模式的变体。这里，半同步/半异步模式的工作流程如下：

1. 同步线程用来处理客户逻辑（逻辑单元）
2. 异步线程用来处理I/O事件（I/O单元）
3. 异步线程监听到客户请求后，将其封装成请求对象并插入请求队列中
4. 请求队列通知某个工作在同步模式的工作线程来读取并处理请求对象

半同步/半反应堆工作流程：

1. 主线程充当异步线程，负责监听所有socket上的事件
2. 若有新请求到来，主线程接收之以得到新的连接socket，然后往epoll内核事件表中注册该socket上的读写事件
3. 如果连接socket上有读写事件发生，主线程从socket上接收数据，并将数据封装成请求对象插入到请求队列中
4. 所有工作线程睡眠在请求队列上，当有任务到来时，通过竞争（如互斥锁）获得任务的接管权

### 2.5 pthread_create的陷阱

我们通常使用pthread_create来创建一个线程，其函数原型：

```C++
#include <pthread.h>
int pthread_create (pthread_t *thread_tid,                 //返回新生成的线程的id
   const pthread_attr_t *attr,         //指向线程属性的指针,通常设置为NULL
   void * (*start_routine) (void *),   //处理线程函数的地址
   void *arg);                         //start_routine()中的参数
```

其中第三个参数为一个函数指针，要求为静态函数，如果是类成员函数则要求其为静态成员函数。

若其中的线程函数为类成员函数，则this指针会被作为默认的参数被传进函数中，从而和线程函数参数arg不能够匹配，而static修饰后，this指针就不会传递了。

### 2.6 pthread_detach()操作

pthread_join()和pthread_detach()是一组意义相反的操作，其中pthread_join()是用来将子线程加入父线程中，子线程的资源回收需要程序员自己完成；而pthread_detach()是将子线程从父线程中分离出来，同时，其资源回收由内核完成。

## 3.http连接处理

### 3.1 有关epoll

epoll_create创建了一棵红黑树，除此之外内核还帮我们在文件系统里面创建了一个list链表，用于存储准备就绪的事件；epoll_ctl则负责向红黑树中注册元素；epoll_wait调用时，仅仅观察上述list链表中有没有数据即可；

那什么时候将相应事件插入到list链表中？epoll是根据每个fd上面的回调函数（中断函数）进行判断，只有发生了事件的socket才会主动去调用callback函数，其他空闲状态的socket不会调用，若是就绪事件，则插入list。

epoll支持高效的ET模式，并且还支持EPOLLONESHOT事件（只监听一次事件，如果还需要继续监听这个socket，则需要再次把这个socket加入到EPOLL队列里面）。该事件能进一步减少可读、可写和异常事件被触发的次数。

**注意**：并不是所有情况使用epoll都是最好的：

- 当监测的fd数目较小，且各个fd都比较活跃，建议使用select或者poll
- 当监测的fd数目非常大，成千上万，且单位时间只有其中的一部分fd处于就绪状态，这个时候使用epoll能够明显提升性能

### 3.2 HTTP状态码

HTTP有5种类型的状态码，具体的：

- 1xx：指示信息--表示请求已接收，继续处理。

- 2xx：成功--表示请求正常处理完毕。

- - 200 OK：客户端请求被正常处理。
  - 206 Partial content：客户端进行了范围请求。

- 3xx：重定向--要完成请求必须进行更进一步的操作。

- - 301 Moved Permanently：永久重定向，该资源已被永久移动到新位置，将来任何对该资源的访问都要使用本响应返回的若干个URI之一。
  - 302 Found：临时重定向，请求的资源现在临时从不同的URI中获得。

- 4xx：客户端错误--请求有语法错误，服务器无法处理请求。

- - 400 Bad Request：请求报文存在语法错误。
  - 403 Forbidden：请求被服务器拒绝。
  - 404 Not Found：请求不存在，服务器上找不到请求的资源。

- 5xx：服务器端错误--服务器处理请求出错。

- - 500 Internal Server Error：服务器在执行请求时出现错误。

### 3.3 mmap和munmap的理解

mmap()是分配一段匿名的虚拟内存地址，也可以映射一个文件到内存空间，mmap()必须是以PAGE_SIZE为单位进行映射，而内存也只能以页为单位进行映射，如果映射非PAGE_SIZE整数倍的地址范围，首先要进行内存对齐，强行以PAGE_SIZE的倍数大小进行映射。

munmap()就是释放映射的内存空间。

## 4. 定时器处理非活动连接

引入定时器的原因：由于非活跃用户占用了连接资源，大大影响了服务器的性能，通过实现一个服务器定时器，处理这种非活跃连接，释放连接资源。

### 4.1 基础知识

1. 定时事件：指固定一段时间触发一段代码，由该代码触发一个事件，如从内核事件表中删除非活跃连接，关闭连接文件描述符，释放连接资源。
2. 定时器：利用数据结构将多种定时事件封装起来。具体的，本代码中只涉及一种定时事件，就是定期检测非活跃连接，这时，我们就需要将**定时事件**和**连接资源**封装为一个定时器。
3. 定时器容器：是指使用某种容器类数据结构，将上述多个定时器组合起来，便于对定时事件统一管理。具体的，项目中使用升序链表将所有定时器串联组织起来。

### 4.2 定时器方法

Linux提供了三种设置定时器的方法：

1. socket选项中的SO_RECVTIMEO和SO_SENDTIMEO
2. SIGALRM信号
3. I/O复用系统调用的超时参数

### 4.3 信号通知流程

信号处理函数和当前进程是两条不同的执行路线，具体流程表现为，当进程收到信号时，进程会发生中断，然后CPU转而处理内核态中的系统调用或中断服务，转而又进入到用户态进行信息处理函数，完成之后CPU又回到内核态由系统调用来恢复主进程，然后CPU转到主进程中继续执行未完成的任务。如图：

![image-20201109081621105](C:\Users\20931\AppData\Roaming\Typora\typora-user-images\image-20201109081621105.png)

进程如何接收信号：

​	接收信号的任务是由内核代理的，当内核接收到信号后，会将其放到对应进程的信号队列中，同时向进程发送一个中断，使其陷入内核态。注意，此时信号还只是在队列中，对进程来说暂时是不知道有信号到来的。

### 4.4 进程之间如何进行管道通信（Linux中）

我们可以通过socketpair()方法来创建一个套接字对（双向管道），这两个套接字即创建了一条管道供双方进行通信

### 4.5 为什么要将管道通信的写端设置为非阻塞？

因为send是将信息发送给套接字缓冲区，如果缓冲区满了，则会阻塞，这时候会进一步增加信号处理函数的执行时间，为此，将其修改为非阻塞。

## 5. 数据库连接池

如何实现数据库连接池：在程序初始化的时候，集中创建多个数据库连接，并把他们集中管理，供程序使用，可以保证较快的数据库读写速度，更加安全可靠。

本项目中使用单例模式和链表结构来创建数据库连接池，实现对数据库连接资源的复用。

### 5.1 什么是RAII机制

RAII是指资源获取就是初始化。在C++中的具体做法是，使用一个对象，在其构造时获取对应的资源，在对象生命期内控制对资源的访问。

如何使用RAII机制？

由于系统的资源不具备自动释放的功能，而C++中的类具有自动调用析构函数的功能。因此，我们考虑把资源用类封装起来，对资源操作都封装在类的内部，在析构函数中进行释放资源。

### 5.2 连接池的功能

初始化、分配、释放、销毁

获取和释放过程通过信号量操作完成，wait()和post()

## 6. 面试题整理

包括项目介绍，线程池相关，并发模型相关，HTTP报文解析相关，定时器相关，日志相关，压测相关，综合能力等。

#### **项目介绍**

- 为什么要做这样一个项目？
  - 其实我认为这样一个C++高性能服务器的实现，其实能够让我学习到很多计算机网络、操作系统、Linux的知识，算是一种从计算机基础理论到实践跨出的第一步，通过对学习过的模式、模型等进行实现，能够加深印象。
- 介绍下你的项目
  - 实现能够供10000个用户同时访问的高并发web服务器，其中的核心技术点如下：
    - 线程池：采用半同步半反应堆线程池（并发模型），提供了Epoll中的ET和LT等方式的IO复用
    - 线程同步：包含三个关键技术--互斥锁保证线程安全，信号量实现线程同步以及条件变量来实现线程通信。
    - HTTP报文解析：用到了主从状态机来接收、解析、处理和发送HTTP请求和回应报文。
    - 定时器：设定的初衷是解决非活跃连接，用到了管道来实现进程通信
    - 日志：同步/异步日志、生产者消费者模式、单例模式（懒汉实现）、阻塞队列
- 简单说一下用户在访问页面时候后端服务器具体进行了哪些操作？
  - 首先从浏览器输入IP地址和端口号，然后通过TCP/IP协议与目标IP以及端口号建立TCP连接
  - 这时客户端就可以向服务器发送一个HTTP请求，Web服务器这边则是通过建立socket来监听各种请求（具体如下）
  - 服务器会首先创建一个文件描述符listenfd用来监听新的连接，因为这个listenfd是服务器的socket文件描述符，是用来和外部建立连接的socket。然后将listenfd放入epoll注册表中，如果listen到了新的用户，listenfd就会变成就绪事件。
  - 在epoll中要么是listenfd有新的连接到来，要么是其他通信fd上有数据传输，如果是有数据传输，则直接调用底层接口实现和对应客户端的数据传输工作，此时传输的就是http请求，可以直接放到http类中进行请求解析。
  - http用主从状态机解析请求，把用户请求丢给逻辑处理单元进行处理，

#### **线程池相关**

- 手写线程池
- 线程的同步机制有哪些？
  - 信号量、互斥锁和条件变量
- 线程池中的工作线程是一直等待吗？
  - 当线程池中的工作线程被创建之后，就会执行while(true)的死循环，并且通过m_queuestat.wait()信号量操作等待主线程向消息队列中添加请求，并用m_queuestat.post()操作来通知正在等待的工作线程进行竞争。所以当消息队列为空即信号量为0时，工作线程一直在等待。
- 你的线程池工作线程处理完一个任务后的状态是什么？
  - 在没有收到停止线程的要求之前，处理完一个任务就会理解进入下一次循环，继续通过m_queuestat.wait()来等待下一个请求的到来。
- 如果同时1000个客户端进行访问请求，线程数不多，怎么能及时响应处理每一个呢？
  - 多客户的情况首先能够想到的就是增加请求队列，让发送请求的客户端按一定顺序进行排序（这个排序可以有几种选择），直到有空闲线程的时候，再将线程分配给对应的请求。
  - 其次能够想到的就是集群方法，包括有负载均衡，直接把客户端请求送到还有空线程的服务器上面去。
  - 如果是1000w的高并发如何做？
    - 1000w通过一台服务器基本上是不可能实现的，肯定需要使用集群、负载均衡等方法
- **如果一个客户请求需要占用线程很久的时间，会不会影响接下来的客户请求呢，有什么好的策略呢?**
  - 设定线程访问最大时限？？优化线程调度算法？时间片？

#### **并发模型相关**

- 简单说一下服务器使用的并发模型？
  - 半同步/半反应堆模型，其是半同步/半异步模式的变；其中，工作线程采用同步，主线程（I/O线程采用异步形式）	
- reactor、proactor、**主从reactor**模型的区别？
  - reactor模式：主线程（I/O处理单元）只负责监听文件描述符上是否有事件发生，读写数据、接受新连接以及处理客户请求都在工作线程中完成。
  - proactor模式：主线程（I/O处理单元）需要负责处理读写数据、接受连接等I/O操作，工作线程只负责业务逻辑处理。
- 你用了epoll，说一下为什么用epoll，还有其他复用方式吗？区别是什么？
  - 因为epoll能够更加高效的处理，基于事件来驱动，而且其文件描述符在内核态，并且返回的文件描述符都是已经就绪的，不需要用户进行遍历来判断哪些是就绪的。
  - 还有select和poll，select用线性表存储，能够监听的fd个数限定，poll用链表进行存储，可以自由扩充监听的fd个数。
- 什么时候选用epoll，epoll一定在所有应用场景下都比其他两个好吗？
  - 当然不是：
    - 当所有的fd都是活跃连接，使用epoll不如poll和select，所以当监测的fd数目较小，而且各个fd都比较活跃时，使用select或者poll
    - 当检测数目非常大，成千上万，且单位时间内只有其中一部分fd处于就绪状态，使用epoll

#### **HTTP报文解析相关**

- 用了状态机啊，为什么要用状态机？
  - 项目里面用到了主从状态机，从状态机用负责读取报文的一行，主状态机则负责对该行数据进行解析，在主状态机的内部调用从状态机，而从状态机则驱动主状态机。
  - 至于为什么使用状态机，个人认为使用状态机是为了简化程序的分支，降低复杂度，对每种状态用一个case进行处理。http解析的过程中可能有各种返回值，如果逐一处理可能会比较麻烦。
- 状态机的转移图画一下
  - ![image-20201115150300194](C:\Users\20931\AppData\Roaming\Typora\typora-user-images\image-20201115150300194.png)
- https协议为什么安全？
  - https其实是http基于ssl的安全版本，其使用了CA证书还有非对称密钥和对称密钥结合的形式，所以比较安全。
- https的ssl连接过程
  - 首先服务器会向客户端发送公钥和自己的CA证书验证，当clinet验证了CA证书的正确性之后，就要结束非对称加密阶段。
  - 这时，客户端用公钥加密自己的对称密钥并发送给服务器（外界因为没有公钥对应的私钥所以无法破解发送的对称密钥），服务器端用自己的私钥解密公钥加密的报文从而获得客户端的对称密钥。此时，两方均拥有对称密钥，可以开始进行对称加密传输。
- GET和POST的区别
  - GET无法修改服务器上的资源，POST可以
  - GET可以用缓存优化（存为书签），POST不可以
  - GET把请求附在URL上，但是POST附在http包中。
  - POST支持二进制编码传输，GET只支持ASCII码。

#### **数据库登录注册相关**

- 登录说一下？
  - 登陆首先是在url请求中给定一个标志，并把cgi标志设置为1，方便系统进行登陆操作。登陆操作首先是要把数据库中的所有username和passwd存储在本地map中，然后解析http报文并提取出请求用户名和密码后，与map中的进行比对，完成登录操作。
- 你这个保存状态了吗？如果要保存，你会怎么做？（cookie和session）
  - 没有保存状态，我知道可以使用cookie和session来保存，由于时间原因，具体如何实现还没有深挖
- **登录中的用户名和密码你是load到本地，然后使用map匹配的，如果有10亿数据，即使load到本地后hash，也是很耗时的，你要怎么优化？**
- **用的mysql啊，redis了解吗？用过吗？**
- 为什么要建立数据库连接池啊？
  - 建立连接池的目的就是要减少不必要的数据库连接和释放操作，以空间换效率。
- 什么是RAII机制啊？
  - 项目中将数据库连接的获取和释放通过RAII机制进行分装，RAII是指资源获取就是初始化。在C++中的具体做法是，使用一个对象，在其构造时获取对应的资源，在对象生命期内控制对资源的访问。

#### **定时器相关**

- 为什么要用定时器？
  - 因为可能存在部分连接不活跃却占据了连接资源的现象，有一些连接长时间没有进行信息的交互，但又长期占用资源，影响服务器性能。
- 说一下定时器的工作原理
  - 定时器就是通过在内核中设置信号以及不同信号对应的信号处理函数，当系统触发后，CPU会向进程发送中断，进程响应中断就会陷入内核态，这时内核调用信号处理函数，信号处理函数（仅仅只是）在管道中发送对应信号到读端，然后读端去判断是什么信号，然后做出相应的处理。用一个双向链表来从旧到新存储每个连接对应的定时器，链表首位存储的是剩余时间最短的，尾部存储的是剩余时间最长的。其中对应的几种操作也就非常明了了：
    - 插入定时器操作：根据新增的定时器的剩余时间，将它插入到链表中的合适位置
    - 删除定时器操作：删除指定定时器
    - 调整定时器操作：先将该定时器删除，然后重新插入即可更新定时器的位置
    - tick()扫描操作：从头到尾遍历链表中的定时器，超时的删除掉，直到遇到未超时的就停止（第一个未超时的定时器后面所有的定时器也是未超时的，这就是用链表按一定顺序存储的好处）。
  - 在何时使用管道：使用socketpair创建两个套接字作为管道的读写端
- 双向链表啊，删除和添加的时间复杂度说一下？还可以优化吗？
  - 删除操作中直接给定了节点地址，所以复杂度为O(1)；插入是需要为新的节点找到对应的位置，所以需要遍历链表，复杂度为O(N)；
  - 可以用小顶堆优化（C++11中的priority_queue）
- 最小堆优化？说一下时间复杂度和工作原理
  - 如果用二叉树实现小顶堆，插入和删除操作都是**O(log(N))**的时间复杂度，但是查找操作需要O(N)，性能不算太好
  - 工作原理就是二叉树中的父亲节点小于其对应的子节点，这样其根节点存储的就是整个数据结构中最小的节点，所以称为小顶堆；
    - 其插入操作是在二叉树尾部直接插入新元素，然后向上比较，如果其比父亲节点小，则进行交换并一直向上追溯，直到比父亲节点大为止
    - 其删除操作是将堆顶元素与末尾元素交换位置，这是堆失去平衡，从根节点（原尾节点）向下访问，将其与小于自身的最小子节点交换，直至没有子节点小于其本身为止。

#### **日志相关**

- 说下你的日志系统的运行机制？
  - 运用单例模式来创建一个日志系统，来对服务器的运行状态、错误信息和访问数据情况进行记录；其中可以根据实际情况来选择同步/异步写入方式；其中异步写入方式就是一种生产者消费者模型（将其封装成阻塞队列），将写入的内容放到阻塞队列中，主线程去处理别的事务，创建一个写线程来将日志写入文件。
- 为什么要异步？和同步的区别是什么？
  - 因为异步写入日志就不会导致工作线程的阻塞，而如果使用同步的话，一旦同时进行写操作的线程过多，就会形成阻塞，降低服务器性能。
- 现在你要监控一台服务器的状态，输出监控日志，请问如何将该日志分发到不同的机器上？（消息队列）RabbitMQ
  - 通过RabbitMQ的方式：我们传统的方式是直接由工作线程将生成的日志放到阻塞队列中去，而RabbitMQ在其中添加一个Exchange，工作线程实际上是把日志发送到了exchange中，由exchange来决定将其发送给一个/多个queue中，这时选择fanout模式，就是进行广播，放到所有的queue中，这样就实现了将日志分发到不同的机器上。

#### **压测相关**

- 服务器并发量测试过吗？怎么测试的？
  - 测试过，使用的是webbench
- webbench是什么？介绍一下原理
  - webbench是一个自动压测的软件，其原理就是由父进程fork多个子进程，然后子进程在默认时间/命令行中给定时间内对目标服务器进行访问，并且通过管道向父进程发送访问信息的结果；父进程收集所有子进程的访问结果，当所有子进程访问结束之后，进行统计，并给用户显示最后的访问结果，并退出。
- 测试的时候有没有遇到问题？
  - 我测试的时候的并发量没有达到1000以上。。。

#### **综合能力**

- 你的项目解决了哪些其他同类项目没有解决的问题？
- 说一下前端发送请求后，服务器处理的过程，中间涉及哪些协议？
  - 域名那一步就省了，因为这里直接输入的就是IP:PORT
  - 然后网络通过IP:PORT RIP协议找到指定服务器的指定端口
  - 然后通过TCP协议建立连接
  - 通过HTTP请求来访问数据，进行操作

## 7. 面试题实战

#### 你怎么样实现这个高性能服务器的呢？

#### 高性能具体是怎么做的？

#### 划分为哪几个部分，有哪些关键组件？

#### 多个线程向一个socket写数据会有问题吗？往fd里面写是单线程的吗？







