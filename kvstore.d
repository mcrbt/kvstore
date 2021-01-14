/**
 * kvstore - JSON key/value store
 * Copyright: Copyright (C) 2020-2021 Daniel Haase
 *
 * File: _kvstore.d
 * Author: Daniel Haase
 * License: LGPL-3.0
 *
 * This file is part of kvstore.
 *
 * kvstore is free software: you can redistribute it and/or modify it under the
 * terms of the GNU Lesser General Public License as published by the Free
 * Software Foundation, either version 3 of the License, or (at your option)
 * any later version.
 *
 * kvstore is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License for more
 * details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with kvstore. If not, see <https://www.gnu.org/licenses/lgpl-3.0.txt>.
 */

module kvstore;

import std.algorithm.comparison : min;
import std.algorithm.sorting : sort;
import std.conv : to;
import std.file : exists, getSize;
import std.json : JSONException, JSONValue, JSONOptions,
	JSONType, parseJSON, toJSON;
import std.math : abs;
import std.range : back, front;
import std.stdio : chunks, File, remove, write;
import std.string : toStringz;

private immutable string VERSION = "0.8.1";
private const JSONOptions options =
	(JSONOptions.escapeNonAsciiChars);

/**
 * The class KVStore handles the state and all operations
 * on the key/value store.
 */
public class KVStore
{
	private JSONValue json;
	private immutable string file;
	private ulong keyno;
	private ulong maxdepth;
	private bool dirty;

	/**
	 * Default constructor. Calls the `this(const string)` constructor
	 * with a default database filename (`default.kvs`).
	 *
	 * Throws: JSONException, ErrnoException, StdioException, UnicodeException
	 */
	this() { this("default.kvs"); }

	/**
	 * Loads the data file if filename exists.
	 * Otherwise a new JSON object is initialized.
	 * If filename is null or empty the filename defaults to
	 * `default.kvs`.
	 *
	 * Params:
	 *     filename = the name of data file to be loaded,
	 *     or the name of the new data file to be created, respectively
	 * Throws: JSONException, ErrnoException, StdioException, UnicodeException
	 */
	this(const string filename)
	{
		if((filename is null) || (filename.length == 0))
			this.file = "default.kvs";
		else this.file = filename.idup;

		if(this.file.exists) this.load();
		else
		{
			this.json = parseJSON("{}");
			this.keyno = 0;
			this.maxdepth = 0;
			this.dirty = true;
		}
	}

	/**
	 * Copy constructor. Creates a copy of store with an optional new filename.
	 * No data is loaded but only the passed-in store is cloned.
	 * If a new _filename is specified and if a file of that name already
	 * exists, calling `this.save()` would cause that file to be overridden.
	 * If filename is not specified the _filename of the old store will be
	 * copied, as well.
	 * If store is null the default constructor is called.
	 *
	 * Params:
	 *     store = a reference to a `KVStore` instance to be cloned
	 *     filename = the _filename associated with the cloned store (optional)
	 * Throws: JSONException, ErrnoException, StdioException, UnicodeException
	 */
	this(const ref KVStore store, const string filename = "")
	{
		if(store !is null)
		{
			this.json = parseJSON(store.toString());

			if((filename is null) || (filename.length == 0))
				this.file = store.file.idup;
			else this.file = filename.idup;

			this.keyno = store.keyno;
			this.maxdepth = store.maxdepth;
			this.dirty = store.dirty;
		}
		else
		{
			if((filename is null) || (filename.length == 0))
				this.file = "default.kvs";
			else this.file = filename.idup;

			if(this.file.exists) this.load();
			else
			{
				this.json = parseJSON("{}");
				this.keyno = 0;
				this.maxdepth = 0;
				this.dirty = true;
			}
		}
	}

	/**
	 * Loads the data file into memory.
	 * If the file does not exist a JSON object is initialized anyway.
	 *
	 * Returns: true if the data file was successfully loaded, false otherwise
	 * Throws: JSONException, ErrnoException, StdioException
	 * TODO: (string) decompression
	 */
	public bool load()
	{
		if(this.file.exists)
		{
			if(getSize(this.file) > 0)
			{
				File kvsfile = File(this.file, "r");
				scope(exit) kvsfile.close();

				string content = "";
				foreach(ubyte[] chunk; chunks(kvsfile, 4096))
					content ~= to!string(chunk);

				if(content.length > 0)
					this.json = parseJSON(content, -1, options);

				this.keyno = this.json.object.keys.length;
				this.recalculateMaximumDepth();
				this.dirty = false;
				return true;
			}
		}

		this.json = parseJSON("{}");
		this.keyno = 0;
		this.maxdepth = 0;
		this.dirty = true;
		return false;
	}

	/**
	 * Writes the JSON data from memory to file on disk.
	 *
	 * Throws: JSONException, FileException, ErrnoException
	 * TODO: (string) compression
	 */
	public void save()
	{
		File kvsfile = File(this.file, "w");
		scope(exit) kvsfile.close;
		kvsfile.write(toJSON(this.json, false, options));
		this.dirty = false;
	}

	/**
	 * Clears the JSON data of this store in memory.
	 * The data file on disk is not affected.
	 *
	 * Throws: JSONException
	 */
	public pure void clear()
	{
		this.json.object.clear;
		this.keyno = 0;
		this.maxdepth = 0;
		this.dirty = true;
	}

	/**
	 * Deletes the data file on disk.
	 * The in-memory JSON store is not affected.
	 *
	 * Throws: FileException
	 */
	public bool drop()
	{
		if(this.file.exists)
		{
			this.file.toStringz.remove;
			this.dirty = true;
			return true;
		}

		return false;
	}

	/**
	 * Checks if key exists in the data store.
	 * key must neither be null nor empty.
	 *
	 * Params:
	 *     key = the _key to be checked
	 * Returns: true iff key was found,
	 *     false if not or if key is null or empty
	 */
	public pure bool hasKey(const string key) const
	{
		if((key is null) || (key.length == 0)) return false;
		return ((key in this.json) !is null);
	}

	/**
	 * Retrieves the value stored for key.
	 * key must neither be null nor empty.
	 *
	 * Params:
	 *     key = the _key of which the value should be returned for
	 * Returns: the value found for key,
	 *     null if key was not found
	 *     and a JSON array as string if multiple values are stored
	 * Throws: JSONException
	 * See_Also: `kvstore.KVStore.getFirst`, `kvstore.KVStore.getAll`
	 */
	public string get(const string key) const
	{
		// input validation in "this.hasKey()"
		if(!this.hasKey(key)) return null;

		if(this.json[key].type == JSONType.string)
			return this.json[key].str;
		else return toJSON(this.json[key], false, options);
	}

	/**
	 * Retrieves the value stored for key.
	 * If multiple values are stored only the first one is returned.
	 * key must neither be null nor empty.
	 *
	 * Params:
	 *     key = the _key of which the value should be returned for
	 * Returns: the first (or only) value stored for key
	 * Throws: JSONException
	 * See_Also: `kvstore.KVStore.get`, `kvstore.KVStore.getAll`
	 */
	public string getFirst(const string key) const
	{
		// input validation in "this.hasKey()"
		if(!this.hasKey(key)) return null;

		if(this.json[key].type == JSONType.array)
		{
			if(this.json[key].array.length > 0)
			{
				JSONValue first = this.json[key].array[0];
				if(first.type == JSONType.string) return first.str;
				else return toJSON(first, false, options);
			}
			else return null;
		}
		else if(this.json[key].type == JSONType.string)
			return this.json[key].str;
		else return toJSON(this.json[key], false, options);
	}

	/**
	 * Retrieves all values stored for key.
	 * If only one value is stored, an array with one element is returned.
	 * key must neither be null nor empty.
	 *
	 * Params:
	 *     key = the _key of which all values should be returned for
	 * Returns: a string array contain all values stored for key
	 * Throws: JSONException
	 * See_Also: `kvstore.KVStore.get`, `kvstore.KVStore.getFirst`
	 */
	public string[] getAll(const string key) const
	{
		// input validation in "this.getKey()"
		if(!this.hasKey(key)) return null;

		string[] coll;

		if(this.json[key].type == JSONType.array)
			coll = toArray(this.json[key]);
		else
		{
			coll.length = 1;

			if(this.json[key].type == JSONType.string)
				coll[0] = this.json[key].str;
			else coll[0] = toJSON(this.json[key], false, options);
		}

		return coll;
	}

	/**
	 * Sets value for key. If key exists its value is replaced even
	 * if it is an array of multiple values. If key does
	 * not yet exist it will be created with the respective value.
	 * The file on disk is not being updated.
	 * key must neither be null nor empty.
	 *
	 * Params:
	 *     key = the _key to store value for
	 *     value = the _value to be stored for key
	 * Throws: JSONException
	 * See_Also: `kvstore.KVStore.append`
	 */
	public void set(const string key, const string value)
	{
		if((key is null) || (key.length == 0)) return;

		if(this.hasKey(key))
		{
			ulong len = 1;

			if(this.json[key].type == JSONType.array)
			{
				if(this.maxdepth == this.json[key].array.length)
					len = this.json[key].array.length;
			}

			this.json.object[key] = value; // override old value
			if(len > 1) this.recalculateMaximumDepth();
		}
		else
		{
			this.json.object[key] = value; // create new entry
			++(this.keyno);
			if(this.maxdepth < 1) this.maxdepth = 1;
		}

		this.dirty = true;
	}

	/**
	 * Set multiple _values for key. If key exists its old value
	 * (which can be an array) is overriden. If key does
	 * not yet exist it will be created with the respective values.
	 * The file on disk is not being updated.
	 * Both, key and values, must neither be null nor empty.
	 *
	 * Params:
	 *     key = the _key to store value for
	 *     values = an array of _values to be stored for key
	 * Throws: JSONException
	 * See_Also: `kvstore.KVStore.append`
	 */
	public void set(const string key, const string[] values)
	{
		if((key is null) || (key.length == 0)) return;
		if((values is null) || (values.length == 0)) return;

		// maximum depth handled by "this.set()"
		if(values.length == 1) this.set(key, values[0]); // create or override
		else
		{
			this.set(key, values[0]); // create or override
			this.append(key, values[1..$]); // then append rest of values
		}
	}

	/**
	 * Appends value to a list of values stored for key.
	 * If key does not exist yet it is inserted and value is
	 * stored as its only value (a JSON string, not an array).
	 * If key exists but has only one _value attached, a JSON
	 * array is created from the new value and the _value that
	 * had already been present before. That array is stored
	 * as *_value* for key.
	 * The file on disk is not being updated.
	 * Both, key and value, must neither be null nor empty.
	 * If value already exists in the list stored for key,
	 * it not appended again.
	 *
	 * Params:
	 *     key = the _key to _append value at
	 *     value = the _value to be appended for key
	 * Throws: JSONException
	 * See_Also: `kvstore.KVStore.set`
	 */
	public void append(const string key, const string value)
	{
		if((key is null) || (key.length == 0)) return;
		if((value is null) || (value.length == 0)) return;

		if(this.hasKey(key))
		{
			if(this.json[key].type == JSONType.array)
			{
				// skip if "value" already in array
				foreach(ref v; this.json[key].array)
					if(v.str == value) return;

				// append "value" to array
				this.json[key].array ~= JSONValue(value);
				immutable ulong len = this.json[key].array.length;
				if(this.maxdepth < len) this.maxdepth = len;
			}
			else
			{
				// create array from previous and new value
				this.json.object[key] = JSONValue([this.json[key].str, value]);
				if(this.maxdepth < 2) this.maxdepth = 2;
			}

			this.dirty = true;
		}
		else this.set(key, value); // create key
	}

	/**
	 * Appends multiple _values to a list of _values stored for key.
	 * If key does not exist yet it is inserted and all elements of
	 * values are stored as a JSON array.
	 * If key exists all elements of values is appended to the key's
	 * array of _values.
	 * The file on disk is not being updated.
	 * key must neither be null nor empty.
	 * If values is null or empty nothing is appended.
	 *
	 * Params:
	 *     key = the _key to _append value at
	 *     values = the array of _values to be appended for key
	 * Throws: JSONException
	 * See_Also: `kvstore.KVStore.set`
	 */
	public void append(const string key, const string[] values)
	{
		if((key is null) || (key.length == 0)) return;
		if((values is null) || (values.length == 0)) return;

		if(this.hasKey(key))
		{
			if(values.length == 1) this.append(key, values[0]);
			else
			{
				immutable ulong len = values.length;
				foreach(v; values) this.append(key, v);
				if(len > this.maxdepth) this.maxdepth = len;
			}
		}
		else
		{
			if(values.length == 1) this.set(key, values[0]);
			else
			{
				immutable ulong len = values.length;
				this.json.object[key] = parseJSON("[]"); // create JSON array
				foreach(v; values) this.json.object[key].array ~= JSONValue(v);
				++(this.keyno);
				if(len > this.maxdepth) this.maxdepth = len;
				this.dirty = true;
			}
		}
	}

	/**
	 * Removes the entry referred to by key from the in-memory
	 * store. The file on disk is not being updated.
	 * key must neither be null nor empty.
	 *
	 * Params:
	 *     key = the key to be removed from the store
	 * Throws: JSONException
	 */
	public void remove(const string key)
	{
		// input validation in "this.hasKey()"
		if(this.hasKey(key))
		{
			immutable ulong dep = ((this.json[key].type == JSONType.array) ?
								   this.json[key].array.length : 1);
			this.json.object.remove(key);
			--(this.keyno);
			this.dirty = true;

			if(this.keyno == 0) { this.maxdepth = 0; return; }
			if(dep == this.maxdepth) this.recalculateMaximumDepth();
		}
	}

	/**
	 * Swaps keys and values of all entries in the store in
	 * memory. If there are no entries there is nothing to
	 * do which is considered a successful operation and true
	 * is returned. The operation is only permitted if for
	 * all keys the maximum number of values (their *depth*)
	 * is 1.
	 * true is returned only if the swap operation succeeds
	 * for all entries in the store (see overloaded function).
	 * It is possible to enforce *uniqueness*. When
	 * trying to swap the key and value of an entry the new
	 * entry is only inserted into the store if that key had
	 * not been present before. If uniqueness is required and
	 * a key already exists the operation fails. Otherwise the
	 * new value is appended to the present key.
	 *
	 * Note that not only all values (becoming the new keys) need
	 * to be unique for this requirement, but there must also be
	 * no key being equal to any of the *values* in the store,
	 * because the store is currently altered *in-place*. Also
	 * the situation should be kept in mind, where, e.g., having
	 * entries `{ key1: key2 }` and `{ key2: value2 }`, with
	 * `unique = false`: When `key1` is swapped it is appended
	 * to `key2`, getting `{ key2: [value2, key1] }`. `key2` is
	 * still left to be swapped but now has a *depth* of 2 which
	 * is not allowed.
	 * **Caution**: If only one of the _swap operations for a
	 * single entry fails the whole operation is aborted and
	 * store remains in an inconsistent state. The original
	 * state cannot be recovered in that case. (This may change
	 * in the future). There are several possibilities to
	 * implement the ability for the store to *roll back* to a
	 * consistent state. 1. Insert the swapped entries into a
	 * new store and replace the old store if there was no error.
	 * (This would require twice the space in RAM.) 2. Check the
	 * uniqueness of the *union* of values and keys before any
	 * swapping is done. (Since this is a costly operation it
	 * would decrease the overall speed of the _swap operation
	 * significantly.) 3. Save the current store to disk (or
	 * create a backup), perform the operation, and reload the
	 * original store from disk (or restore the backup) if the
	 * swapping fails. (This would also decrease the speed of the
	 * operation, because of the additional hard drive accesses
	 * on possibly large stores.)
	 *
	 * Params:
	 *     unique = true to abort on two same keys, false to
	 *         append the new value to an existing key
	 *         (defaults to false)
	 * Returns: true on success, false on failure
	 * Throws: JSONException
	 */
	public bool swap(const bool unique = false)
	{
		if(this.keyno == 0) return true;
		if(this.maxdepth > 1) return false;

		foreach(k; this.json.object.keys)
			if(!swap(k, unique)) return false;
		return true;
	}

	/**
	 * Swaps the entry of key be creating a new entry
	 * with the old value being used as new _key and
	 * the old _key as its value, and then removing the
	 * old entry of key.
	 * If key is not found false is returned.
	 * If the _key of the new entry already exists its value
	 * is appended to the present _key. To avoid that behaviour
	 * unique can to set to true to abort the operation with
	 * failure if the new _key already exists and return false.
	 * key must neither be null nor empty.
	 *
	 * Params:
	 *     key = the _key of the entry to be swapped
	 *     unique = true to abort if the new key already
	 *         exists, false to append the new value to
	 *         an existing key
	 *         (defaults to false)
	 * Returns: true on success, false on failure
	 * Throws: JSONException
	 */
	public bool swap(const string key, const bool unique = false)
	{
		// input validation in "this.hasKey()"
		if(!this.hasKey(key)) return false;

		string value;

		if(this.json[key].type == JSONType.array)
		{
			if(this.json[key].array.length > 1) return false;
			value = this.json[key].array[0].str;
		}
		else value = this.json[key].str;

		if(this.hasKey(value))
		{
			if(unique) return false;
			this.append(value, key); // updates this.maxdepth
			this.remove(key); // updates this.keyno as no additional key was added
		}
		else
		{
			// this.keyno stays consistent as 1 key is added and 1 key is removed
			this.json.object[value] = key;
			this.json.object.remove(key);
			this.dirty = true;
		}

		return true;
	}

	/**
	 * Return the _key in the store being _closest to key.
	 * If key is contained in the store then key is returned.
	 * If the store is empty, null is returned.
	 * Similarity between the keys is computed based on the private
	 * `kvstore.distance` function implementing the *Levenshtein _distance*.
	 * If several keys with the same *Levenshtein _distance* to key are found
	 * their respective length is considered and the one with the length
	 * _clostest to the length of key is used as the _closest _key. If
	 * *then* several keys with the same length are found their ASCII
	 * character code _distance of the first differing character is
	 * considered, as well, and the one being "_closest" to the one in key
	 * is used.
	 * Note: Computing the Levenshtein distance between two keys has a
	 * time complexity of `O(m * n)` with `m` being the length of the first
	 * _key, and `n` being the length of the second _key. _Distance is
	 * computed between key and each _key in the store.
	 * The array of keys will be sorted in advance to save some
	 * operations using the default *Phobos* sorting algorithm which
	 * performs in `O(k * log(k))`, with `k` being the number of keys.
	 * This makes closest as costly as
	 * `O((k * (m * n)) + (k * log(k)))` which is approximately
	 * `O(k * a^2)` on average, with `k` being the number of keys in
	 * the store and `a` being the average _key length. This is
	 * actually an oversimplification but may give a hint on the
	 * runtime performance of this operation.
	 * key must neither be null nor empty.
	 *
	 * Params:
	 *		 key = the _key for which to search the _closest one in the store
	 * Returns: the _key being _clostest to key
	 */
	public pure string closest(const string key) const
	{
		if((key is null) || (key.length == 0)) return null;
		if(this.empty) return null;
		if(this.hasKey(key)) return key;

		if(this.count == 1)
			return this.json.object.keys.front;

		string[] ids = this.json.object.keys.sort.release;

		immutable ulong keylen = key.length;
		ulong mindist = 18_446_744_073_709_551_615; // (2^(64) - 1)
		ulong minlendist = 18_446_744_073_709_551_615; // (2^(64) - 1)
		ubyte minchardist = 255; // (2^(8) - 1)
		ulong idx = 0;
		ulong dist, lendist;
		ubyte chardist;

		for(ulong i = 0; i < ids.length; i++)
		{
			dist = key.distance(ids[i]);

			if(dist < mindist)
			{
				mindist = dist;
				idx = i;
			}

			if(dist <= mindist)
			{
				lendist = (cast(long)(ids[i].length - keylen)).abs;

				if(lendist < minlendist)
				{
					minlendist = lendist;
					idx = i;
				}

				if(lendist <= minlendist)
				{
					ulong pos = cast(ulong)(cast(long)(key.compare(ids[i]))).abs;
					if(pos > 0) --pos;
					chardist = key[pos].chardist(ids[i][pos]);

					if(chardist < minchardist)
					{
						minchardist = chardist;
						idx = i;
					}
				}
			}
		}

		return ids[idx];
	}

	/**
	 * Retrieves the number of values stored for key.
	 * If key is not found in the store -1 is returned.
	 * key must neither be null nor empty.
	 *
	 * Params:
	 *     key = the _key to retrieve the value number for
	 * Returns: the number of stored values for key
	 *     or 0 if key is not in the store
	 * Throws: JSONException
	 */
	public pure ulong depth(const string key) const
	{
		// input validation in "this.hasKey()"
		if(this.hasKey(key))
		{
			if(this.json[key].type == JSONType.array)
				return this.json[key].array.length;
			return 1; // if key exists and is not an array it has 1 value
		}

		return 0;
	}

	/**
	 * Returns the full JSON _entry for key serialized as string.
	 * key is part of that JSON entry, as well.
	 * key must neither be null nor empty.
	 *
	 * Params:
	 *     key = the _key for which to get its _entry as JSON string
	 * Returns: key's store entry serialized as JSON string
	 * Throws: JSONException
	 */
	public string entry(const string key) const
	{
		// input validation in "this.hasKey()"
		if(this.hasKey(key))
			return "{\"" ~ key ~ "\":" ~
				toJSON(this.json[key], false, JSONOptions.none) ~ "}";
		return null;
	}

	/**
	 * Returns a string array of the form `[key, value]` if there
	 * is only one value. A string array of the form
	 * `[key, value, value, ...]` is returned if there are
	 * multiple values.
	 * key must neither be null nor empty.
	 *
	 * Params:
	 *     key = the _key for which to get its _key/value tuple
	 * Returns: a two-element string array containing key and the
	 *     corresponding value, or a larger string array of there
	 *     are multiple values
	 * Throws: JSONException
	 */
	public string[] tuple(const string key) const
	{
		// input validation in "this.hasKey()"
		if(!this.hasKey(key)) return null;

		if(this.json[key].type == JSONType.string)
			return [key, this.json[key].str];
		else if(this.json[key].type == JSONType.array)
		{
			string[] tup;
			tup.length = (this.json[key].array.length + 1);
			tup[0] = key.dup;

			foreach(size_t i, JSONValue v; this.json[key].array)
				tup[(i + 1)] = v.str;
			return tup;
		}
		else return [key, this.json[key].str];
	}

	/**
	 * Returns an array of _keys that are currently stored in
	 * the database in memory. The elements in the returned array
	 * can be in any order.
	 *
	 * Returns: a string array of _keys currently stored
	 * Throws: JSONException
	 */
	public pure string[] keys() const @property
	{
		return this.json.object.keys;
	}

	/**
	 * Returns a sorted array of _keys that are currently stored in
	 * the database in memory. Ordering of the elements is done by
	 * the private `compare` function of this module.
	 *
	 * Returns: a sorted string array of _keys currently stored
	 * Throws: JSONException
	 */
	public pure string[] sortedKeys() const @property
	{
		return sort!((a, b) => compare(a, b) < 0)(this.json.object.keys)
			.release();
	}

	/**
	 * Determine if the store has no elements.
	 *
	 * Returns: true if the store is empty, false otherwise
	 */
	public pure bool empty() const @property
	{
		return (this.keyno <= 0);
	}

	/**
	 * Gets the number of elements currently in the key/value store.
	 *
	 * Returns: the number of entries currently stored
	 */
	public pure nothrow ulong count() const @property @safe @nogc
	{
		return this.keyno;
	}

	/**
	 * Gets the value number of the key with most values.
	 *
	 * Returns: the maximum number of values
	 */
	public pure nothrow ulong maxDepth() const @property @safe @nogc
	{
		return this.maxdepth;
	}

	/**
	 * Return whether the in-memory store has been altered and needs
	 * to be saved to disk.
	 *
	 * Returns: true if the in-memory store is dirty, false if the store
	 *     in memory is the same as the store on disk
	 * See_Also: `kvstore.KVStore.isClean`
	 */
	 public pure nothrow bool isDirty() const @property @safe @nogc
	 {
		 return this.dirty;
	 }

	/**
	 * Return whether the in-memory store is the same as the store on disk.
	 *
	 * Returns: true if the store has been saved, false if not
	 * See_Also: `kvstore.KVStore.isDirty`
	 */
	 public pure nothrow bool isClean() const @property @safe @nogc
	 {
		 return !this.dirty;
	 }

	/**
	 * Returns the amount of disk space occupied by the data file.
	 * The space is given in bytes.
	 * If the file does not exist, -1 is returned.
	 *
	 * Returns: data file size in bytes, or -1 if the file does not exist
	 * Throws: FileException
	 */
	public long size() const @property
	{
		if(this.file.exists) return getSize(this.file);
		else return (-1);
	}

	/**
	 * Return the filename associated with the key/value store.
	 * The store file may or may not already exist in the file system.
	 *
	 * Returns: the filename of the key/value store
	 */
	public pure nothrow string getFilename() const @property @safe @nogc
	{
		return this.file;
	}

	/*
	 * Loop through the entries and find the one with most values.
	 * Throws: JSONException
	 */
	private void recalculateMaximumDepth()
	{
		if(this.keyno == 0)
		{
			this.maxdepth = 0;
			return;
		}

		ulong dep = 1;

		foreach(k; this.json.object.keys)
		{
			if(this.json[k].type == JSONType.array)
			{
				if(this.json[k].array.length > dep)
					dep = this.json[k].array.length;
			}
		}

		this.maxdepth = dep;
	}

	/**
	 * Returns the full database serialized as prettified JSON string.
	 * No escaping of e.g. non-ASCII characters is done.
	 * The database currently loaded is returned, not the file on disk.
	 *
	 * Overrides: Object._toString()
	 * Returns: all entries serialized as prettified JSON string
	 * Throws: JSONException
	 */
	public override string toString() const @property
	{
		return toJSON(this.json, true, JSONOptions.none);
	}
}

/**
 * Returns the version of this library.
 *
 * Returns: the version of this library
 */
public pure nothrow string libraryVersion() @safe @nogc
{
	return VERSION;
}

/**
 * Return the first differing character (1-indexed!) in lhs, or rhs,
 * respectively. (E.g. if lhs[0] > rhs[0] => return 1)
 * If lhs equals rhs, 0 is returned, if lhs is smaller than rhs,
 * a value smaller than 0 is returned, otherwise a value greater than
 * 0 is returned.
 * This function is required by kvstore.KVStore.swap and
 * kvstore.KVStore.sortedKeys.
 *
 * Params:
 *     lhs = left hand side of the comparison (left operand)
 *     rhs = right hand side of the comparision (right operand)
 * Returns: 0 iff lhs and rhs are equal, or the (1-indexed) position
 *     of the first differing character (negative iff lhs < rhs)
 */
private pure long compare(const string lhs, const string rhs) @nogc
{
	if((lhs is null) && (rhs is null)) return 0L;
	else if((lhs is null) && (rhs !is null)) return -1L;
	else if((lhs !is null) && (rhs is null)) return 1L;

	for(long i = 0; i < min(lhs.length, rhs.length); ++i)
	{
		if(lhs[i] < rhs[i]) return ((i + 1) * (-1));
		if(lhs[i] > rhs[i]) return (i + 1);
	}

	if(lhs.length < rhs.length) return (lhs.length * (-1));
	else if(lhs.length > rhs.length) return rhs.length;
	return 0L;
}

/**
 * Calculate distance between two ASCII characters by subtracting
 * lhs from rhs and making up the absolute value of that difference.
 * This function is required by kvstore.KVStore.closest.
 *
 * Params:
 *     lhs = left hand side of the operation
 *     rhs = right hand side of the operation
 * Returns: absolute value of the difference of lhs and rhs
 * TODO: consider type of character (e.g. numbers are closer to
 * each other than a number and a special character)
 */
private pure ubyte chardist(const char lhs, const char rhs) @nogc
{
	return cast(ubyte)(cast(int)rhs - cast(int)lhs).abs;
}

/**
 * Compute the basic Levenshtein distance between lhs and rhs.
 * If, and only if, lhs equals rhs 0 is returned.
 * The lower bound is the difference of the lengths lhs and rhs.
 * The upper bound is twice the length of the longer string.
 * If lhs and rhs are of the same length the *Hamming distance* is
 * an upper bound, as well.
 * distance is commutative, i.e. `distance(a, b) == distance(b, a)`
 * and the *triangle inequality* holds:
 * `distance(a, c) <= distance(a, b) + distance(b, c)`.
 * The time complexity of distance is `O(m * n)` where `m` is the
 * length of lhs, and `n` is the length of rhs.
 * This function is required by kvstore.KVStore.closest.
 *
 * Params:
 *     lhs = left hand side of distance operation (left operand)
 *     rhs = right hand side of distance operation (right operand)
 *     penalizeSubstitution = a "substitution" operation required
 *         to make lhs and rhs equal occasionally adds a greater
 *         distance than a "deletion" or "insertion" operation.
 * Returns: the Levenshtein distance between lhs and rhs
 */
private pure ulong distance(const string lhs, const string rhs,
							const bool penalizeSubstitution = false)
{
	if((lhs is null) && (rhs is null)) return 0L;
	else if((lhs is null) && (rhs !is null)) return rhs.length;
	else if((lhs !is null) && (rhs is null)) return lhs.length;

	immutable ulong lhslen = lhs.length;
	immutable ulong rhslen = rhs.length;

	if(rhslen == 0) return lhslen;
	else if(lhslen == 0) return rhslen;

	ulong[] v0, v1;
	ulong cdel, cins, csub;

	v0.length = (rhslen + 1);
	v1.length = (rhslen + 1);

	for(ulong i = 0; i < (rhslen + 1); i++) v0[i] = i;

	for(ulong i = 0; i < lhslen; i++)
	{
		v1[0] = (i + 1);

		for(ulong j = 0; j < rhslen; j++)
		{
			cdel = (v0[(j + 1)] + 1);
			cins = (v1[j] + 1);

			if(lhs[i] == rhs[j]) csub = v0[j];
			else
				csub = (v0[j] + (penalizeSubstitution ? 2 : 1));

			v1[(j + 1)] = min(min(cdel, cins), csub);
		}

		v0 = v1.dup;
	}

	return v0[rhslen];
}

/**
 * Convert the string representation of a JSON array to an array
 * of strings. value must be a valid serialization of a JSON array
 * of strings or a single (JSON) string.
 *
 * Params:
 *     value = the string to be converted to an array
 * Returns: a string array built from value
 */
private pure string[] toArray(const string value)
{
	if((value is null) || (value.length == 0)) return [];

	try
	{
		JSONValue json = parseJSON(value);
		return toArray(json);
	}
	catch(const JSONException jsonException) { return [value]; }
}

/**
 * Convert a JSON array of strings to a string array.
 * value must be a valid JSONValue of JSONType "array" or "string".
 *
 * Params:
 *     value = a JSON value to be converted to an array
 * Returns: a string array built from value
 */
private pure string[] toArray(const JSONValue value)
{
	string[] coll;

	try
	{
		if(value.type == JSONType.array)
		{
			coll.length = value.array.length;
			for(long i = 0; i < coll.length; i++)
				coll[i] = value.array[i].str.dup;
		}
		else if(value.type == JSONType.string)
		{
			coll.length = 1;
			coll[0] = value.str;
		}
		else coll.length = 0;
	}
	catch(const JSONException jsonException) { coll.length = 0; return coll; }

	return coll;
}

private unittest
{
	import std.file : exists;

	KVStore store = new KVStore("unittest.kvs");

	assert(!"unittest.kvs".exists);

	/* test isDirty, isClean, getFilename, size, count,
		 depth, maxDepth, key, sortedKeys, clear, drop,
		 empty */

	assert(store.empty);
	assert(store.isDirty);
	assert(!store.isClean);
	assert(store.getFilename(), "unittest.kvs");

	assert(store.size == (-1));
	assert(store.count == 0);
	assert(!store.hasKey("unittest"));
	assert(store.get("unittest") is null);

	store.set("key", "value");
	assert(store.count == 1);
	assert(!store.empty);
	assert(store.get("key") == "value");

	store.append("hello", "dlang");
	assert(store.count == 2);
	assert(store.depth("hello") == 1);
	assert(store.maxDepth == 1);
	assert(store.keys == ["key", "hello"]);
	assert(store.sortedKeys == ["hello", "key"]);

	store.save();
	assert(store.isClean);
	assert(!store.isDirty);
	assert("unittest.kvs".exists);
	assert(store.size > (0L));

	store.clear();
	assert(store.empty);
	assert(store.count == 0);
	assert(store.maxDepth == 0);
	assert(store.get("key") is null);

	assert(store.drop());
	assert(store.size == (-1L));
	assert(!"unittest.kvs".exists);

	/* test get, getFirst, getAll */

	store.set("key", "value1");
	assert(store.maxDepth == 1);
	assert(store.get("key") == "value1");

	store.append("key", ["value2", "value3", "value4", "value5"]);
	assert(store.depth("key") == 5);
	assert(store.maxDepth == 5);
	assert(store.get("key") ==
		"[\"value1\",\"value2\",\"value3\",\"value4\",\"value5\"]");
	assert(store.getFirst("key") == "value1");
	assert(store.getAll("key") ==
		["value1", "value2", "value3", "value4", "value5"]);

	store.clear();
	assert(store.maxDepth == 0);

	/* test set, append, remove */

	// insert keys via set(string, string)
	store.set("1", "one");
	store.set("2", "two");
	assert(store.get("1") == "one");
	assert(store.getFirst("2") == "two");
	assert(store.getAll("2") == ["two"]);
	assert(store.keys == ["2", "1"]);
	assert(store.sortedKeys == ["1", "2"]);

	// override a key via set(string, string)
	store.set("1", "three");
	assert(store.get("1") == "three");

	// override a key via set(string, string[])
	store.set("1", ["four", "five"]);
	assert(store.depth("1") == 2);
	assert(store.getAll("1") == ["four", "five"]);

	// insert a key via append(string, string)
	store.append("3", "six");
	assert(store.hasKey("3"));
	assert(store.get("3") == "six");

	// override a key via append(string, string)
	store.append("3", "seven");
	assert(store.getAll("3") == ["six", "seven"]);

	// insert a key via append(string, string[])
	store.append("4", ["eight", "nine", "ten"]);
	assert(store.hasKey("4"));
	assert(!store.hasKey("0"));
	assert(store.depth("4") == 3);

	assert(store.count == 4);

	store.remove("3");
	assert(!store.hasKey("3"));
	assert(store.sortedKeys == ["1", "2", "4"]);
	assert(store.count == 3);

	store.clear();
	assert(!store.hasKey("4"));
	assert(store.count == 0);
	assert(store.isDirty);

	/* test entry, tuple */

	store.set("key1", "value1");
	assert(store.entry("key1") == "{\"key1\":\"value1\"}");
	assert(store.tuple("key1") == ["key1", "value1"]);

	store.set("key2", ["value2.0", "value2.1", "value2.2"]);
	assert(store.entry("key2") ==
		"{\"key2\":[\"value2.0\",\"value2.1\",\"value2.2\"]}");
	assert(store.tuple("key2") ==
		["key2", "value2.0", "value2.1", "value2.2"]);

	store.clear();

	/* test toString */

	store.set("key", "value");
	assert(store.count == 1);
	assert(store.depth("key") == 1);
	assert(store.maxDepth == 1);

	store.set("hello", "world");
	store.append("hello", "of");
	store.append("hello", "d");
	assert(store.count == 2);
	assert(store.depth("hello") == 3);
	assert(store.maxDepth == 3);

	JSONValue json = parseJSON(store.toString());
	assert(toJSON(json, false, JSONOptions.none) ==
		"{\"hello\":[\"world\",\"of\",\"d\"],\"key\":\"value\"}");

	store.clear();
	assert(store.count == 0);
	assert(store.get("key") is null);
	assert(store.toString() == "{}");

	json = parseJSON(store.toString());
	assert(toJSON(json, false, JSONOptions.none) == "{}");

	/* test swap */

	store.set("United States of America", "US");
	store.set("Great Britain", "UK");
	store.set("Switzerland", "CH");
	store.set("FR", "France");
	store.set("Netherlands", "NL");
	store.set("Germany", "DE");
	store.set("Italy", "IT");

	assert(store.swap("FR", false));
	assert(store.hasKey("France"));
	assert(!store.hasKey("FR"));

	assert(store.swap(true));
	assert(!store.hasKey("United States of America"));
	assert(store.hasKey("DE"));
	assert(store.hasKey("FR"));

	store.set("Belgium", "NL");
	assert(store.swap("Belgium", false));
	assert(!store.hasKey("Belgium"));
	assert(store.hasKey("NL"));
	assert(store.depth("NL") == 2);
	assert(store.tuple("NL") == ["NL", "Netherlands", "Belgium"]);

	store.set("Denmark", "DE");
	assert(!store.swap("Denmark", true));
	assert(store.hasKey("DE"));
	assert(store.hasKey("Denmark"));
	store.clear();

	/* test compare */

	assert(compare("abc", "def") == -1L);
	assert(compare("def", "abc") == 1L);
	assert(compare("one", "one") == 0L);
	assert(compare(null, null) == 0L);
	assert(compare(null, "null") == -1L);
	assert(compare("null", null) == 1L);
	assert(compare("head", "heap") == -4L);

	/* test chardist */

	assert(chardist('a', 'a') == 0);
	assert(chardist('a', 'c') == 2);
	assert(chardist('a', 'c') == chardist('c', 'a'));
	assert(chardist('z', 'a') == 25);

	/* test distance */

	// null and length
	assert(distance(null, "hello world") == "hello world".length);
	assert(distance("Levenshtein", null) == "Levenshtein".length);
	assert(distance(null, null) == 0);
	assert(distance("hello", "hello world") <= "hello world".length);

	// equality
	assert(distance("abc", "abc") == 0);

	// commutativity
	assert(distance("abc", "def") == distance("def", "abc"));

	// triangle inequality
	assert(distance("aaa", "aac") <=
		   (distance("aaa", "aab") + distance("aab", "aac")));

	// deletion
	assert(distance("ab", "abc") == 1);

	// insertion
	assert(distance("abc", "abcd") == 1);

	// substitution
	assert(distance("abc", "bbc") == 1);
	assert(distance("abc", "abc ") == distance("abc", " abc"));

	// penalize substitution
	assert(distance("hello", "world", true) <= 10);
	assert(distance("hello", "world", false) == 4);

	/* test closest */

	store.set("hello", "world");
	store.set("head", ["shoulders", "knees", "and", "toes"]);
	store.set("heap", "one");
	store.append("heap",
				 ["two", "three", "four", "five", "six", "seven"]);

	assert(store.count() == 3);
	assert(store.isDirty);
	assert(store.depth("head") == 4);
	assert(store.depth("heap") == 7);
	assert(store.maxDepth == 7);
	assert(store.tuple("head") ==
		   ["head", "shoulders", "knees", "and", "toes"]);

	assert(store.closest("hello") == "hello");
	assert(store.closest("head") == "head");
	assert(store.closest("heap") == "heap");
	assert(store.closest("hence") == "hello");
	assert(store.closest("heae") == "head");
	assert(store.closest("hean") == "heap");
	assert(store.closest("help") ==	"heap");
	assert(store.closest("sunset") == "hello");
	assert(store.closest(null) is null);
	assert(store.closest("") is null);

	KVStore store2 = new KVStore();
	assert(store2.empty);
	assert(store2.closest("hello") == null);

	store2.set("hello", "world");
	assert(store2.closest("parkinglot") == "hello");
	assert(store2.closest("world") == "hello");

	store2.clear();
	store2 = null;

	/* test constructors */

	// copy constructor
	KVStore copy = new KVStore(store, "copied.kvs");
	assert(!copy.empty);
	assert(copy.count == 3);
	assert(copy.maxDepth == 7);
	assert(copy.isDirty);
	assert(!copy.isClean);
	assert(copy.getFilename == "copied.kvs");
	assert(!"copied.kvs".exists);

	// default constructor
	KVStore def = new KVStore();
	assert(def.getFilename == "default.kvs");
	assert(def.empty);
	assert(!"default.kvs".exists);
	assert(def.count == 0);
	assert(def.maxDepth == 0);
	assert(def.isDirty);
	assert(!def.isClean);

	def.clear();
	copy.clear();
	store.clear();
	assert(!store.drop());

	def = null;
	copy = null;
	store = null;

	/* test toArray */

	assert(toArray("[\"world\",\"of\",\"d\"]") == ["world", "of", "d"]);
	assert(toArray(parseJSON("[\"world\",\"of\",\"d\"]")) == ["world", "of", "d"]);
	assert(toArray("value") == ["value"]);
	assert(toArray("[\"value\"]") == ["value"]);
	assert(toArray(parseJSON("[\"value\"]")) == ["value"]);
}
