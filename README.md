# kvstore


## Description

`kvstore` is key/value store based on `std.json`.

The basic structure was inspired by the *DUB package* `dddb`
(see [DUB package repository](https://code.dlang.org/packages/dddb)
and [GitHub project](https://github.com/cvsae/dddb)).

Data is hold in memory and can be serialized to disk as JSON. As there is no
memory management, i.e. caching, paging, etc., it can not be considered a
*database*. Therefore the size of data sets `kvstore` can handle is limited
to the memory available.

*Keys* and *values* both must be of type `string`. `wstring`, `dstring`,
their respective plain `char[]` equivalents, as well as *C strings*, are not
supported. However, an array of values can still be stored with a single key.

Data is serialized in JSON format. When deserializing a store from disk the file
is read in chunks of 4096 bytes. As the serialized data in JSON format does not
contain any newline symbols the store file only consists of a single line.
Reading such file line-wise would not be the best idea.

In addition to the standard `get`, `set`, `remove`, `clear` operations there are
a couple more interesting operations. Among those are `closest` and `swap`.

#### closest

`closest` computes that key in the store being most similar to the one passed to
the function. This may be useful if keys are string representation of dates,
like UNIX timestamps or dates in the form `yymmdd`, for instance. As a JSON
object is basically a *map*, `kvstore` itself can be used as a
*map data structure*. If the key for a value is computed (dynamically) the
results of such computation may be inaccurate. Keys are compared using a
(private) function of this library implementing the *Levenshtein distance*.

If the key already exists in the store, that key itself is returned. If the
passed key is `null` or empty, or if the store is empty, `null` is returned. If
there is only one key in the store then that key is returned independent of its
*distance* to the passed key.

If several keys with the same *Levenshtein distance* are found their respective
length is considered and the one with the length closest to the passed key is
returned. If all of the equal-distant keys are of the same length, as well,
their ASCII character code distance of the first differing character is
considered, additionally.

Computing the *Levenshtein distance* between two keys has a time complexity of
`O(m * n)` with `m` being the length of the first key, and `n` being the length
of the second key. The distance to the passed key is computed for every key in
the store. The array of keys will be sorted in advance to save some operations
using the default *Phobos* sorting algorithm which performs in `O(k * log(k))`
with `k` being the number of keys. This makes the `closest` function as costly
as `O((k * (m * n)) + (k * log(k)))` which is approximately `O(k * a^2)` on
average, with `k` being the number of keys in the store and `a` being the
average key length. This is actually an oversimplification but may give a hint
on the runtime performance of the operation.


#### swap

The `swap` operation swaps a key with its value, thus making the former value
the new key of that entry, and the former key the value for the new key. The
operation can also be performed on the whole store.
The swap operation is only permitted if for all keys the maximum number of
values (their *depth*) is 1.

If the whole store is to be swapped `true` is returned only if the swap
operation succeeds for all entries in the store. It is possible to enforce
*uniqueness*. When trying to swap the key and value of an entry the new
entry is only inserted into the store if no such key had been present before.
If uniqueness is required and a key already exists the operation fails.
Otherwise the new value is appended to the present key.

Note that not only all values (becoming the new keys) need to be unique for
this requirement, but no key must being equal to any of the *values* in the
store, because swapping is currently done *in-place*. Also keep the following
situation in mind. Having entries `{ key1: key2 }` and `{ key2: value2 }`,
with `unique = false`, these steps would be performed:

1. When `key1` is swapped it is appended to the value of `key2`:
   `{ key2: [value2, key1] }`
2. `key2` is still left to be swapped but now has a *depth* of 2 which
   is not allowed.

**CAUTION**: If only one of the swap operations for a single entry fails
the whole operation is aborted and the store remains in an inconsistent state.
The original state cannot be recovered in that case. (This may change in
the future.)

There are several possibilities to implement the ability for the store to
*roll back* to a consistent state. For instance:

* Insert the swapped entries into a new store instance and replace the
  old store if there was no error. (This would require twice the space in
  RAM.)
* Check the uniqueness of the *union* of values and keys before any
  swapping is done. (Since this is a costly operation it would decrease
  the overall speed of the swap operation significantly.)
* Save the current store to disk (or create a backup), perform the
  operation, and reload the original store from disk (or restore the
  backup) if the swapping fails. (This would also decrease the speed
  of the operation, because of the additional hard drive accesses and
  the parsing of the serialized JSON data.)


## Makefile targets

This project's lifecycle is managed using *GNU* `make`, rather than `dub`.
The *Makefile* provides the following targets: `build`, `lint`, `test`,
`install`, `uninstall`. Of course, `clean` and `pack` targets are also present.

#### `build`

- The `build` target produces a dynamic library `libkvstore.so`.
- The code is compiled for a 64-bit architecture using the *Digital Mars*
  compiler `dmd`.
  architecture.
- DDoc documentation in HTML format is generated on the fly by `dmd`.
- This library is optimized for speed and all symbols are stripped from the
  library using the command `strip`.
- A header file (*D interface file*) is also generated.

#### `lint`

- The `lint` target runs the `dscanner` tool against the source file
  `kvstore.d`.
- If there are no style warnings, nothing is printed and `dscanner` exits
  successfully with exit code 0. Hence, the Makefile target succeeds
  and `make` exits with code 0, as well.

#### `test`

- The `test` target does not produce any executable, but compiles the
  library in `debug` mode and immediately runs the contained *unit tests*.
- Additionally, a code coverage analysis is done and a report `kvstore.lst`
  is generated. The source code coverage for the unit tests (in percent) is
  printed afterwards.

#### `install`

- The `install` target copies the generated library to `/usr/lib`.
- In addition a symbolic link to the library is created in the same directory
  containing the current version of the library.
- This target can safely be executed several times.

#### `uninstall`

- The `uninstall` target reverts the step done by the `install` target.
- All files created by the `install` target are removed from `/usr/lib`.

#### `clean`

- The `clean` target removes all files generated by `build` and `test`.

#### `pack`

- The `pack` target bundles the files of this repository in an `.txz`-archive.


## Build, Test, Installation

So building the optimized and stripped library `libkvstore.so` (along with its
HTML documentation) is as simple as:

```
$ make
```

`$ make build`, `$ make kvstore`, and `$ make all` can be run equivalently.

To run the provided unit tests and perform a source code coverage analysis,
the following command can be executed:

```
$ make test
```

Installing the library on a Linux system is done by running:

```
$ make install
```


## Copyright

Copyright &copy; 2020-2021 Daniel Haase

`kvstore` is licensed under **GNU Lesser General Public License**, version 3.


## License disclaimer

```
kvstore - JSON key/value store
Copyright (C) 2020-2021 Daniel Haase

This program is free software: you can redistribute it and/or modify it under the
terms of the GNU Lesser General Public License as published by the Free
Software Foundation, either version 3 of the License, or (at your option)
any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License for more
details.

You should have received a copy of the GNU Lesser General Public License
along with this program.
If not, see <https://www.gnu.org/licenses/lgpl-3.0.txt>.
```

[https://www.gnu.org/licenses/lgpl-3.0.txt](https://www.gnu.org/licenses/lgpl-3.0.txt)
