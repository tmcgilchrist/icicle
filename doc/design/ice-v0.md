Ice V0
--------

These are the release notes for version zero.
This is going to be a fairly rough release.

I'd say that for the things we support, we support quite well.
However, there are going to be holes in what we support, and those holes have rough edges.
Most of the rough edges should be in the form of confusing error messages rather than running and doing the wrong thing.

Features
--------
1. Ivory-(mostly)-compatible PSV input/output.
2. C compilation from all supported Icicle queries.
3. Fast!

Limitations of V0
-----------------

We have left off a whole bunch of things for version zero.

### No resumable computation
In Ivory it only needs to look at the new data that has been ingested.
This is the eventual plan for Ice/Icicle also, but has not been implemented yet.

For now all the data must be read, for every snapshot.
We are quite a lot faster than Ivory though, so this should be OK for now.

### Arbitrarily nested arrays are unsupported
Nesting arrays to multiple levels, such as ``Array (Array (Array Int))``, does not work.
One level of nesting (``Array (Array Int)``) does work, but no further.

I doubt this will come up as a problem, but if you come up across an error message like this, it's probably nested arrays:
```
C error:
no such variable "iarray__iarray__iarray__iint_t"; did you mean "iarray__iarray__iint_t"?
```

### Missing Array, String and Map primitives
There are currently no primitives for working on Array, String and Map types.
Arrays can be created with ``latest`` and Maps with ``group``, but there is no way of indexing into an array, taking its length, or folding over it.
String primitives such as split, join, isPrefixOf and so on would also be useful.

There are of course far more missing features, but these are the most notable.

### No support for escaped strings in PSV input/output

We do not handle escaped characters at all. The following is illegal and will cause a parse error:

```
marge|fresh|{"green":"\""}|1858-11-16
```