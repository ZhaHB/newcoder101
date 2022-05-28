# c++ 补充知识点 (纯粹用于面试使用)

## 智能指针

&emsp;&emsp;智能指针的作用是管理一个指针，避免指针申请后未释放造成内存泄漏的问题。智能指针实际上就是一个类，超过类的作用域，析构可以自动释放资源。

### auto_ptr

```c++
auto_ptr<string> p1 (new string ("test"));
auto_ptr<string> p2;
p2 = p1;

// 若此时调用p1,就会出现问题,p2剥夺了p1的所有权 
```

### unique_ptr

```c++
unique_ptr<string> p1 (new string("test"));
unique_ptr<string> p2 ;
p2 = p1; //不被允许，考虑到所有权剥夺，在unique_ptr中禁止了拷贝构造
```

### shared_ptr

&emsp;&emsp;采用应用计数,解决auto_ptr在对象所有权上的局限性,使用成员函数use_count()来查看资源的所有者个数，在调用release()时,当前指针会释放资源所有权,当引用计数为0时候,释放该资源.

### weak_ptr

&emsp;&emsp;与shared_ptr一起配合使用解决循环引用问题。

## 重载、重写与重定义

* 重载：是指同一可访问区内被声明的几个具有不同参数列表的同名函数,重载不关心函数的返回类型

* 重写：virtual func的实现

* 重定义：派生类重新定义父类中相同名称非virtual函数,参数列表.重定义中参数列表和返回类型都可以不同.

## static_cast/dynamic_cast/

### static_cast

&emsp;&emsp;上行转化安全，下行转化不安全：主要执行非多态的转化操作

### dynamic_cast

&emsp;&emsp;专门用于派生类之间的转换吗,type-id必须是类指针,类引用,或者void*,对于下行转化是安全的,当类型不一致时候，转换过来的是空指针,而static_cast在类型不一致时候转换过来的是错误意义的指针,可能造成非法访问等问题

```c++
#include <iostream>
using namespace std;

class father {

public:
    virtual void foo() { cout << " f's foo()" << endl; }
};

class son :public father{
public:
    void foo() { cout << "son's foo()" << endl; }
    int m_data;
};

int main() {
    father tFather;
    son tSon;
    tSon.m_data = 123;

    father* pfather;
    son* pson;

    /*上行转化，不存在问题，多态有效*/
    pson = &tSon;
    pfather = dynamic_cast<father*> (pson);
    pfather->foo();

    /*使用pfather指向子类，后下行转换，没有问题*/
    pfather = &tSon;
    pson = dynamic_cast<son*>(pfather);
    pson->foo();
    cout << pson->m_data << endl;

    /*下行转换(pfater实际指向父类对象)，含有不安全操作，dynamic_cast发挥作用，使得转化指针为null*/
    pfather = &tFather;
    pson = dynamic_cast<son*>(pfather); // pson = NULL
    pson->foo(); 
    cout << pson->m_data << endl;

    /*下行转换，使用static_cast*/
    pfather = &tFather;
    pson = static_cast<son*>(pfather);
    pson->foo(); // 返回父类方法
    cout << pson->m_data << endl; // 不安全操作，对象实例根本没有data成员

    system("pause");
    return 0;
}
```

### const_cast

&emsp;&emsp;专门用于const属性的转换,去除const性质,或增加const性质,是四个转换符中唯一一个可以操作常量的转换符

### reinterpret_cast

&emsp;&emsp;使用特点:从底层对数据进行重新解释,依赖具体的平台,可移植性差;可以将整形转化为指针,也可以把指针转换为数组;可以在指针和引用之间进行肆无忌惮的转换.
