/+
    Implements a stable 3-way partitioning algorithm which runs in O(n log n)
    time without any heap allocations; uses O(log n) stack space for recursion.
    
    Authors: Xinok
    License: Public Domain
+/

import std.algorithm : SwapStrategy;

/++
    TODO add/update documentation here
++/
auto isPartitioned3(alias pred = "a < b", Range, Pivot)(Range r, Pivot p)
{
    import std.range, std.functional;
    static assert(isInputRange!Range);
    alias less = binaryFun!pred;
    static assert(is(typeof(less(r.front, p)) == bool));
    static assert(is(typeof(less(p, r.front)) == bool));

    // Iterate over elements less than pivot
    while(!r.empty)
    {
        if(less(r.front, p)) r.popFront();
        else break;
    }

    // Iterate over elements equal to pivot
    while(!r.empty)
    {
        if(!less(r.front, p) && !less(p, r.front)) r.popFront();
        else break;
    }

    // Iterate over elements greater than pivot
    while(!r.empty)
    {
        if(less(p, r.front)) r.popFront();
        else break;
    }

    // If range was partitioned, we should have iterated over all
    // of the elements leaving the range empty
    return r.empty;
}

///
pure nothrow @nogc @safe
unittest
{
    int[20] test = [
        8, 10, 3, 6, 2, 4, 7, 9, 1, 5, 11,
        12, 14, 17, 15, 20, 18, 19, 16, 13
    ];

    assert(isPartitioned3(test[], 11));
    assert(isPartitioned3(test[], 12));
    assert(!isPartitioned3(test[], 5));
    assert(!isPartitioned3(test[], 14));
}

unittest
{
    // Any array with zero or one elements is always partitioned,
    // regardless of the pivot chosen.

    int[1] test = [0];

    assert(isPartitioned3(test[], -1));
    assert(isPartitioned3(test[], 0));
    assert(isPartitioned3(test[], 1));

    assert(isPartitioned3(test[0..0], -1));
    assert(isPartitioned3(test[0..0], 0));
    assert(isPartitioned3(test[0..0], 1));
}



auto part3(alias less = "a < b", Range, Pivot)(Range r, Pivot p)
{
    import std.typecons;
    auto parts = StablePartition3Impl!(less, Range, Pivot).part3(r, p, r.length);
    return tuple(r[0 .. parts[0]], r[parts[0] .. parts[1]], r[parts[1] .. parts[2]]);
}

template StablePartition3Impl(alias pred, Range, Pivot)
{
    import std.algorithm, std.range, std.functional, std.typecons, std.traits;

    static assert(isRandomAccessRange!Range);
    static assert(hasLength!Range);
    static assert(hasSlicing!Range);
    static assert(hasAssignableElements!Range ||
                  hasSwappableElements!Range);

    static assert(is(
        typeof(binaryFun!pred(Range.init.front, Pivot.init)) == bool
    ));

    alias less    = binaryFun!pred;
    alias Element = ElementType!Range;

    enum StackSize = 64;    // Length of static arrays on stack



    // Partition a small sublist using a technique dependent on the
    // type of the range
    size_t[3] part3Small()(Range r, Pivot p)
    {
        // These two variants were broken up into separate
        // functions for the sake of unit testing
        static if(hasAssignableElements!Range)
        {
            return part3SmallAssign(r, p);
        }
        else static if(hasSwappableElements!Range)
        {
            return part3SmallSwap(r, p);
        }
        else
        {
            static assert(false);  // This should never happen...
        }
    }



    // Partition sublist using a buffer
    size_t[3] part3SmallAssign()(Range r, Pivot p)
    {
        static assert(hasAssignableElements!Range);

        Element[StackSize] buffer = void;
        size_t lt, et, gt;
        et = buffer.length;

        foreach(e; r)
        {
            if(less(e, p))              // Less than pivot
            {
                r[lt++] = e;
            }
            else if(less(p, e))         // Greater than pivot
            {
                buffer[gt++] = e;
            }
            else                        // Equal to pivot
            {
                buffer[--et] = e;
            }
            
            if(et == gt) break;         // Buffer full
        }

        // Equal elements are in reverse order
        reverse(buffer[et .. buffer.length]);

        // Copy elements from buffer back into range
        copy(buffer[et .. buffer.length], r[lt .. lt + buffer.length - et]);
        et = lt + buffer.length - et;
        copy(buffer[0 .. gt], r[et .. et + gt]);
        gt += et;

        return [lt, et, gt];
    }



    // Partition sublist using array of indices
    size_t[3] part3SmallSwap()(Range r, Pivot p)
    {
        /+
            This variant is a hybrid of counting sort and cycle sort
            First, we count the number of elements in each partition
            Then we build an array of indices of where each element belongs
            Finally, we apply cycle sort but applying the array of indices
                to preserve stability and avoid unnecessary computation
        +/

        static assert(hasSwappableElements!Range);

        size_t[StackSize] indices = void;
        size_t lt, et, gt;

        // Truncate length of range
        immutable stopAt = r.length <= StackSize ? r.length : StackSize;

        // Step 1 : Count number of elements in each partition
        foreach(i; 0 .. stopAt)
        {
            if(less(r[i], p))           // Less than pivot
            {
                lt++;
                indices[i] = 1;
            }
            else if(less(p, r[i]))      // Greater than pivot
            {
                // gt++;
                indices[i] = 3;
            }
            else                        // Equal to pivot
            {
                et++;
                indices[i] = 2;
            }
        }

        // Step 2 : Compute sorted index of each element
        gt = lt + et;
        et = lt;
        lt = 0;

        foreach(ref e; indices[0..stopAt]) switch(e)
        {
            case 1: e = lt++; break;
            case 2: e = et++; break;
            case 3: e = gt++; break;
            default: assert(0);
        }

        // Step 3 : Use Cycle Sort to swap elements into place
        foreach(a; 0 .. stopAt)
        {
            size_t b = indices[a];
            size_t c;
            while(a != b)
            {
                r.swapAt(a, b);
                indices[].swapAt(a, b);
                b = indices[a];
            }
        }

        return [lt, et, gt];
    }



    // Partitions range[0 .. minLength]
    size_t[3] part3()(Range r, Pivot p, size_t minLength)
    {
        // Partition a small sublist
        auto parts = part3Small(r, p);
        size_t lt = parts[0];
        size_t et = parts[1];
        size_t gt = parts[2];

        // This ensures a few elements aren't left over at the end of the range
        if(minLength >= r.length / 2) minLength = r.length;

        // Recursively build small partitions and merge them using rotations
        while(gt < minLength)
        {
            parts = part3(r[gt .. r.length], p, gt);
            size_t p4 = parts[0] + gt;
            size_t p5 = parts[1] + gt;
            size_t p6 = parts[2] + gt;

            /+
                These statements use a sequence of reversals
                to rotate the elements into place
            +/
            reverse(r[et..p4]);
            gt = p4 - gt + et;
            reverse(r[lt..gt]);
            reverse(r[gt..p5]);
            et = gt - et + lt;
            p4 = p5 - p4 + gt;
            reverse(r[et..gt]);
            reverse(r[gt..p4]);
            lt = et;
            et = p4;
            gt = p6;
        }

        return [lt, et, gt];
    }
}

pure nothrow @nogc @safe
unittest
{
    // Stable partition3 should be able to infer the attributes above
    int[5] arr = [4, 3, 2, 1, 0];
    auto parts = part3(arr[], 2);
    assert(arr == [1, 0, 2, 4, 3]);
    assert(isPartitioned3(arr[], 2));
    assert(parts[0] == arr[0..2]);
    assert(parts[1] == arr[2..3]);
    assert(parts[2] == arr[3..$]);
}

unittest
{
    // Test both variants of function part3Small

    immutable int[32] arr =
        [2, 19, 32, 30, 18, 27, 31, 8, 25, 7, 1, 24, 3, 23, 10, 16,
         5, 28, 4, 21, 6, 11, 14, 26, 12, 20, 15, 22, 17, 13, 9, 29];

    immutable int[32] arr2 =
        [2, 8, 7, 1, 3, 10, 5, 4, 6, 11, 12, 9, 13, 19, 32, 30, 18,
         27, 31, 25, 24, 23, 16, 28, 21, 14, 26, 20, 15, 22, 17, 29];

    // Test variant part3SmallAssign
    int[] test = arr.dup;
    StablePartition3Impl!("a < b", int[], int).part3SmallAssign(test, 13);
    assert(test == arr2);

    // Test variant part3SmallSwap
    test = arr.dup;
    StablePartition3Impl!("a < b", int[], int).part3SmallSwap(test, 13);
    assert(test == arr2);
}

unittest
{
    // Large partitioning, stability, and CTFE test

    import std.array, std.random, std.range, std.algorithm;


    struct Element
    {
        size_t value;
        size_t index;
    }

    bool predicate(Element a, Element b)
    {
        return a.value < b.value;
    }


    // Generate test array with duplicate elements
    bool test()
    {
        enum seed = 1153316679;
        auto rnd = Random(seed);
    
        auto r = iota(0, 1024).map!(a => Element(a % 64, 0)).array;
        randomShuffle(r, rnd);
        foreach(i, ref e; r) e.index = i;

        // Partition range
        auto pivot = Element(41, 0);
        auto parts = part3!predicate(r, pivot);

        // Check result is partitioned
        assert(isPartitioned3!predicate(r, pivot));

        // Check range was partitioned stably
        foreach(p; parts) foreach(i; 1 .. p.length)
        {
            assert(p[i-1].index < p[i].index);
        }
        
        return true;
    }
    
    // Runtime test
    test();
    
    // Compile-time test
    enum CTFE = test();
}



version(unittest){ }
else void main()
{
    import std.stdio, std.algorithm, std.random, std.array, std.datetime, std.range;
    auto arr = iota(0, 2^^20).array;
    randomShuffle(arr);

    StopWatch sw;
    sw.start();
    part3(arr, arr.length / 2);
    sw.stop();
    writeln(sw.peek);

    randomShuffle(arr);

    sw.reset();
    sw.start();
    partition3(arr, arr.length / 2);
    sw.stop();
    writeln(sw.peek);
}
