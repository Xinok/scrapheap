/+
    A proof of concept for "defer" in D
    
    Authors: Xinok
    License: Public Domain
+/

import std.stdio, std.array;

struct Defer
{
    Appender!(void delegate()[]) stack;
    
    ~this()
    {
        foreach_reverse(s; stack.data) s();
    }

    void opCall(lazy void call)
    {
        stack.put(() => call);
    }

    void put(void delegate() call)
    {
        stack.put(call);
    }

    void put(ARGS...)(void delegate(ARGS) call, ARGS args)
    {
        stack.put(() => call(args));
    }

    void capture(alias call, ARGS ...)(ARGS args)
    {
        stack.put(() => call(args));
    }
}

void demo1()
{
    // The statement "Hello!" won't be printed until the function exits

    Defer defer;
    writeln("begin");
    defer(writeln("Hello!"));
    writeln("end");
}

void demo2()
{
    // A replica of an example from the Go programming language
    // https://tour.golang.org/flowcontrol/13
    // Here, we must "capture" the value of i and store it

    Defer defer;
    writeln("counting");
    foreach(i; 0..10) defer.capture!writeln(i);
    writeln("done");
}

void demo3()
{
    // Deferred statements are still called even if the function throws
    Defer defer;

    defer(writeln("Exiting function..."));
    writeln("What happens if I press this button...");
    throw new Exception("whoops");
    writeln("WTF?!?!");
}

void demo4()
{
    // You can have multiple stacks of deferred statements

    Defer evens;
    Defer odds;

    writeln("counting");
    foreach(i; 0..10)
    {
        if(i % 2 == 0) evens.capture!writeln(i, " is even");
        else           odds.capture!writeln(i, " is odd");
    }
    writeln("done");
}

void main()
{
    demo1();
    writeln();

    demo2();
    writeln();

    try demo3();
    catch(Exception){ }
    writeln();

    demo4();
    writeln();
}
